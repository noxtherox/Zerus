import SwiftUI

struct NativeDriveSyncView: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var keepLocal = Set<String>()
    @State private var issue: String?
    @State private var reconnecting = false
    @State private var resolving = false
    var body: some View {
        Form {
            Section {
                if let drive = vault.driveSelection { LabeledContent("Vault", value: drive.name); LabeledContent("Account", value: drive.email) }
                Text(vault.driveStatus ?? "This is a Files vault.").font(.callout).accessibilityIdentifier("drive.sync.status")
                Text("Edits save on this iPhone first. Keep this app open to finish syncing. Drive changes are checked before uploads; interrupted work resumes from its saved record.").font(.caption).foregroundStyle(.secondary)
                Button("Sync now", systemImage: "arrow.clockwise") { Task { await vault.flush(); await vault.refresh() } }.disabled(vault.driveSyncing).accessibilityIdentifier("drive.sync.now")
                Button("Reconnect Google account") { reconnecting = true }.accessibilityIdentifier("drive.sync.reconnect")
            }
            if let review = vault.driveConflict {
                Section {
                    Text("Choose which version to keep for each conflicting file. Files in Google Drive will only be replaced after checking that the reviewed version is still current.").font(.caption).foregroundStyle(.secondary)
                    ForEach(review.files) { file in
                        DisclosureGroup(file.path) {
                            version("On this iPhone", bytes: file.local)
                            version("In Google Drive", bytes: file.remote)
                            Toggle("Keep iPhone version", isOn: Binding(get: { keepLocal.contains(file.path) }, set: { if $0 { keepLocal.insert(file.path) } else { keepLocal.remove(file.path) } })).accessibilityIdentifier("drive.conflict." + file.path)
                        }
                    }
                    Button("Apply reviewed choices") {
                        resolving = true; issue = nil
                        Task { defer { resolving = false }; do { try await vault.resolveDrive(review, keepLocal: keepLocal) } catch { issue = error.localizedDescription } }
                    }.accessibilityIdentifier("drive.conflict.apply")
                } header: { Text("Review both versions") } footer: { Text("With the switch off, the Drive version is kept. Replaced note versions remain in native history when their format supports capture.") }
            }
            if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled) } }
        }.navigationTitle("Google Drive sync").navigationBarTitleDisplayMode(.inline)
            .disabled(resolving)
            .onChange(of: vault.driveConflict?.id) { _, _ in keepLocal = [] }
            .sheet(isPresented: $reconnecting) { NativeDriveFolderBrowser(choose: nil) }
    }
    @ViewBuilder private func version(_ title: String, bytes: Data?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            if let bytes {
                if bytes.count <= 100_000, let text = String(data: bytes, encoding: .utf8) { ScrollView([.horizontal, .vertical]) { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 220) }
                else { Text(ByteCountFormatter.string(fromByteCount: Int64(bytes.count), countStyle: .file)).foregroundStyle(.secondary) }
            } else { Text("File removed").foregroundStyle(.secondary) }
        }
    }
}

struct NativeDriveSyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { NativeDriveSyncView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } } }
}
