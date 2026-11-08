import SwiftUI
import UniformTypeIdentifiers

struct NativeVaultsView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var picking = false
    @State private var drivePicking = false
    @State private var renaming: NativeSavedVault?
    @State private var removing: NativeSavedVault?
    @State private var name = ""
    @State private var creating = false
    @State private var newName = ""
    var body: some View {
        List {
            Section {
                Button("Open a vault in Files", systemImage: "folder.badge.plus") { picking = true }.accessibilityIdentifier("vaults.open")
                Button("Open a Google Drive vault", systemImage: "externaldrive.badge.icloud") { drivePicking = true }.accessibilityIdentifier("vaults.drive")
                Button("Create a vault on this iPhone", systemImage: "plus") { newName = ""; creating = true }.accessibilityIdentifier("vaults.create")
            }
            if let issue = vault.savedVaultIssue {
                Section { Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary).font(.callout) }
            }
            Section {
                if vault.savedVaults.isEmpty { ContentUnavailableView("Your vaults, together", systemImage: "books.vertical", description: Text("Open a folder in Files or Google Drive, or create a vault on this iPhone.")) }
                ForEach(vault.savedVaults) { record in
                    vaultRow(record).padding(.vertical, 3)
                }
            } header: { Text("Saved vaults") } footer: {
                Text("Access is saved on this device. All open windows share the current vault. Switching first saves your notes; unavailable folders stay in this list so you can try again.")
            }
        }
        .navigationTitle("Vaults").navigationBarTitleDisplayMode(.inline)
        .disabled(vault.switchingVault)
        .sheet(isPresented: $drivePicking) { NativeDriveFolderBrowser(vaultPurpose: true) { selection in
            let opened = await vault.openDrive(selection); try Task.checkCancellation(); guard opened else { let message = vault.error ?? "The Drive vault could not be opened."; vault.error = nil; throw VaultFailure(message: message) }
        } }
        .overlay { if vault.switchingVault { ProgressView("Opening your vault…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await vault.open(url) }
            case .failure(let error): vault.error = error.localizedDescription
            }
        }
        .alert("Name in saved vaults", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Vault name", text: $name).accessibilityIdentifier("vaults.name")
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { if let record = renaming { vault.renameSavedVault(record.id, to: name) }; renaming = nil }
        } message: { Text("This changes the name in this list. The folder and its files keep their names. Leave it empty to use the folder name.") }
        .alert("Remove \(removing?.title ?? "vault") from this list?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove from list", role: .destructive) { if let record = removing { vault.removeSavedVault(record.id) }; removing = nil }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text(removing?.drive == nil ? "The folder, notes and local history are kept. An open vault stays open until you switch or close the app. You can add it again from Files." : "The Drive folder, working copy, notes and local history are kept. An open vault stays open until you switch or close the app. Choose the same Google Drive folder to add it again.") }
        .alert("New vault on this iPhone", isPresented: $creating) {
            TextField("Vault name", text: $newName).accessibilityIdentifier("vaults.newName")
            Button("Cancel", role: .cancel) { }
            Button("Create") { Task { await vault.createLocal(name: newName) } }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("Create a separate folder of Markdown notes. You can find it in Files → On My iPhone → Zerus Native → Vaults.") }
    }
    @ViewBuilder private func vaultRow(_ record: NativeSavedVault) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    vaultIcon(record)
                    Spacer()
                    if record.id == vault.activeVaultID { Image(systemName: "checkmark").foregroundStyle(Accent.color).accessibilityHidden(true) }
                    vaultMenu(record)
                }
                vaultButton(record, expanded: true)
            }
        } else {
            HStack(spacing: 12) {
                vaultButton(record, expanded: false)
                vaultMenu(record)
            }
        }
    }
    private func vaultIcon(_ record: NativeSavedVault) -> some View {
        Image(systemName: record.id == vault.activeVaultID ? "folder.fill" : "folder").foregroundStyle(Accent.color).accessibilityHidden(true)
    }
    private func vaultSummary(_ record: NativeSavedVault) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title).font(.body.weight(.medium)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(record.locationDescription).font(.caption).foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1).fixedSize(horizontal: false, vertical: true)
            if record.id == vault.activeVaultID { Text("Current vault").font(.caption).foregroundStyle(Accent.color).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func vaultButton(_ record: NativeSavedVault, expanded: Bool) -> some View {
        Button {
            guard record.id != vault.activeVaultID else { return }
            Task { await vault.openSavedVault(record.id) }
        } label: {
            Group {
                if expanded { vaultSummary(record) }
                else {
                    HStack(spacing: 12) {
                        vaultIcon(record)
                        vaultSummary(record)
                        Spacer(minLength: 0)
                        if record.id == vault.activeVaultID { Image(systemName: "checkmark").foregroundStyle(Accent.color).accessibilityHidden(true) }
                    }
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("vault.saved.\(record.id)")
            .accessibilityAddTraits(record.id == vault.activeVaultID ? .isSelected : [])
    }
    private func vaultMenu(_ record: NativeSavedVault) -> some View {
        Menu {
            Button("Rename in list", systemImage: "pencil") { name = record.name ?? record.folder; renaming = record }
            Button("Remove from list", systemImage: "minus.circle", role: .destructive) { removing = record }
        } label: { Image(systemName: "ellipsis.circle").padding(8).frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Manage \(record.title)").accessibilityIdentifier("vault.manage.\(record.id)")
    }

}

struct NativeVaultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            NativeVaultsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
