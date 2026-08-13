import Foundation
import DaddyCore

/// A directory under `~/Documents` that agents work in.
struct Project: Identifiable, Hashable {
    let id: String
    let name: String

    /// Tilde-abbreviated for display.
    let path: String

    var expandedURL: URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}

/// One HEX transcription Daddy acted on.
struct VoiceEntry: Identifiable {
    let id = UUID()
    let at: Date
    let transcript: String
    let resolution: String
    let didSucceed: Bool
}

// MARK: - Formatting

func formatTimeAgo(_ date: Date) -> String {
    let elapsed = Date().timeIntervalSince(date)
    if elapsed < 60 { return "now" }
    if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
    if elapsed < 86_400 { return "\(Int(elapsed / 3600))h" }
    return "\(Int(elapsed / 86_400))d"
}
