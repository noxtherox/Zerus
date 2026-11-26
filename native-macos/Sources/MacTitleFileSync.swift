import Foundation

/// Decides whether leaving a note should rename its file to match its title.
/// Only files that still follow their title are renamed: an "Untitled" file,
/// or one named after the title the note had when it was opened. A file the
/// user named independently keeps its name.
enum MacTitleFileSync {
    /// The title to rename to, or nil when the file should keep its name.
    static func title(path: String, title: String, openedTitle: String?) -> String? {
        guard !path.hasPrefix(".zerus/"), !path.hasPrefix(".trash/"), (path as NSString).pathExtension.lowercased() == "md",
              let clean = try? NativeNoteRename.cleanTitle(title) else { return nil }
        let current = (path as NSString).lastPathComponent
        guard NativeNoteRename.suggestedFilename(clean, path: path).caseInsensitiveCompare(current) != .orderedSame else { return nil }
        let stem = unnumbered(current)
        let followsTitle = stem.caseInsensitiveCompare("Untitled") == .orderedSame
            || openedTitle.flatMap { try? NativeNoteRename.cleanTitle($0) }.map { stem.caseInsensitiveCompare(unnumbered(NativeNoteRename.suggestedFilename($0, path: path))) == .orderedSame } == true
        return followsTitle ? clean : nil
    }
    /// File stem without the " 2" style suffix added for duplicate names.
    private static func unnumbered(_ filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        return stem.replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)
    }
}
