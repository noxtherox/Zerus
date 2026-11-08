import SwiftUI

struct NativeMoveNoteView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let notePath: String
    let workspace: UUID?
    let moved: () -> Void
    @State private var snapshot: NativeRelationDefinitionSnapshot?
    @State private var newFolder = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var plan: NativeRelationMaintenancePlan?
    private var folders: [String] {
        var result = Set(["Inbox"])
        for folder in vault.folders {
            do { try NativePropertyDefinition.validateOwner(folder); result.insert(folder) }
            catch { continue }
        }
        return result.sorted()
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text((notePath as NSString).lastPathComponent).font(.headline)
                    Text("Note links, attachments and populated relations stay connected. Review the affected files before moving.").font(.subheadline).foregroundStyle(.secondary)
                }
                if let failure { Section { Text(failure).foregroundStyle(.orange); Button("Reload folders") { Task { await reload() } } } }
                if busy && snapshot != nil { ProgressView("Preparing move…") }
                if snapshot != nil {
                    Section {
                        TextField("New folder", text: $newFolder).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("move.newFolder")
                        Button("Review move") { prepare(newFolder.trimmingCharacters(in: .whitespacesAndNewlines)) }.disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("move.review")
                    } header: { Text("Create a folder") } footer: { Text("Use / for subfolders, up to eight levels. An existing note is never replaced.") }
                    Section("Choose a folder") {
                        ForEach(folders, id: \.self) { folder in
                            Button(folder) { prepare(folder) }.accessibilityIdentifier("move.folder." + folder)
                                .disabled(folder == (snapshot?.notes.first { $0.path == notePath }?.folder))
                        }
                    }
                } else if failure == nil { ProgressView("Loading folders…") }
            }
            .disabled(busy)
            .navigationTitle("Move note").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy).accessibilityIdentifier("move.cancel") } }
            .interactiveDismissDisabled(busy)
            .task { await reload() }
            .sheet(item: $plan) { plan in NativeRelationMaintenanceReview(plan: plan) { self.plan = nil; moved() } }
        }
    }
    private func reload() async {
        guard workspace == vault.workspaceID else { return }
        busy = true
        defer { busy = false }
        do { snapshot = try await vault.relationDefinitionSnapshot(); failure = nil }
        catch { snapshot = nil; failure = error.localizedDescription }
    }
    private func prepare(_ folder: String) {
        guard let snapshot else { return }
        let source = notePath, prefix = folder == "Inbox" ? "" : folder + "/"
        var filename = (notePath as NSString).lastPathComponent
        if notePath.hasPrefix(".zerus/links/"), let note = snapshot.notes.first(where: { $0.path == notePath }) {
            let stem = note.title.replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression)
            filename = (stem.isEmpty ? "Link" : stem) + ".md"
            var number = 2
            while snapshot.notes.contains(where: { $0.path.caseInsensitiveCompare(prefix + filename) == .orderedSame }) { filename = stem + " \(number).md"; number += 1 }
        }
        let destination = prefix + filename
        busy = true; failure = nil
        Task {
            defer { busy = false }
            do { plan = try await vault.prepareMove(snapshot, source: source, destination: destination) }
            catch { failure = error.localizedDescription }
        }
    }
}

struct NativeRelationRepairView: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var plan: NativeRelationMaintenancePlan?
    @State private var reviewing: NativeRelationMaintenancePlan?
    @State private var busy = false
    @State private var failure: String?
    var body: some View {
        List {
            Section {
                Text("Restore relation fields left behind by older folder moves. A repair requires matching definitions and values that resolve to eligible notes. Ambiguous or unsupported fields stay unchanged.").font(.subheadline).foregroundStyle(.secondary)
            }
            if busy { ProgressView("Checking relation fields…") }
            if let failure { Section { Text(failure).foregroundStyle(.orange) } }
            if let plan {
                Section {
                    Text(plan.hasChanges ? "\(plan.changedNotes.count) note files will be updated" : plan.issues.isEmpty ? "No repairs needed" : "No unambiguous repairs found").font(.headline)
                    ForEach(Array(plan.summaries.enumerated()), id: \.offset) { _, summary in Text(summary) }
                    if plan.hasChanges { Button("Review repairs") { reviewing = plan }.accessibilityIdentifier("relations.repair.review") }
                }
                if !plan.issues.isEmpty {
                    Section("Needs your attention") {
                        ForEach(plan.issues) { issue in
                            VStack(alignment: .leading, spacing: 6) { Text(issue.name).font(.headline); Text(issue.path).font(.caption).foregroundStyle(.secondary); Text(issue.reason).font(.subheadline) }
                        }
                    }
                }
            }
            Button("Check again", systemImage: "arrow.clockwise") { Task { await reload() } }.disabled(busy)
        }
        .navigationTitle("Legacy relations").navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(item: $reviewing) { plan in NativeRelationMaintenanceReview(plan: plan) { reviewing = nil; Task { await reload() } } }
    }
    private func reload() async {
        busy = true
        defer { busy = false }
        do {
            let snapshot = try await vault.relationDefinitionSnapshot()
            plan = try await Task.detached { try snapshot.repairPlan() }.value; failure = nil
        } catch { plan = nil; failure = error.localizedDescription }
    }
}

private struct NativeRelationMaintenanceReview: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let plan: NativeRelationMaintenancePlan
    let saved: () -> Void
    @State private var busy = false
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let source = plan.sourcePath, let destination = plan.destination {
                        LabeledContent("From", value: source); LabeledContent("To", value: destination)
                    }
                    Text("All listed files are checked again and saved together. Cancel leaves them unchanged.").foregroundStyle(.secondary)
                }
                if !plan.summaries.isEmpty { Section("Changes") { ForEach(Array(plan.summaries.enumerated()), id: \.offset) { _, summary in Text(summary) } } }
                Section("Note files to update") { ForEach(plan.changedNotes, id: \.self) { Text($0).font(.subheadline) } }
                if let failure { Section { Text(failure).foregroundStyle(.orange); Text("Cancel and reload the review to use current files.").font(.caption).foregroundStyle(.secondary) } }
            }
            .navigationTitle(plan.destination == nil ? "Review repairs" : "Review move").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy).accessibilityIdentifier("maintenance.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() }
                    else { Button(plan.destination == nil ? "Repair relations" : "Move note") { commit() }.disabled(!plan.hasChanges).accessibilityIdentifier("maintenance.confirm") }
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }
    private func commit() {
        busy = true; failure = nil
        Task {
            defer { busy = false }
            do { try await vault.saveRelationMaintenance(plan); dismiss(); saved() }
            catch { failure = error.localizedDescription }
        }
    }
}
