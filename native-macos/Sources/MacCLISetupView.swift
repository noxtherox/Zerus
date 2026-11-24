import SwiftUI

struct MacCLISetupView: View {
    @Bindable var workspace: MacWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var makeDefault = false
    @State private var registration: MacCLIRegistrationReview?
    @State private var metadata: MacCLIMetadataReview?
    @State private var busy = false
    @State private var issue: String?
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up this vault for CLI use").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(workspace.root?.path ?? "No vault selected").font(.callout.monospaced()).textSelection(.enabled)
                    GroupBox("Register the vault") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Add this folder to the shared Zerus CLI vault list on this Mac. Registration keeps your notes unchanged.").font(.callout).foregroundStyle(.secondary)
                            TextField("Vault name", text: $name)
                            Toggle("Make this the default CLI vault", isOn: $makeDefault)
                            Button("Review registration…") { perform { registration = try await workspace.prepareCLIRegistration(name: name, makeDefault: makeDefault) } }
                        }.padding(8)
                    }
                    GroupBox("Prepare note metadata") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Give notes stable IDs and update older reserved metadata. Review every changed note before applying. Note text and other properties stay in place.").font(.callout).foregroundStyle(.secondary)
                            Text("Invalid, duplicate or noncanonical IDs block preparation. Open drafts are saved first; conflicts and retained recovery drafts must be resolved.").font(.caption).foregroundStyle(.secondary)
                            Button("Review metadata changes…") { perform { metadata = try await workspace.prepareCLIMetadata() } }
                        }.padding(8)
                    }
                    if let message { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { if busy { ProgressView().controlSize(.small) }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 700, height: 520).disabled(busy).interactiveDismissDisabled(busy)
            .onAppear { if name.isEmpty { name = workspace.root?.lastPathComponent ?? "" } }
            .confirmationDialog("Register this vault?", isPresented: Binding(get: { registration != nil }, set: { if !$0 { registration = nil } }), titleVisibility: .visible) {
                if let registration {
                    Button("Register reviewed vault") {
                        perform {
                            try await workspace.commitCLIRegistration(registration)
                            message = "Registered " + registration.registry.name + ". Agents can find it with zerus vault list --json."
                        }
                    }
                }
                Button("Cancel", role: .cancel) { registration = nil }
            } message: {
                if let registration {
                    let old = registration.registry.previousPath
                    let oldName = registration.registry.previousName
                    Text("Name: " + registration.registry.name + "\nFolder: " + registration.root.path + "\nRegistry: " + registration.registry.file.path + (oldName != nil && oldName != registration.registry.name ? "\nRenames registered vault: " + oldName! + " → " + registration.registry.name : "") + (registration.registry.isDefault ? "\nThis will be the default CLI vault." : "") + (old != nil && old != registration.root.resolvingSymlinksInPath().standardizedFileURL.path ? "\nUpdates an existing vault identity registered at: " + old! : "") + (registration.manifest.change.before == nil ? "\nCreates .zerus/vault.json to keep this vault’s identity." : ""))
                }
            }
            .macSheet(item: $metadata) { review in MacCLIMetadataReviewView(workspace: workspace, review: review) { message = "CLI note metadata prepared." } }
    }
    private func perform(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true; issue = nil; message = nil
        Task { @MainActor in defer { busy = false }; do { try await operation() } catch { issue = error.localizedDescription } }
    }
}

private struct MacCLIMetadataReviewView: View {
    @Bindable var workspace: MacWorkspace
    let review: MacCLIMetadataReview
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review CLI metadata").font(.title2.bold())
            Text("\(review.noteChanges.count) of \(review.notes.count) notes change · \(review.idsAdded) IDs added · \(review.keysRenamed) legacy keys renamed.")
            Text("Marks this vault as using stable CLI note IDs. Reserved true/false flags are normalized in the shown diffs. Other metadata and note bodies are preserved.").font(.callout).foregroundStyle(.secondary)
            ScrollView { LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(review.issues, id: \.self) { Text($0).foregroundStyle(.red).textSelection(.enabled) }
                ForEach(review.noteChanges, id: \.path) { change in
                    DisclosureGroup(change.path) {
                        MacHistoryDifferenceView(before: change.before.flatMap(NoteDocument.decodeUTF8) ?? "", after: change.after.flatMap(NoteDocument.decodeUTF8) ?? "")
                    }
                }
                if let manifest = review.changes.first(where: { $0.path == ".zerus/vault.json" }), manifest.before != manifest.after {
                    DisclosureGroup("Vault identity and CLI readiness") { MacHistoryDifferenceView(before: manifest.before.map { String(decoding: $0, as: UTF8.self) } ?? "", after: manifest.after.map { String(decoding: $0, as: UTF8.self) } ?? "") }
                }
            }.frame(maxWidth: .infinity, alignment: .leading) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Apply reviewed metadata") {
                    busy = true; issue = nil
                    Task { @MainActor in
                        defer { busy = false }
                        do { try await workspace.commitCLIMetadata(review); saved(); dismiss() }
                        catch { issue = error.localizedDescription }
                    }
                }.disabled(!review.issues.isEmpty)
            }
        }.padding(24).frame(width: 760, height: 600).disabled(busy).interactiveDismissDisabled(busy)
    }
}
