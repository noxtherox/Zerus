import SwiftUI
import AppKit

/// A window keeps native Undo targets only for its open note tabs. A suspended
/// editor is inert; reopening adopts current callbacks and reloads if source
/// bytes changed. Closing a tab or changing vault releases its live history.
@MainActor final class MacEditorSessions: ObservableObject {
    private struct Key: Hashable { let scope: UUID; let path: String }
    private var entries: [Key: MacRichEditor.Coordinator] = [:]
    func acquire(_ parent: MacRichEditor) -> MacRichEditor.Coordinator {
        guard let scope = parent.commandScope, !parent.path.isEmpty else { return MacRichEditor.Coordinator(parent) }
        let key = Key(scope: scope, path: parent.path)
        if let existing = entries[key], !existing.active, existing.retainedScroll?.superview == nil, existing.retainedScroll != nil {
            existing.updateParent(parent)
            return existing
        }
        let value = MacRichEditor.Coordinator(parent)
        entries[key] = value
        return value
    }
    func contains(_ value: MacRichEditor.Coordinator) -> Bool { entries.values.contains { $0 === value } }
    func retain(scope: UUID, paths: Set<String>) {
        let removed = entries.keys.filter { $0.scope != scope || !paths.contains($0.path) }
        for key in removed { entries.removeValue(forKey: key)?.detach() }
    }
    func removeAll() {
        let previous = entries.values; entries.removeAll()
        for value in previous { value.detach() }
    }
}
