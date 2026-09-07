# Voice trigger options (Jarvis / step D)

Status: double-tap Option currently does nothing. No pill, no mic/speech
prompts, no freeze. Launch-freeze fixed (see below). Mic/speech prompts never
firing is a consequence, not a separate bug — they are requested lazily inside
`beginRecording`, which never runs because the tap is never detected.

## What broke the app (fixed)

Registering `NSEvent.addGlobalMonitorForEvents` inside `MockStore.init`
(pre-activation) wedged ALL app input: window rendered, runloop healthy, zero
clicks/keys, invisible in menu bar. Proven by bisect (clean main = alive,
dirty = dead; disabling only the monitor install = alive).

Fix (in place): `VoiceCaptureController.start()` is called from
`RootView.onAppear` instead of `MockStore.init`
(`DaddyApp/Sources/DaddyApp/Scenes/RootView.swift`). Monitors install after
first render. App launches alive.

Also in place: recording pill in `RootView` (red dot + Listening…/
Transcribing…), since nothing read `voiceCaptureController.state` before.

## Option A — global NSEvent monitors (current code)

How: `OptionDoubleTapMonitor` installs global `.flagsChanged` + `.keyDown`
monitors, detects two Option down-edges within 400ms. Esc cancels, tap stops.

Problem: zero events delivered, even with JarvDaddysHome enabled in
Settings → Privacy → Input Monitoring. Proven by temporary stderr logging:
install runs, zero `flagsChanged` callbacks ever arrive. No system prompt ever
appeared either.

Likely cause: approval is tied to code signature. `bundle.sh` ad-hoc
re-signs on every build, invalidating approval silently (no re-prompt).
Mitigation attempted: signed `JarvDaddysHome.app` with stable cert
`Apple Development: Aaron Ambrosi (2Q7MBD643R)` — still nothing.

To retry: remove the Jarv entry from Input Monitoring, re-add the current
build, toggle off/on, relaunch, tap. If delivery starts, re-approve once per
rebuild (ad-hoc) or never again (stable cert). Fragile either way.

## Option B — poll `NSEvent.modifierFlags` (recommended)

How: 50ms timer reads `NSEvent.modifierFlags` (global state, no monitor, no
permission, no signature sensitivity), edge-detects Option, same 400ms
double-tap window. Start/stop logic in `VoiceCaptureController` unchanged.

Trade-off: Esc-cancel needs a real key event, which polling can't see. Either
keep the global `.keyDown` monitor best-effort for Esc, or change cancel to
triple-tap / tap-and-hold while recording. Needs your call — it changes the
decided trigger UX.

## Current code state (jarvisV1, uncommitted)

- Deferred monitor start + pill: in place, app launches alive.
- Sync reload/tick (`reloadWorkItems`, `syncCoordinator.tick`): restored.
- All bisect scaffolding removed. Debug prints removed.
- `build/JarvDaddysHome.app` = release, stable-cert signed.
- Untracked D/B files + 19 modified files still uncommitted, as before.
