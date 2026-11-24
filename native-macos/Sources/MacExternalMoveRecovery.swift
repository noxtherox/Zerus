import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension MacExternalLibrary {
    func exportPendingOriginal(_ record: NativeExternalMoveRecord, to url: URL) async throws {
        guard try await moveStore.pending().contains(record) else { throw VaultFailure(message: "This pending move changed. Reload it before exporting.") }
        let destination = try record.destination().root.appendingPathComponent(record.destinationPath)
        if let entry = entries.first(where: { $0.id == record.sourceID }), let source = URL(string: entry.location) {
            guard url.resolvingSymlinksInPath().standardizedFileURL != source.resolvingSymlinksInPath().standardizedFileURL else { throw VaultFailure(message: "Export to a separate file to keep the original protected.") }
            if let sourceID = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable,
               let targetID = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable,
               sourceID == targetID { throw VaultFailure(message: "Choose a separate recovery file, not an alias of the original.") }
        }
        _ = try await MacExternalDraftExport.create(bytes: record.sourceBytes, to: url, original: destination, privateDirectory: store.directory)
    }
}

struct MacExternalMoveRecoveryView: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var library: MacExternalLibrary
    let record: NativeExternalMoveRecord
    var reviewOriginal: (NativeExternalEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var issue: String?
    @State private var busy = false
    @State private var discard = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Pending move").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text(record.sourceName).font(.headline)
            LabeledContent("Vault copy", value: record.destinationPath).textSelection(.enabled)
            Text(record.phase == .removed ? "The original was removed. Finish the saved connection after checking the vault copy." : "Original recovery bytes are kept on this Mac. Review the current original before removing it, or keep both files and close the connection.").foregroundStyle(.secondary)
            Button("Open destination vault") { run {
                let destination = try record.destination(); await workspace.openVault(destination.root)
                guard workspace.root?.resolvingSymlinksInPath().standardizedFileURL == destination.root.resolvingSymlinksInPath().standardizedFileURL else { throw VaultFailure(message: workspace.issue ?? "The destination vault could not be opened.") }
            } }
            if record.phase != .removed, let entry = library.entries.first(where: { $0.id == record.sourceID }) {
                Button("Review original removal…") { reviewOriginal(entry); dismiss() }
            }
            Button(record.phase == .removed ? "Finish saved connection" : "Keep vault copy and close connection") { run { try await workspace.finishPendingExternalMove(record); dismiss() } }
            Text("The vault note and every copied attachment are checked before the connection is closed. Any remaining original file stays in place.").font(.caption).foregroundStyle(.secondary)
            Button("Save original recovery copy…") { export() }
            DisclosureGroup("Retained original Markdown") {
                ScrollView { Text(String(data: record.sourceBytes, encoding: .utf8) ?? "Unreadable UTF-8").font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
            }
            Button("Discard recovery record…", role: .destructive) { discard = true }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if busy { ProgressView().controlSize(.small) }
        }.padding(24).frame(width: 640).disabled(busy).interactiveDismissDisabled(busy)
        .alert("Discard the retained original?", isPresented: $discard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard recovery record", role: .destructive) { run { try await library.moveStore.finish(record); await library.restore(); dismiss() } }
        } message: { Text("This permanently removes the private move record and its retained original bytes. The original project files, saved connection and vault copy stay in place. Export the recovery copy first if needed.") }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await action() } catch { issue = error.localizedDescription } }
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Recovered " + record.sourceName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try await library.exportPendingOriginal(record, to: url) }
    }
}
