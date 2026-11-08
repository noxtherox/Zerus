import SwiftUI

struct NativeSavedLinksView: View {
    @EnvironmentObject private var vault: VaultStore
    let workspaceID: UUID
    let open: (NoteDocument) -> Void
    @State private var query = ""
    @State private var filters = NativeCollectionFilters()
    @State private var adding = false
    @State private var settings = false
    @State private var editing: NoteDocument?
    @State private var created: NoteDocument?
    private var candidates: [NoteDocument] { vault.searchableNotes.filter { !$0.trashed && ($0.savedLink != nil || $0.unfiledSavedLink) } }
    private var visible: [NoteDocument] { filters.apply(candidates, query: query) }
    var body: some View {
        List {
            Section { Button("Add a saved link", systemImage: "plus") { adding = true }.accessibilityIdentifier("savedlink.add") }
            if query.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "link").font(.title).foregroundStyle(Accent.color)
                        Text("Worth keeping.").font(.system(.title2, design: .serif))
                        Text("Useful pages, with a little room for your thoughts.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }.listRowBackground(Color.clear)
            }
            if visible.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "No saved links yet" : "No matching links", systemImage: "link")
                } description: { Text(query.isEmpty ? "Save a web address and add your own notes." : "Try another title, address or phrase.") }
                actions: { if query.isEmpty { Button("Add a link") { adding = true } } }
                    .listRowBackground(Color.clear)
            }
            ForEach(visible) { note in
                Button { open(note) } label: { NativeSavedLinkRow(note: note) }.buttonStyle(.plain)
                    .accessibilityIdentifier("savedlink.note." + (note.savedLink?.id ?? note.path))
                    .swipeActions { Button("Trash", systemImage: "trash", role: .destructive) { Task { await vault.move(note, trash: true) } } }
                    .contextMenu {
                        if let url = note.savedLink?.url {
                            Link(destination: url) { Label("Open website", systemImage: "safari") }
                            ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
                        }
                        if note.savedLink != nil { Button("Edit address", systemImage: "pencil") { editing = note } }
                        NoteActions(note: note)
                    }
            }
        }
        .navigationTitle("Saved links").searchable(text: $query, prompt: "Search saved links")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .scrollContentBackground(.hidden).background(Accent.paper)
        .refreshable { await vault.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Settings") }
        }
        .sheet(isPresented: $settings) { SettingsView(collection: .init(filters: $filters, notes: candidates)) }
        .sheet(isPresented: $adding, onDismiss: {
            if let created { self.created = nil; open(created) }
        }) { NativeSavedLinkForm(workspaceID: workspaceID) { created = $0 } }
        .sheet(item: $editing) { note in
            if let session = vault.session(for: note) { NativeSavedLinkForm(workspaceID: workspaceID, session: session) { _ in } }
        }
    }
}

private struct NativeSavedLinkRow: View {
    let note: NoteDocument
    var body: some View {
        let snippet = note.snippet
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "link").font(.title3).foregroundStyle(Accent.color).frame(width: 40, height: 40).background(Accent.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(note.title).font(.headline).foregroundStyle(.primary).lineLimit(2); Spacer(); if note.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Accent.color) } }
                Text(note.savedLink?.displayName ?? "Link details unavailable; note preserved").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if !snippet.isEmpty { Text(snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 5) {
                    if note.archived { Image(systemName: "archivebox") }
                    if !note.unfiledSavedLink { Label(note.folder, systemImage: "folder").lineLimit(1); Text("·") }
                    Text(note.modified, style: .relative)
                }.font(.caption).foregroundStyle(.tertiary)
            }
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
}

struct NativeSavedLinkCard: View {
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject var session: NoteSession
    @State private var editing = false
    var body: some View {
        if let saved = session.document.savedLink {
            HStack(spacing: 12) {
                if let url = saved.url {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            Image(systemName: "link")
                            VStack(alignment: .leading, spacing: 4) { Text(saved.displayName).font(.subheadline.weight(.semibold)); Text(url.absoluteString).font(.caption).lineLimit(2) }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.caption)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityLabel("Open saved link: " + url.absoluteString).accessibilityIdentifier("savedlink.open")
                } else {
                    Label("This saved address needs updating.", systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { editing = true } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }.accessibilityLabel("Edit saved link address").accessibilityIdentifier("savedlink.edit")
            }.padding(14).background(Accent.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20).padding(.bottom, 8)
                .sheet(isPresented: $editing) { NativeSavedLinkForm(workspaceID: vault.workspaceID, session: session) { _ in } }
        }
    }
}

struct NativeSavedLinkForm: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let workspaceID: UUID
    let session: NoteSession?
    let originalAddress: String
    let saved: (NoteDocument) -> Void
    @State private var address: String
    @State private var title = ""
    @State private var busy = false
    @State private var issue: String?
    @FocusState private var addressFocused: Bool
    init(workspaceID: UUID, session: NoteSession? = nil, saved: @escaping (NoteDocument) -> Void) {
        self.workspaceID = workspaceID; self.session = session; self.saved = saved
        originalAddress = session?.document.savedLink?.address ?? ""; _address = State(initialValue: originalAddress)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Web address", text: $address, axis: .vertical).keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($addressFocused).accessibilityIdentifier("savedlink.address")
                    if session == nil { TextField("Title (optional)", text: $title).accessibilityIdentifier("savedlink.title") }
                } footer: { Text(session == nil ? "Save a web page to keep it with your notes. It opens in your default browser." : "Update the web address. Your title and notes stay with this link.") }
                if let issue { Section { Text(issue).foregroundStyle(.red).accessibilityIdentifier("savedlink.error") } }
                if !address.isEmpty && NativeSavedLink.normalizedURL(address) == nil { Text("Use a valid http or https address.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle(session == nil ? "Save a link" : "Edit link").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("savedlink.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("Save link") { save() }.disabled(NativeSavedLink.normalizedURL(address) == nil).accessibilityIdentifier("savedlink.save") }
            }
            .disabled(busy).interactiveDismissDisabled(busy)
            .overlay { if busy { ProgressView("Saving link…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .task { addressFocused = true }
        }
    }
    private func save() {
        guard !busy else { return }; busy = true; issue = nil
        Task {
            defer { busy = false }
            do {
                let note: NoteDocument
                if let session {
                    try await vault.updateSavedLink(session: session, address: address, originalAddress: originalAddress, workspace: workspaceID)
                    note = session.document
                } else { note = try await vault.createSavedLink(address: address, title: title, workspace: workspaceID) }
                dismiss(); saved(note)
            } catch { issue = error.localizedDescription }
        }
    }
}
