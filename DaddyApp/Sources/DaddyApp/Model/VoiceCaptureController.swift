import AVFoundation
import Speech

enum VoiceCaptureState {
    case idle
    case recording
    case transcribing
}

/// A trivial lock-guarded box — the two permission callbacks below can fire
/// on different threads, so a plain captured `var` would be a data race.
private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Daddy's own mic capture: double-tap Option starts recording, a second tap
/// stops and hands off the final transcript, Esc cancels. Runs on-device
/// (`requiresOnDeviceRecognition`) — no network dependency, matches the
/// app's local-first bias elsewhere.
@MainActor
@Observable
final class VoiceCaptureController {
    private(set) var state: VoiceCaptureState = .idle

    private let hotkeyMonitor = OptionDoubleTapMonitor()
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptionGeneration = 0

    /// Fired with the final transcript once a recording completes normally
    /// (not cancelled). The caller resolves and executes it.
    var onTranscript: ((String) -> Void)?

    func start() {
        hotkeyMonitor.onDoubleTap = { [weak self] in self?.beginRecording() }
        hotkeyMonitor.onSingleTapWhileActive = { [weak self] in self?.handleTapWhileActive() }
        hotkeyMonitor.onEscape = { [weak self] in self?.cancelRecording() }
        hotkeyMonitor.start()
    }

    func stop() {
        hotkeyMonitor.stop()
        cancelRecording()
    }

    private func beginRecording() {
        guard state == .idle else { return }
        Self.requestPermissionsIfNeeded { [weak self] granted in
            guard granted else { return }
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.startEngine()
            }
        }
    }

    private func startEngine() {
        guard state == .idle, let speechRecognizer, speechRecognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapBlock(appendingTo: request))

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            recognitionRequest = nil
            inputNode.removeTap(onBus: 0)
            return
        }

        state = .recording
        hotkeyMonitor.isActive = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognitionEvent(result: result, error: error)
            }
        }
    }

    /// `nonisolated`, same reasoning as `requestPermissionsIfNeeded`: this
    /// block runs on CoreAudio's real-time tap thread, never main. Written
    /// as a closure literal directly inside a `@MainActor` method, Swift
    /// infers it as MainActor-isolated even though it never touches `self`
    /// — and the runtime isolation check traps the instant CoreAudio invokes
    /// it off-main. Building it in a `nonisolated` factory instead breaks
    /// that inference; `request` itself is fine to touch from any thread,
    /// it's designed for exactly this real-time callback use.
    private nonisolated static func makeTapBlock(
        appendingTo request: SFSpeechAudioBufferRecognitionRequest
    ) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in request.append(buffer) }
    }

    private func handleTapWhileActive() {
        switch state {
        case .recording:
            finishRecording()
        case .transcribing:
            teardownToIdle()
        case .idle:
            break
        }
    }

    private func finishRecording() {
        guard state == .recording else { return }
        state = .transcribing
        // Stays active through transcribing so a tap or Esc always gets out,
        // even before the recognizer answers.
        transcriptionGeneration += 1
        let generation = transcriptionGeneration
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        // Backstop: on-device recognition sometimes never calls back. The
        // pill must never outlive this.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.handleTranscriptionTimeout(generation: generation)
        }
    }

    func cancelRecording() {
        guard state == .recording || state == .transcribing else { return }
        teardownToIdle()
    }

    /// Every exit path funnels here — engine, request, task, state — so the
    /// pill can never stick.
    private func teardownToIdle() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        hotkeyMonitor.isActive = false
        state = .idle
    }

    private func handleRecognitionEvent(result: SFSpeechRecognitionResult?, error: Error?) {
        if error != nil {
            teardownToIdle()
            return
        }
        guard let result, result.isFinal else { return }
        handleFinalTranscript(result.bestTranscription.formattedString)
    }

    private func handleTranscriptionTimeout(generation: Int) {
        guard generation == transcriptionGeneration, state == .transcribing else { return }
        teardownToIdle()
    }

    private func handleFinalTranscript(_ text: String) {
        recognitionTask = nil
        recognitionRequest = nil
        hotkeyMonitor.isActive = false
        state = .idle
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onTranscript?(text)
    }

    /// `nonisolated`, no `self`/MainActor capture, and — critically — the
    /// two requests fire independently rather than one nested inside the
    /// other's completion closure. Two real bugs were stacked here before:
    /// (1) a closure written inside a `@MainActor` method that captures
    /// `self` gets inferred as MainActor-isolated, and Swift's runtime
    /// isolation check traps the instant TCC invokes it from its own
    /// internal thread; (2) issuing a *second* TCC request synchronously
    /// from inside the first request's own reply-handling callback is
    /// apparently unsafe in its own right — confirmed because the crash
    /// happens right after the speech dialog is dismissed, at the point the
    /// mic request fires nested inside that callback. Requesting both
    /// up front with a `DispatchGroup`, neither depending on the other's
    /// callback, avoids both at once.
    private nonisolated static func requestPermissionsIfNeeded(completion: @escaping @Sendable (Bool) -> Void) {
        let group = DispatchGroup()
        let speechOK = LockedBool()
        let micOK = LockedBool()

        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechOK.value = status == .authorized
            group.leave()
        }

        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            micOK.value = granted
            group.leave()
        }

        group.notify(queue: .main) {
            completion(speechOK.value && micOK.value)
        }
    }
}
