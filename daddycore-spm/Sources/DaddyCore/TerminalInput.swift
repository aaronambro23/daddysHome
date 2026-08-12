import Foundation

/// Something that can be sent into a pty.
///
/// Agents are interactive TUIs: approving a tool call means pressing Enter or an
/// arrow key, and interrupting means a real `0x03` byte — writing the *string*
/// `"\u{03}"` is not the same thing, and writing `"\n"` is not always the same
/// as pressing Return. Modelling input explicitly keeps that correct in one
/// place instead of at every call site.
///
/// Design borrowed from terminal-control's typed key encoding
/// (`src/driver.rs`), reimplemented in Swift.
public enum TerminalInput: Equatable, Sendable {
    /// Literal text, sent as UTF-8.
    case text(String)

    /// A single raw control byte, e.g. `0x03` for Ctrl-C.
    case control(UInt8)

    /// A named key, encoded as the escape sequence a terminal would send.
    case key(Key)

    public enum Key: String, Equatable, Sendable, CaseIterable {
        case enter
        case tab
        case backspace
        case escape
        case up
        case down
        case right
        case left
        case home
        case end
        case pageUp
        case pageDown
        case delete
    }

    /// Common control bytes, named.
    public static let interrupt = TerminalInput.control(0x03)   // Ctrl-C
    public static let endOfFile = TerminalInput.control(0x04)   // Ctrl-D

    /// The bytes to write into the pty.
    public var bytes: [UInt8] {
        switch self {
        case .text(let string):
            return Array(string.utf8)

        case .control(let byte):
            return [byte]

        case .key(let key):
            return Array(key.escapeSequence.utf8)
        }
    }
}

extension TerminalInput.Key {
    /// Standard xterm encodings. Agents read these directly from the pty.
    var escapeSequence: String {
        switch self {
        case .enter: return "\r"
        case .tab: return "\t"
        case .backspace: return "\u{7F}"
        case .escape: return "\u{1B}"
        case .up: return "\u{1B}[A"
        case .down: return "\u{1B}[B"
        case .right: return "\u{1B}[C"
        case .left: return "\u{1B}[D"
        case .home: return "\u{1B}[H"
        case .end: return "\u{1B}[F"
        case .pageUp: return "\u{1B}[5~"
        case .pageDown: return "\u{1B}[6~"
        case .delete: return "\u{1B}[3~"
        }
    }
}
