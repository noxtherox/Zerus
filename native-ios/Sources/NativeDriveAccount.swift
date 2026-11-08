import ZerusIOSServices
import AuthenticationServices
import SwiftUI

@MainActor
final class NativeDriveAccount: ObservableObject {
    static let shared = NativeDriveAccount()
    @Published private(set) var configured = false
    @Published private(set) var accountID: String?
    @Published private(set) var email: String?
    @Published private(set) var busy = false
    @Published private(set) var issue: String?
    private let manager = GoogleDriveManager()
    private var epoch = UUID()
    func reload() async {
        do { try apply(await manager.run(.init(operation: "status"))); issue = nil }
        catch { issue = error.localizedDescription }
    }
    private func apply(_ status: [String: Any]) throws {
        configured = status["configured"] as? Bool == true
        if let account = status["account"] as? [String: Any] {
            guard let id = account["accountId"] as? String, NativeDriveFiles.validID(id), let email = account["email"] as? String else { throw VaultFailure(message: "The saved Google Drive connection could not be read.") }
            if accountID != id { epoch = UUID() }
            accountID = id; self.email = email
        } else { if accountID != nil { epoch = UUID() }; accountID = nil; email = nil }
    }
    func connect(presenter: ASWebAuthenticationPresentationContextProviding, reconnect: Bool) async {
        guard !busy else { return }; busy = true; issue = nil; epoch = UUID()
        defer { busy = false }
        do { try apply(await manager.run(.init(operation: reconnect ? "reconnect" : "connect"), presenter: presenter)) }
        catch { issue = error.localizedDescription }
    }
    func disconnect() async {
        guard !busy else { return }; busy = true; issue = nil; epoch = UUID()
        defer { busy = false }
        do { try apply(await manager.run(.init(operation: "disconnect"))) }
        catch { issue = error.localizedDescription }
    }
    func files(account expected: String? = nil) async throws -> NativeDriveFiles {
        guard !busy else { throw CancellationError() }
        try apply(await manager.run(.init(operation: "status")))
        guard configured, let accountID, expected == nil || expected == accountID, !busy else { throw VaultFailure(message: "Connect the original Google account in File locations → Google Drive.") }
        let origin = epoch
        return NativeDriveFiles(accountID: accountID) { [weak self] command in
            guard let self, self.epoch == origin, self.accountID == accountID, !self.busy else { throw CancellationError() }
            let response = try await self.manager.run(command)
            guard self.epoch == origin, self.accountID == accountID, !self.busy else { throw CancellationError() }
            return response
        }
    }
}

/// Resolve the anchor from the presenting SwiftUI hierarchy, rather than
/// borrowing a window from another scene (or manufacturing an empty window).
struct NativeDriveAnchor: UIViewRepresentable {
    final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        weak var view: UIView?
        var anchor: UIWindow?
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor! }
        func prepare() -> Bool { anchor = view?.window; return anchor != nil }
    }
    let presenter: Presenter
    func makeUIView(context: Context) -> UIView { let view = UIView(); presenter.view = view; return view }
    func updateUIView(_ uiView: UIView, context: Context) { presenter.view = uiView }
}

struct NativeDriveFolderBrowser: View {
    @ObservedObject private var account = NativeDriveAccount.shared
    @Environment(\.dismiss) private var dismiss
    let choose: ((NativeDriveFolder) async throws -> Void)?
    var vaultPurpose = false
    init(vaultPurpose: Bool = false, choose: ((NativeDriveFolder) async throws -> Void)?) { self.vaultPurpose = vaultPurpose; self.choose = choose }
    @State private var presenter = NativeDriveAnchor.Presenter()
    @State private var trail: [(id: String, name: String)] = [("root", "My Drive")]
    @State private var folders: [NativeDriveItem] = []
    @State private var loading = false
    @State private var saving = false
    @State private var saveJob: Task<Void, Never>?
    @State private var issue: String?
    @State private var retry = UUID()
    @State private var disconnecting = false
    private var current: (id: String, name: String) { trail.last! }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(vaultPurpose ? "Choose the folder containing your Markdown vault. Zerus keeps a private working copy on this iPhone and syncs changes with Google Drive." : choose == nil ? "Connect Google Drive to browse folders for your file locations." : "Choose the Drive folder that matches this file location. Connected documents download for previews; their original files stay in Drive.").font(.subheadline).foregroundStyle(.secondary)
                    if !account.configured {
                        Label("Google Drive setup is needed in this preview.", systemImage: "wrench.and.screwdriver").accessibilityIdentifier("drive.setup")
                        Text("The developer must configure this app’s Google sign-in client. Your Files vault remains available.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let email = account.email { LabeledContent("Google account", value: email) }
                    else { Text("Google will ask for access to your Drive files so Zerus can use the folders you choose. Sign-in stays on this iPhone.").font(.caption).foregroundStyle(.secondary) }
                    if let message = issue ?? account.issue { Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("drive.issue") }
                }
                if account.accountID != nil {
                    Section(current.name) {
                        if trail.count > 1 { Button("Parent folder", systemImage: "arrow.up") { trail.removeLast() }.accessibilityIdentifier("drive.parent") }
                        if loading { ProgressView("Loading folders…") }
                        ForEach(folders) { folder in
                            Button {
                                guard !trail.contains(where: { $0.id == folder.id }) else { issue = "This folder path repeats. Refresh Google Drive before continuing."; return }
                                trail.append((folder.id, folder.name))
                            } label: {
                                HStack { Image(systemName: "folder").foregroundStyle(Accent.color); Text(folder.name).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                            }.accessibilityIdentifier("drive.folder." + folder.id)
                        }
                        if !loading && folders.isEmpty && issue == nil { Text("No subfolders").foregroundStyle(.secondary) }
                        Button("Refresh folders", systemImage: "arrow.clockwise") { retry = UUID() }.accessibilityIdentifier("drive.refresh")
                    }
                    if let choose {
                        Section { Button(vaultPurpose ? "Open this vault" : "Use this folder", systemImage: "checkmark.circle") { save(choose) }.disabled(loading || saving || issue != nil || vaultPurpose && current.id == "root").accessibilityIdentifier("drive.choose") }
                    }
                }
                Section {
                    Button(account.accountID == nil ? "Connect Google Drive" : "Reconnect Google account", systemImage: "person.crop.circle.badge.checkmark") {
                        guard presenter.prepare() else { issue = "Google sign-in is not ready. Reopen this screen."; return }
                        Task { defer { presenter.anchor = nil }; await account.connect(presenter: presenter, reconnect: account.accountID != nil); trail = [("root", "My Drive")]; retry = UUID() }
                    }.disabled(!account.configured).accessibilityIdentifier("drive.connect")
                    if account.accountID != nil { Button("Disconnect Google account", role: .destructive) { disconnecting = true }.accessibilityIdentifier("drive.disconnect") }
                } footer: { Text("Google sign-in stays in the iOS Keychain. Disconnecting removes this device’s sign-in; saved folder mappings and original files are kept.") }
            }.navigationTitle("Google Drive").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("drive.done") } }
                .disabled(account.busy || saving)
                .overlay { if account.busy || saving {
                    VStack(spacing: 12) {
                        ProgressView(account.busy ? "Connecting…" : vaultPurpose ? "Opening your Drive vault…" : "Saving folder…")
                        if saving { Button("Cancel") { saveJob?.cancel() }.accessibilityIdentifier("drive.open.cancel") }
                    }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                } }
                .background(NativeDriveAnchor(presenter: presenter).frame(width: 0, height: 0))
                .interactiveDismissDisabled(account.busy || saving)
                .task { await account.reload() }
                .task(id: current.id + (account.accountID ?? "") + retry.uuidString) { await load() }
                .confirmationDialog("Disconnect Google Drive on this iPhone?", isPresented: $disconnecting, titleVisibility: .visible) {
                    Button("Disconnect", role: .destructive) { Task { await account.disconnect(); folders = []; trail = [("root", "My Drive")] } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Documents already shared or copied remain available. Saved mappings require reconnecting the same account.") }
        }
    }
    private func load() async {
        folders = []; issue = nil
        guard account.accountID != nil else { return }
        let folder = current.id, request = retry; loading = true
        defer { if current.id == folder && retry == request { loading = false } }
        do {
            let items = try await account.files().children(folder)
            try Task.checkCancellation()
            guard current.id == folder, retry == request else { return }
            folders = items.filter(\.folder).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch is CancellationError {} catch { if current.id == folder, retry == request { issue = error.localizedDescription } }
    }
    private func save(_ choose: @escaping (NativeDriveFolder) async throws -> Void) {
        guard let id = account.accountID, let email = account.email else { return }
        let selection = NativeDriveFolder(accountID: id, email: email, folderID: current.id, name: current.name)
        saving = true; issue = nil
        saveJob = Task { defer { saving = false; saveJob = nil }; do { try await choose(selection); try Task.checkCancellation(); dismiss() } catch is CancellationError { dismiss() } catch { if Task.isCancelled { dismiss() } else { issue = error.localizedDescription } } }
    }
}
