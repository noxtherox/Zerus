import SwiftUI

/// Chooses reference text only. External registrations never enter the vault's
/// selected paths or grant any agent a capability to write to the original.
struct NativeExternalReferencePicker: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var external: NativeExternalNotesModel
    @Environment(\.dismiss) private var dismiss
    let choose: (NativeSearchDocument) -> Void
    @State private var query = ""
    @State private var failure: String?
    @State private var loading: UUID?
    @State private var job: Task<Void, Never>?
    @State private var action = UUID()
    @FocusState private var focused: Bool
    private var records: [NativeExternalSearchRecord] {
        external.searchRecords.filter { record in
            query.isEmpty || (record.entry.name + " " + record.entry.parent + " " + (record.document?.content ?? "")).localizedStandardContains(query)
        }.map { (record: $0, title: $0.document?.title ?? $0.entry.name) }
            .sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.record.entry.id.uuidString < $1.record.entry.id.uuidString : order == .orderedAscending
            }.map(\.record)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a connected Markdown file. Its latest text or kept recovery draft will be added as a read-only reference; long files use a labelled excerpt.").font(.subheadline).foregroundStyle(.secondary)
                    if external.searching { ProgressView("Checking external files…").accessibilityIdentifier("context.external.indexing") }
                    if let issue = external.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.caption) }
                    if let failure { Label(failure, systemImage: "exclamationmark.triangle").font(.callout).accessibilityIdentifier("context.external.error") }
                    if loading != nil {
                        ProgressView("Preparing reference…")
                        Button("Cancel loading") { cancel() }.accessibilityIdentifier("context.external.loading.cancel")
                    }
                }
                if records.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No external files" : "No matching files", systemImage: "doc.text.magnifyingglass", description: Text("Connect a Markdown file in Library → External notes, or try another search."))
                }
                ForEach(records, id: \.entry.id) { record in
                    Button { prepare(record.entry.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.document?.title ?? record.entry.name).font(.headline).foregroundStyle(.primary)
                            Label(record.entry.parent + " · " + record.entry.name, systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                            if record.draft { Text("Recovery draft").font(.caption).foregroundStyle(Accent.color) }
                            if let issue = record.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.disabled(loading != nil).accessibilityIdentifier("context.external.option." + record.entry.id.uuidString)
                }
            }.scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search names and text", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).submitLabel(.done).onSubmit { focused = false }.accessibilityIdentifier("context.external.search")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear external search") }
                        if focused { Button("Done") { focused = false }.accessibilityIdentifier("context.external.keyboard.dismiss") }
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 20).padding(.vertical, 8).background(.bar)
                }
                .navigationTitle("External reference").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel(); dismiss() }.accessibilityIdentifier("context.external.cancel") } }
                .task { await external.refreshSearchIndex() }
                .refreshable { await external.refreshSearchIndex() }
                .onDisappear { cancel() }
        }
    }
    private func cancel() { job?.cancel(); job = nil; action = UUID(); loading = nil }
    private func prepare(_ id: UUID) {
        cancel(); focused = false; failure = nil
        let token = UUID(), workspace = vault.workspaceID
        action = token; loading = id
        job = Task {
            defer { if action == token { loading = nil; job = nil } }
            do {
                let record = try await external.searchRecord(id)
                guard !Task.isCancelled, action == token, vault.workspaceID == workspace, external.entries.contains(where: { $0.id == id }) else { return }
                let document = try record.referenceDocument()
                choose(document); dismiss()
            } catch is CancellationError {} catch {
                if action == token, vault.workspaceID == workspace { failure = error.localizedDescription }
            }
        }
    }
}
