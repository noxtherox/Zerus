import SwiftUI
import AppKit
import Markdown

/// Discover editable blocks when the menu opens, rather than on every edit
/// that invalidates the surrounding SwiftUI toolbar.
@MainActor struct MacBlockMenu: NSViewRepresentable {
    struct Snapshot {
        let scope: UUID
        let path: String
        let source: String
    }
    let snapshot: () -> Snapshot?
    let prepare: (Snapshot) -> Bool
    let codeBlocks: Bool
    let openTable: (MacTableRequest) -> Void
    let openCode: (MacCodeRequest) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.macTheme) private var theme

    init(workspace: MacWorkspace, codeBlocks: Bool, openTable: @escaping (MacTableRequest) -> Void, openCode: @escaping (MacCodeRequest) -> Void) {
        self.init(codeBlocks: codeBlocks, snapshot: { [weak workspace] in
            guard let workspace, let path = workspace.selection else { return nil }
            return Snapshot(scope: workspace.workspaceID, path: path, source: workspace.editorBody(workspace.body))
        }, prepare: { [weak workspace] snapshot in
            guard let workspace else { return false }
            guard workspace.workspaceID == snapshot.scope, workspace.selection == snapshot.path,
                  workspace.editorBody(workspace.body).utf8.elementsEqual(snapshot.source.utf8), !workspace.busy,
                  !workspace.preparingToClose, !workspace.agentWritingHeld else {
                workspace.issue = "The note changed. Open the menu again to choose a current block."
                return false
            }
            workspace.editorSheetActive = true
            return true
        }, openTable: openTable, openCode: openCode)
    }
    init(codeBlocks: Bool, snapshot: @escaping () -> Snapshot?, prepare: @escaping (Snapshot) -> Bool,
         openTable: @escaping (MacTableRequest) -> Void, openCode: @escaping (MacCodeRequest) -> Void) {
        self.codeBlocks = codeBlocks; self.snapshot = snapshot; self.prepare = prepare
        self.openTable = openTable; self.openCode = openCode
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false; button.bezelStyle = .inline
        button.controlSize = .small
        button.setAccessibilityLabel("Tables and code")
        button.toolTip = "Tables and code"
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.addItem(Self.labelItem()); menu.delegate = context.coordinator
        button.menu = menu
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = isEnabled && snapshot() != nil
        button.contentTintColor = NSColor(theme.color(.accent))
    }
    private static func labelItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Tables and code")
        return item
    }
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: MacBlockMenu
        private var actions: [() -> Void] = []
        init(_ parent: MacBlockMenu) { self.parent = parent }
        func menuNeedsUpdate(_ menu: NSMenu) {
            actions.removeAll(); menu.removeAllItems(); menu.addItem(MacBlockMenu.labelItem())
            guard let snapshot = parent.snapshot() else { return }
            let source = snapshot.source, origin = snapshot.scope, path = snapshot.path
            let prepare = parent.prepare
            let document = Document(parsing: source)
            let codes = MacCodeBlock.blocks(in: source, document: document)
            let tables = MacTableBlock.blocks(in: source, excluding: codes.map(\.range), document: document)
            func add(_ title: String, _ action: @escaping () -> Void) {
                let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
                item.target = self; item.tag = actions.count
                actions.append {
                    guard prepare(snapshot) else { return }
                    action()
                }
                menu.addItem(item)
            }
            let tableAction = parent.openTable, codeAction = parent.openCode
            add("Insert table") { tableAction(.init(workspaceID: origin, path: path, source: source, range: nil, table: .empty())) }
            for (index, block) in tables.enumerated() {
                add("Edit table \(index + 1)") { tableAction(.init(workspaceID: origin, path: path, source: source, range: block.range, table: block.table)) }
            }
            menu.addItem(.separator())
            if parent.codeBlocks {
                add("Insert code block") { codeAction(.init(workspaceID: origin, path: path, source: source, range: nil, code: nil)) }
            }
            for (index, block) in codes.enumerated() {
                add("Edit code \(index + 1) · " + block.code.language) { codeAction(.init(workspaceID: origin, path: path, source: source, range: block.range, code: block.code)) }
            }
        }
        @objc private func invoke(_ item: NSMenuItem) {
            guard actions.indices.contains(item.tag) else { return }
            actions[item.tag]()
        }
    }
}
