import SwiftUI
import QuickLook

struct VaultRecoveryScreen: View {
    @EnvironmentObject private var vault: VaultStore
    let review: VaultRecoveryReview
    let switchVault: () -> Void
    @State private var choices: [String: VaultRecoveryChoice]
    @State private var confirming = false

    init(review: VaultRecoveryReview, switchVault: @escaping () -> Void) {
        self.review = review; self.switchVault = switchVault
        _choices = State(initialValue: Dictionary(uniqueKeysWithValues: review.files.map { ($0.path, .current) }))
    }

    private var changedCount: Int {
        review.files.filter { $0.data(for: choices[$0.path] ?? .current) != $0.current }.count
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("An interrupted change needs a decision", systemImage: "arrow.trianglehead.2.clockwise.rotate.90").font(.headline)
                    Text("Another app or device changed a file before Zerus could finish recovering. Compare the saved versions, then choose what to keep for each file.").font(.subheadline).foregroundStyle(.secondary)
                    Text("Every version will be saved in a recovery copy before your choices are applied.").font(.subheadline)
                }
                if let error = vault.recoveryError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityIdentifier("recovery.error")
                    }
                }
                if !vault.recoveryDrafts.isEmpty {
                    Section {
                        ForEach(vault.recoveryDrafts) { draft in
                            NavigationLink { RecoveryVersionPreview(name: "Unsaved draft", path: draft.path, data: draft.data) } label: { Label(draft.path, systemImage: "doc.badge.clock") }
                        }
                    } header: { Text("Unsaved drafts") } footer: {
                        Text("These drafts will also be kept in the recovery copy. They will not replace your choices below.")
                    }
                }
                ForEach(review.files) { file in
                    Section {
                        RecoveryFileVersions(file: file)
                        Picker("Keep", selection: Binding(get: { choices[file.path] ?? .current }, set: { choices[file.path] = $0 })) {
                            ForEach(VaultRecoveryChoice.allCases) { Text($0.label).tag($0) }
                        }.accessibilityIdentifier("recovery.choice." + file.path)
                    } header: {
                        Text(file.path).textCase(nil)
                    } footer: {
                        if file.current != file.original && file.current != file.intended {
                            Text("The current file contains an outside change.")
                        }
                    }
                }
                Section {
                    Button { Task { await vault.reloadRecovery() } } label: { Label("Refresh review", systemImage: "arrow.clockwise") }.accessibilityIdentifier("recovery.refresh")
                    if vault.canReturnFromRecovery { Button("Return to " + vault.vaultName) { vault.returnFromRecovery() } }
                    Button(action: switchVault) { Label("Open another vault", systemImage: "folder") }.accessibilityIdentifier("recovery.switch")
                } footer: {
                    Text("No choices are applied until you confirm. A file that changes again will need a refreshed review.")
                }
            }
            .navigationTitle("Recover your vault").navigationBarTitleDisplayMode(.inline)
            .disabled(vault.recoverySaving || vault.loading)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply choices") { confirming = true }.disabled(vault.recoverySaving || vault.loading).accessibilityIdentifier("recovery.apply")
                }
            }
            .overlay {
                if vault.recoverySaving || vault.loading { ProgressView(vault.loading ? "Opening vault…" : "Recovering files…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
            }
            .confirmationDialog("Apply recovery choices?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Save choices and reopen") { Task { await vault.resolveRecovery(choices: choices) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(changedCount == 0
                     ? "The current files will stay as they are. Every saved version will be retained in Settings → Recovery copies."
                     : "\(changedCount) \(changedCount == 1 ? "file will" : "files will") change to the versions you selected, including any selected deletions. Every saved version will be retained in Settings → Recovery copies.")
            }
        }
    }
}

private struct RecoveryFileVersions: View {
    let file: VaultRecoveryFile
    var body: some View {
        version("Current", data: file.current, explanation: "On disk when reviewed")
        version("Original", data: file.original, explanation: "Before the interrupted change")
        version("Intended", data: file.intended, explanation: "The interrupted change’s result")
    }
    private func version(_ name: String, data: Data?, explanation: String) -> some View {
        NavigationLink {
            RecoveryVersionPreview(name: name, path: file.path, data: data)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(name); Spacer(); Text(data.map { ByteCountFormatter.string(fromByteCount: Int64($0.count), countStyle: .file) } ?? "No file").font(.caption).foregroundStyle(.secondary) }
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("recovery.version." + name.lowercased() + "." + file.path)
    }
}

private struct RecoveryVersionPreview: View {
    let name: String
    let path: String
    let data: Data?
    @State private var exportURL: URL?
    @State private var quickLook: URL?
    @State private var exportError: String?
    private let previewLimit = 256 * 1024
    private var textPreview: String? {
        guard let data else { return nil }
        var prefix = Data(data.prefix(previewLimit))
        guard !prefix.contains(0) else { return nil }
        // A preview boundary can split a UTF-8 scalar. Do not decode a huge
        // file merely to repair the last incomplete character.
        for _ in 0..<4 {
            if let text = String(data: prefix, encoding: .utf8) { return text }
            if prefix.isEmpty { break }; prefix.removeLast()
        }
        return nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(path).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                if let data {
                    if let text = textPreview {
                        Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        if data.count > previewLimit { Text("Showing the beginning of this version. Share the file to read its full contents.").font(.footnote).foregroundStyle(.secondary) }
                    } else {
                        ContentUnavailableView("File version", systemImage: "doc", description: Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))
                        if let exportURL { Button("Preview file") { quickLook = exportURL } }
                    }
                } else {
                    ContentUnavailableView("No file in this version", systemImage: "doc.badge.minus", description: Text("Choosing this version removes the file. The other versions stay in the recovery copy."))
                }
                if let exportError { Text(exportError).font(.footnote).foregroundStyle(.secondary) }
            }.padding()
        }
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        .toolbar { if let exportURL { ShareLink(item: exportURL).accessibilityLabel("Share this version") } }
        .quickLookPreview($quickLook)
        .task {
            guard let data, exportURL == nil else { return }
            do {
                exportURL = try await Task.detached {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-recovery-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let filename = (path as NSString).lastPathComponent
                    let url = folder.appendingPathComponent(filename.isEmpty || filename == "." || filename == ".." ? "Recovered file" : filename)
                    try data.write(to: url, options: .atomic)
                    return url
                }.value
            } catch { exportError = error.localizedDescription }
        }
    }
}

struct RecoveryCopiesView: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var copies: [VaultRecoveryCopy] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("Recovery copies keep every version reviewed during an interrupted change, including outside edits and files you chose to remove.").font(.subheadline).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Loading recovery copies…") }
            else if let error { Text(error).foregroundStyle(.secondary) }
            else if copies.isEmpty { ContentUnavailableView("No recovery copies", systemImage: "clock.arrow.circlepath", description: Text("A copy appears here after you resolve an interrupted change.")) }
            ForEach(copies) { copy in
                NavigationLink { RecoveryCopyDetail(copy: copy) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(copy.modified, format: .dateTime.year().month().day().hour().minute())
                        Text("Saved versions · " + ByteCountFormatter.string(fromByteCount: Int64(copy.bytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Recovery copies").navigationBarTitleDisplayMode(.inline)
        .task(id: vault.root) {
            loading = true
            do { copies = try await vault.recoveryCopies(); error = nil }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

private struct RecoveryCopyDetail: View {
    @EnvironmentObject private var vault: VaultStore
    let copy: VaultRecoveryCopy
    @State private var archive: VaultRecoveryArchive?
    @State private var error: String?
    var body: some View {
        List {
            if let archive {
                Section {
                    Text(archive.created, format: .dateTime.year().month().day().hour().minute())
                    Text("These are the exact versions seen during the review. Preview or share a version to keep a separate file.").font(.subheadline).foregroundStyle(.secondary)
                }
                if let drafts = archive.drafts, !drafts.isEmpty {
                    Section("Unsaved drafts") {
                        ForEach(drafts) { draft in
                            NavigationLink { RecoveryVersionPreview(name: "Unsaved draft", path: draft.path, data: draft.data) } label: { Label(draft.path, systemImage: "doc.badge.clock") }
                        }
                    }
                }
                ForEach(archive.files) { file in
                    Section {
                        RecoveryFileVersions(file: file)
                    } header: { Text(file.path).textCase(nil) } footer: {
                        Text("Chosen: " + (archive.choices[file.path]?.label ?? "Unknown"))
                    }
                }
            } else if let error { Text(error).foregroundStyle(.secondary) }
            else { ProgressView("Opening recovery copy…") }
        }
        .navigationTitle("Recovery copy").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let root = vault.root { ShareLink(item: root.appendingPathComponent(copy.path)).accessibilityLabel("Share recovery copy") }
        }
        .task { do { archive = try await vault.recoveryCopy(copy.path) } catch { self.error = error.localizedDescription } }
    }
}
