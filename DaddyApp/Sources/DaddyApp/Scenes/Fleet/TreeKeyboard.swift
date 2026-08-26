import AppKit

/// The file tree's half of a keyboard shared with two live terminals.
///
/// One job left: taking the keyboard off the agent when you click a row.
///
/// There was a second job — asking AppKit whether a terminal or a text field
/// currently held first responder, and standing down if so. That looked like
/// the careful thing to do and was actually the bug: first responder moves
/// around during a relayout, so expanding a folder could leave the tree
/// refusing Enter and ⌘⌫ for reasons invisible to the person pressing them.
/// `FileTreeStore.isActive` answers the same question by watching what you
/// click, which cannot drift.
@MainActor
enum TreeKeyboard {

    /// Takes the keyboard back on behalf of the tree.
    ///
    /// Without this the agent's `TerminalView` keeps first responder straight
    /// through a click on the rail, and every key you typed next would go to
    /// the agent while the tree sat there looking selected.
    static func claim() {
        _ = NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
