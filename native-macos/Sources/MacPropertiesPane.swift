import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum MacPaneSection: String, CaseIterable, Identifiable, Sendable {
    case properties, revisions, relations, outline, attachments
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
struct MacPaneLayout: Equatable, Sendable {
    var order = MacPaneSection.allCases
    var collapsed: Set<MacPaneSection> = []
    static func ids(_ value: Any?) -> [String] { (value as? [Any] ?? []).compactMap { $0 as? String } }
    init(_ object: [String: Any] = [:]) {
        var seen = Set<MacPaneSection>()
        order = (Self.ids(object["order"]).compactMap(MacPaneSection.init(rawValue:)) + MacPaneSection.allCases).filter { seen.insert($0).inserted }
        collapsed = Set(Self.ids(object["collapsed"]).compactMap(MacPaneSection.init(rawValue:)))
    }
}
enum MacPaneChange: Sendable {
    case collapse(MacPaneSection, Bool), step(MacPaneSection, Int), move(MacPaneSection, MacPaneSection), reset
}
struct MacPaneSnapshot: @unchecked Sendable {
    let bytes: Data?
    let object: [String: Any]
    var layout: MacPaneLayout { .init(object) }
}
extension VaultFiles {
    func macPaneSnapshot() throws -> MacPaneSnapshot {
        let path = ".zerus/properties-pane.json", location = try url(for: path)
        guard FileManager.default.fileExists(atPath: location.path) else { return .init(bytes: nil, object: [:]) }
        let bytes = try read(path)
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "The properties pane layout has an unsupported format. Its file was preserved.") }
        return .init(bytes: bytes, object: object)
    }
    func macChangePane(_ change: MacPaneChange) throws -> MacPaneSnapshot {
        let snapshot = try macPaneSnapshot()
        var object = snapshot.object, layout = snapshot.layout
        func move(_ section: MacPaneSection, _ target: MacPaneSection) {
            guard let from = layout.order.firstIndex(of: section), let to = layout.order.firstIndex(of: target), from != to else { return }
            layout.order.remove(at: from); layout.order.insert(section, at: to)
        }
        switch change {
        case .collapse(let section, let value): if value { layout.collapsed.insert(section) } else { layout.collapsed.remove(section) }
        case .move(let section, let target): move(section, target)
        case .step(let section, let direction):
            if let index = layout.order.firstIndex(of: section), [-1, 1].contains(direction), layout.order.indices.contains(index + direction) { move(section, layout.order[index + direction]) }
        case .reset: layout = .init()
        }
        // Keep future section IDs in their existing slots while changing the
        // known sections. Unknown fields and collapsed IDs survive every edit.
        var remaining = layout.order.map(\.rawValue), seen = Set<String>(), order: [String] = []
        for id in MacPaneLayout.ids(object["order"]) where seen.insert(id).inserted {
            if MacPaneSection(rawValue: id) != nil { if !remaining.isEmpty { order.append(remaining.removeFirst()) } }
            else { order.append(id) }
        }
        object["order"] = order + remaining
        let unknown = MacPaneLayout.ids(object["collapsed"]).filter { MacPaneSection(rawValue: $0) == nil }
        object["collapsed"] = Array(Set(unknown)).sorted() + layout.order.filter { layout.collapsed.contains($0) }.map(\.rawValue)
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try applyTransaction([.init(path: ".zerus/properties-pane.json", before: snapshot.bytes, after: bytes)], historySource: "macos")
        return .init(bytes: bytes, object: object)
    }
}
extension MacWorkspace {
    func refreshPaneLayout() async {
        guard let io, !paneLayoutSaving else { return }
        let origin = workspaceID, revision = paneRevision
        do {
            let result = try await io.macPaneSnapshot()
            guard origin == workspaceID, revision == paneRevision, !paneLayoutSaving else { return }
            let layout = result.layout
            if paneLayout != layout { paneLayout = layout }
            if !paneLayoutReady { paneLayoutReady = true }
            if paneLayoutIssue != nil { paneLayoutIssue = nil }
        } catch {
            if origin == workspaceID, revision == paneRevision, !paneLayoutSaving {
                let message = error.localizedDescription
                if paneLayoutIssue != message { paneLayoutIssue = message }
                if paneLayoutReady { paneLayoutReady = false }
            }
        }
    }
    func changePane(_ change: MacPaneChange, workspaceID expected: UUID) async throws {
        guard expected == workspaceID else { throw VaultFailure(message: "The vault changed. Reopen the properties pane.") }
        guard let io, !busy, !preparingToClose, !paneLayoutSaving else { throw VaultFailure(message: "Finish the current vault or pane change, then try again.") }
        let rootPath = root?.resolvingSymlinksInPath().standardizedFileURL.path
        let peers = Self.windows.compactMap(\.value).filter { $0.root?.resolvingSymlinksInPath().standardizedFileURL.path == rootPath }
        guard peers.allSatisfy({ !$0.paneLayoutSaving && !$0.preparingToClose && !$0.busy }) else { throw VaultFailure(message: "Finish the current vault change before changing the properties pane.") }
        peers.forEach { $0.paneRevision += 1; $0.paneLayoutSaving = true; $0.paneLayoutIssue = nil }
        let owners = peers.map { ($0, $0.workspaceID, $0.paneRevision) }
        defer {
            for (peer, origin, revision) in owners where peer.workspaceID == origin && peer.paneRevision == revision { peer.paneLayoutSaving = false }
        }
        do {
            let result = try await io.macChangePane(change)
            for (peer, origin, revision) in owners where peer.workspaceID == origin && peer.paneRevision == revision { peer.paneLayout = result.layout; peer.paneLayoutReady = true }
        } catch {
            for (peer, origin, revision) in owners where peer.workspaceID == origin && peer.paneRevision == revision { peer.paneLayoutIssue = error.localizedDescription }
            throw error
        }
    }
}

private let macPaneDragType = "com.zerus.notes.properties-pane-section"
struct MacPaneHeader: View {
    @Bindable var workspace: MacWorkspace
    let section: MacPaneSection
    @State private var hovering = false
    private var disabled: Bool { workspace.paneLayoutSaving || !workspace.paneLayoutReady || workspace.busy || workspace.preparingToClose }
    var body: some View {
        let origin = workspace.workspaceID, collapsed = workspace.paneLayout.collapsed.contains(section)
        HStack(spacing: 4) {
            Button { apply(.collapse(section, !collapsed), origin: origin) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90)).frame(width: 10)
                    Text(section.title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(disabled)
                .accessibilityLabel((collapsed ? "Expand " : "Collapse ") + section.title)
            Group {
                Image(systemName: "line.3.horizontal").font(.system(size: 10)).help("Drag to reorder " + section.title)
                    .onDrag {
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(forTypeIdentifier: macPaneDragType, visibility: .ownProcess) { done in done(Data(section.rawValue.utf8), nil); return nil }
                        return provider
                    }
                Menu {
                    Button("Move up") { apply(.step(section, -1), origin: origin) }.disabled(workspace.paneLayout.order.first == section)
                    Button("Move down") { apply(.step(section, 1), origin: origin) }.disabled(workspace.paneLayout.order.last == section)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(disabled).accessibilityLabel(section.title + " section options")
            }.opacity(hovering ? 1 : 0)
        }.foregroundStyle(.secondary).padding(.horizontal, 6).frame(height: 24)
            .contentShape(Rectangle()).onHover { hovering = $0 }
            .onDrop(of: [macPaneDragType], delegate: MacPaneDrop(workspace: workspace, target: section, origin: origin))
    }
    private func apply(_ change: MacPaneChange, origin: UUID) { Task { do { try await workspace.changePane(change, workspaceID: origin) } catch { if workspace.workspaceID == origin { workspace.paneLayoutIssue = error.localizedDescription } } } }
}
private struct MacPaneDrop: DropDelegate {
    let workspace: MacWorkspace
    let target: MacPaneSection
    let origin: UUID
    func validateDrop(info: DropInfo) -> Bool { !workspace.paneLayoutSaving && workspace.paneLayoutReady && !workspace.busy && !workspace.preparingToClose && info.hasItemsConforming(to: [macPaneDragType]) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let provider = info.itemProviders(for: [macPaneDragType]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: macPaneDragType) { data, _ in
            guard let data, data.count <= 32, let value = String(data: data, encoding: .utf8), let section = MacPaneSection(rawValue: value) else { return }
            Task { @MainActor in do { try await workspace.changePane(.move(section, target), workspaceID: origin) } catch { if workspace.workspaceID == origin { workspace.paneLayoutIssue = error.localizedDescription } } }
        }
        return true
    }
}
struct MacPaneSettingsView: View {
    @Bindable var workspace: MacWorkspace
    @Environment(\.macSettingsEmbedded) private var embedded
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let origin = workspace.workspaceID
        VStack(alignment: .leading, spacing: 16) {
            if !embedded { Text("Properties pane").font(.title2.bold()) }
            Text("Drag sections or use their menus to reorder them. Click a heading to collapse or expand it. Saved for all notes in this vault.").foregroundStyle(.secondary)
            ForEach(workspace.paneLayout.order) { section in
                HStack { MacPaneHeader(workspace: workspace, section: section); Text(workspace.paneLayout.collapsed.contains(section) ? "Collapsed" : "Expanded").font(.caption).foregroundStyle(.secondary) }
                Divider()
            }
            if let issue = workspace.paneLayoutIssue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Reset pane layout") { Task { do { try await workspace.changePane(.reset, workspaceID: origin) } catch { if workspace.workspaceID == origin { workspace.paneLayoutIssue = error.localizedDescription } } } }.disabled(workspace.paneLayoutSaving || !workspace.paneLayoutReady || workspace.busy || workspace.preparingToClose)
                Button("Refresh") { Task { await workspace.refreshPaneLayout() } }.disabled(workspace.paneLayoutSaving)
                Spacer(); if !embedded { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }.macSettingsChrome(width: 520).interactiveDismissDisabled(workspace.paneLayoutSaving)
    }
}
