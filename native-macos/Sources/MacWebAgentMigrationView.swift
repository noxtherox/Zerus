import SwiftUI

struct MacWebAgentMigrationView: View {
    let review: MacWebAgentMigrationReview
    let commit: @MainActor () async throws -> Void
    @State private var stoppedOriginal = false
    @State private var busy = false
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import saved web run").font(.title2.bold())
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                Text(review.record.run.objective).font(.headline).textSelection(.enabled)
                Text("\(review.record.run.mode.rawValue) · \(review.source.run.status) · \(review.record.run.steps) cumulative steps · \(review.record.run.inputTokens + review.record.run.outputTokens) reported/estimated tokens")
                Text(review.record.run.scopeLabel)
                Text("Readable note grants: \(review.record.run.readIDs.count). Writable note grants: \(review.record.run.writeIDs.count). Folder boundaries remain enforced if a note moves.")
                DisclosureGroup("Exact note grants") { ForEach(Array(review.grants.enumerated()), id: \.offset) { _, grant in Text(grant).textSelection(.enabled) } }
                Text(review.record.run.createFolders.isEmpty ? "New-note creation is disabled." : "Creation prefixes: " + review.record.run.createFolders.joined(separator: ", "))
                if let binding = try? MacAgentProviderBinding.read(review.record) { Text("Continuation connection: " + binding.kind + " · " + binding.model + " · " + binding.endpoint).textSelection(.enabled) }
                let limits = review.record.run.budget
                Text("Frozen native limits: \(limits.maxSteps) cumulative steps, \(limits.maxMinutes) active minutes, \(limits.maxTotalTokens) total tokens; \(limits.maxInputTokens) input and \(limits.maxOutputTokens) output per request.")
                DisclosureGroup("Instructions and workflow to freeze") {
                    Text(review.record.run.guidance?.instructions ?? "").textSelection(.enabled)
                    Text(review.record.run.workflow?.title ?? "General notes task").font(.headline)
                    Text(review.record.run.workflow?.instructions ?? "").textSelection(.enabled)
                    Text("Memory reference").font(.headline); Text(review.record.run.guidance?.memory ?? "").textSelection(.enabled)
                }
                DisclosureGroup("Active model transcript (\(review.transcript.count) messages)") {
                    if review.transcript.count > 30 { Text("Preview shows the first 30 messages. The complete transcript remains in the exact source archive.").font(.caption) }
                    ForEach(Array(review.transcript.prefix(30).enumerated()), id: \.offset) { _, message in
                        Text(message.role.capitalized).font(.caption.bold())
                        Text(message.content).textSelection(.enabled)
                        if let calls = message.toolCalls { ForEach(calls) { call in Text(call.name + " " + call.arguments).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
                        if !message.images.isEmpty { Text("\(message.images.count) frozen images").font(.caption) }
                    }
                }
                Text("\(review.record.run.proposals.count) proposals and \(review.record.run.receipts.count) individual receipts will be retained. Import applies none of them. Open a proposal or Undo receipt afterward to review its exact files.")
                ForEach(review.notices, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                Text("The complete original journal stays unchanged and receives a separate immutable source copy. Other clients that cannot enforce the imported permissions will refuse this native run.").font(.caption)
                Text("This is a one-way native continuation. The original web journal does not receive changes made after import.").font(.caption)
                Toggle("I stopped this run in the original client and reviewed the continuation settings above", isOn: $stoppedOriginal)
                if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.disabled(busy)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Import reviewed run") {
                    busy = true; issue = nil
                    Task { do { try await commit(); dismiss() } catch { issue = error.localizedDescription }; busy = false }
                }.disabled(busy || !stoppedOriginal)
            }
        }.padding(24).frame(width: 740, height: 650).interactiveDismissDisabled(busy)
    }
}
