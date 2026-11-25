import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacCLISettingsView: View {
    var workspace: MacWorkspace? = nil
    @State private var setup = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macSettingsEmbedded) private var embedded
    @State private var status: MacCLIStatus?
    @State private var review: MacCLIInstallReview?
    @State private var busy = false
    @State private var issue: String?
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !embedded { Text("CLI and agent skills").font(.title2.bold()) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Use Zerus from a terminal or give an AI agent the same vault commands. Installation stays on this Mac.").foregroundStyle(.secondary)
                    if let status {
                        GroupBox("Zerus command line") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Bundled CLI " + status.version)
                                Text(status.path.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Text(status.matches ? "The bundled version is installed." : status.installed ? "The installed version is not checked by running it. Its bytes differ from this bundled build; review before replacing it." : "The CLI is not installed here.").font(.callout)
                                if let issue = status.issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                                if status.installed && !status.onPath { Text("Add this folder to your shell’s PATH, or use the full executable path.").font(.caption).foregroundStyle(.secondary) }
                                Button(status.matches ? "Reinstall CLI…" : status.installed ? "Update CLI…" : "Install CLI…") { prepare(.executable) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                        GroupBox("AI agent skills") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Skill version " + status.skillVersion + " teaches agents the CLI’s read, review and revision checks.").font(.callout)
                                ForEach(status.skills) { skill in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack { Text(skill.agent.label); Spacer(); Button(skill.matches ? "Reinstall…" : skill.installed ? "Update…" : "Install…") { prepare(.skill(skill.agent)) } }
                                        Text(skill.path.path).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                        if let issue = skill.issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                                    }
                                }
                                Button("Export skill…") { exportSkill() }
                            }.padding(8)
                        }
                        if let workspace, workspace.root != nil {
                            Button("Set up this vault for CLI use…") { setup = true }
                        }
                        Text("Pass --vault followed by a vault name or folder to choose explicitly; otherwise the CLI uses its registered default. Installing tools or skills does not change your notes.").font(.caption).foregroundStyle(.secondary)
                    } else if issue == nil { ProgressView("Reading installed tools…") }
                    if let message { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Refresh") { perform { await reload() } }
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                if !embedded { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }.macSettingsChrome(width: 660, height: 560).disabled(busy)
            .interactiveDismissDisabled(busy)
            .task { await reload() }
            .macSheet(isPresented: $setup) { if let workspace { MacCLISetupView(workspace: workspace) } }
            .confirmationDialog("Install " + (review?.label ?? "tools") + "?", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), titleVisibility: .visible) {
                if let review {
                    Button(review.before == nil ? "Install" : "Replace existing file") {
                        perform {
                            try await MacCLIInstaller.shared.install(review)
                            message = review.label + " installed at " + review.destination.path
                            await reload()
                        }
                    }
                }
                Button("Cancel", role: .cancel) { review = nil }
            } message: {
                if let review { Text(review.destination.path + (review.before == nil ? "\nCreates this file on this Mac." : "\nReplaces the existing file. Any custom changes to that file will be replaced.")) }
            }
    }
    private func reload() async {
        do { status = try await MacCLIInstaller.shared.status(); issue = nil }
        catch { issue = error.localizedDescription }
    }
    private func perform(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true; issue = nil; message = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { issue = error.localizedDescription }
        }
    }
    private func prepare(_ kind: MacCLIInstallReview.Kind) {
        perform { review = try await MacCLIInstaller.shared.prepare(kind) }
    }
    private func exportSkill() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "zerus-skill.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let review = try await MacCLIInstaller.shared.prepare(.export(url))
            try await MacCLIInstaller.shared.install(review)
            message = "Skill exported to " + url.path
        }
    }
}
