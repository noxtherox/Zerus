import Foundation

/// Review is a frozen proposal: importing creates journals and private inputs,
/// never applies the note changes described by the source journal.
struct MacWebAgentMigrationReview: Identifiable, Sendable {
    var id: UUID { record.id }
    let root: URL
    let source: MacWebAgentRunRecord
    let children: [MacWebAgentRunRecord]
    let sourceInventory: Set<String>
    let record: NativeAgentRecord
    let attachments: [NativePreparedChatAttachment]
    let conversation: MacConversationSnapshot
    let dependencies: [VaultFileChange]
    let grants: [String]
    let notices: [String]
    let transcript: [NativeAgentMessage]
    let compaction: MacAgentCompactionPlan?
    let storage: NativeAgentStoragePlan
    let importIndex: MacWebAgentImportPlan
}

extension VaultFiles {
    func prepareMacWebAgentMigration(path: String, owner: String, binding: MacAgentProviderBinding, contextCapacity: Int? = nil) async throws -> MacWebAgentMigrationReview {
        let source = try macWebAgentRun(path: path), web = source.run
        guard web.parentRunID == nil else { throw MacWebAgentRun.problem("Choose the parent run; worker journals are reference history, not standalone conversations.") }
        let chat = try conversationSnapshot(web.chatID)
        guard chat.conversation.owner.id == owner, chat.conversation.archivedAt == nil, chat.conversation.deletedAt == nil else {
            throw MacWebAgentRun.problem("Open and explicitly claim the original conversation on this Mac before importing its runs.")
        }
        let importIndex = try prepareMacWebAgentImportIndex(source)
        let settings = try agentLimits(), guidance = try agentGuidance(), workflow = try agentSelectedWorkflow(settings: settings.bytes)
        let preferences = try NativeAgentPreferences.read(settings.bytes)
        let history = try await MacWebAgentHistory.prepare(source, textFallback: preferences.textFallback)
        try Task.checkCancellation()
        guard try read(path) == source.bytes else { throw MacWebAgentRun.problem("The web run changed while preparing its transcript. Stop it on the original client and review it again.") }
        let sourceFolder = try url(for: ".zerus/ai/runs/" + web.chatID)
        let sourceInventory = try Self.webSourceInventory(sourceFolder)
        let catalog = try macWebAgentRuns(chatID: web.chatID)
        let children = try catalog.records.filter { $0.parentRunID == web.id }.map { try macWebAgentRun(path: $0.path) }
        guard try Self.webSourceInventory(sourceFolder) == sourceInventory else { throw MacWebAgentRun.problem("The source journal inventory changed while preparing the import.") }
        guard catalog.issues.isEmpty else { throw MacWebAgentRun.problem("Resolve unreadable journals in this conversation before importing, so no worker source is omitted.") }
        guard children.reduce(source.bytes.count, { $0 + $1.bytes.count }) <= 128 * 1024 * 1024 else { throw MacWebAgentRun.problem("The parent and worker source archives exceed 128 MB.") }
        let notes = try scan().notes
        let id = importIndex.runID, archive = ".zerus/native-ai/web-sources/" + id.uuidString.lowercased() + ".json"
        let snapshots = web.proposals.flatMap { $0.before + $0.relatedAfter } + web.receipts.flatMap { $0.before + $0.after }
        var aliases: [String: String] = [:], notices = history.notices
        if importIndex.reimport { notices.append("This creates a fresh native run from the selected web snapshot. Deleted native progress and Undo access are not restored. Import never overwrites existing notes.") }
        for sourceID in Set(web.readIDs + web.writeIDs) {
            let identified = notes.filter { $0.stableID == sourceID }
            if identified.count == 1 { aliases[sourceID] = NativeAgentNote.identity(identified[0]); continue }
            guard identified.isEmpty else { throw MacWebAgentRun.problem("A granted note identity is duplicated in the vault.") }
            let saved = snapshots.filter { $0.id == sourceID }
            let candidates = notes.filter { note in note.stableID == nil && saved.contains { $0.path == note.path && $0.content == note.content } }
            let identities = Set(candidates.map(NativeAgentNote.identity))
            guard identities.count <= 1 else { throw MacWebAgentRun.problem("A legacy granted note has several possible matches. Give it a stable identity in the original client first.") }
            if let mapped = identities.first { aliases[sourceID] = mapped }
            else if let known = saved.last { aliases[sourceID] = NativeAgentNote.identity(known.document); notices.append("Granted note “" + known.title + "” is currently unavailable. Its historical grant and snapshots are retained; no title-based match is used.") }
            else { throw MacWebAgentRun.problem("Granted note " + sourceID + " has no stable identity or historical path snapshot. Persist its note metadata in the original client first.") }
        }
        guard let scopeText = web.scopeKey, let scope = try NativeJSON.object(with: Data(scopeText.utf8)) as? [String: Any], let kind = scope["kind"] as? String else {
            throw MacWebAgentRun.problem("The original run has no readable saved scope. Review its permissions in the original client first.")
        }
        var folder: String?, includesChildren = true, selectedIDs: Set<String>?
        switch kind {
        case "vault", "external", "files", "links": break
        case "type":
            guard let parts = scope["path"] as? [String], parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") }),
                  scope["includeSubtypes"] == nil || NativeRevisions.boolean(scope["includeSubtypes"]!) != nil else { throw MacWebAgentRun.problem("The saved folder scope is unsupported.") }
            folder = parts.joined(separator: "/"); includesChildren = scope["includeSubtypes"] as? Bool ?? true
        case "selection":
            guard let ids = scope["noteIds"] as? [String] else { throw MacWebAgentRun.problem("The saved selected-note scope is unsupported.") }; selectedIDs = Set(ids)
        case "note":
            guard let selected = scope["noteId"] as? String else { throw MacWebAgentRun.problem("The saved current-note scope is unsupported.") }; selectedIDs = [selected]
        default: throw MacWebAgentRun.problem("The saved scope needs a compatible permission adapter.")
        }
        let proposalIDs = web.proposals.map { MacWebAgentRun.nativeID(source.id + "/proposal/" + $0.id) }
        let receiptIDs = web.receipts.map { MacWebAgentRun.nativeID(source.id + "/receipt/" + $0.id) }
        let prefixes = web.mode == .ask || !["vault", "type"].contains(kind) ? [] : web.createTypes
        var policy = NativeAgentWebMigration(sourcePath: source.path, sourceDigest: source.digest, archivePath: archive, scopeKind: kind, folder: folder, includeSubtypes: includesChildren, aliases: aliases, creationPrefixes: prefixes, proposalIDs: proposalIDs, receiptIDs: receiptIDs)
        policy.childSources = children.isEmpty ? nil : children.map { child in .init(sourcePath: child.path, archivePath: ".zerus/native-ai/web-sources/" + id.uuidString.lowercased() + "-children/" + MacWebAgentRun.nativeID(child.id).uuidString.lowercased() + ".json", digest: child.digest) }
        try policy.validate(runID: id)
        func grant(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { selectedIDs?.contains($0) ?? true }.compactMap { aliases[$0] }.filter { seen.insert($0).inserted } }
        var run = NativeAgentRun(id: id, chatID: web.chatID, owner: owner, objective: web.objective, mode: web.mode,
            scopeLabel: "Imported web run · " + (folder.map { $0.isEmpty ? "Vault root" : $0 + (includesChildren ? " and child folders" : " only") } ?? kind),
            scopeKind: .selected, readFolder: nil, readIDs: grant(web.readIDs), writeIDs: web.mode == .ask ? [] : grant(web.writeIDs), createFolders: prefixes)
        run.version = 7; run.webMigration = policy; run.currentReadID = ""
        if !prefixes.isEmpty { run.organizationFolders = prefixes }
        run.status = web.status == "running" ? "interrupted" : web.status
        run.guidance = guidance.guidance; run.workflow = workflow; run.limits = settings.limits
        var frozen = preferences; frozen.mode = .init(web.mode); frozen.writeScope = .context; run.preferences = frozen
        run.messages = history.messages; run.attachments = history.attachments.isEmpty ? nil : history.attachments.map(\.descriptor)
        run.planSteps = web.plan; run.plan = web.plan.map(\.text); run.question = web.question; run.questionOptions = web.questionOptions
        func charged(_ value: Double) throws -> Int { guard value <= 10_000_000 else { throw MacWebAgentRun.problem("Reported usage exceeds the native journal's accounting range.") }; return Int(ceil(value)) }
        run.outputTokens = try charged(web.usage.outputTokens)
        run.inputTokens = try charged(max(web.usage.inputTokens, (web.usage.budgetTokens ?? 0) - Double(run.outputTokens)))
        guard web.usage.steps <= 100, web.usage.steps.rounded(.down) == web.usage.steps else { throw MacWebAgentRun.problem("This run exceeds the native cumulative step range. Its original accounting is preserved.") }
        run.steps = Int(web.usage.steps); run.activeSeconds = web.usage.elapsedMilliseconds / 1000
        if !children.isEmpty {
            var accounted = Set<String>()
            for event in web.events {
                if let raw = try NativeJSON.object(with: event.original) as? [String: Any], let detail = raw["detail"] as? [String: Any], let rows = detail["runs"] as? [[String: Any]] { accounted.formUnion(rows.compactMap { $0["id"] as? String }) }
            }
            let pendingAnalysis = run.pendingCalls.filter { $0.name == "analyze_notes" }
            if !pendingAnalysis.isEmpty {
                let unsettled = children.filter { !accounted.contains($0.run.id) }
                for child in unsettled {
                    run.outputTokens += try charged(child.run.usage.outputTokens)
                    run.inputTokens += try charged(max(child.run.usage.inputTokens, (child.run.usage.budgetTokens ?? 0) - child.run.usage.outputTokens))
                }
                let reports = try children.map { child -> [String: Any] in
                    let transcript = try child.run.messages.map { try NativeJSON.object(with: $0) as? [String: Any] }
                    let last = transcript.compactMap { $0 }.last { $0["role"] as? String == "assistant" }
                    let text = (last?["content"] as? String) ?? ((last?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? "")
                    return ["sourceRunId": child.run.id, "question": child.run.objective, "status": child.run.status, "partial": child.run.status != "complete", "text": text]
                }
                let result = String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "trusted": false, "interruptedByMigration": true, "analyses": reports], options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
                for call in pendingAnalysis { run.messages.append(.init(role: "tool", content: result, toolCallId: call.id)) }
                notices.append("Original web workers were stopped. Their saved partial/final answers and unaccounted reported usage are retained; continuation receives these untrusted results without restarting the old worker requests.")
            }
            notices.append("\(children.count) complete worker source journals will be archived with this parent.")
        }
        run.events = web.events.map { .init(id: MacWebAgentRun.nativeID(source.id + "/event/" + $0.id), date: $0.date, text: "[Web " + $0.kind + "] " + $0.text) }
        var occupied = Set(notes.map { $0.path.lowercased() })
        for (index, proposal) in web.proposals.enumerated() {
            let before = proposal.before.map { NativeAgentNote($0.document) }
            let afterPath: String
            if let first = proposal.before.first { afterPath = proposal.afterPath ?? first.path }
            else if let receipt = web.receipts.first(where: { $0.proposalID == proposal.id }), let after = receipt.after.first { afterPath = after.path }
            else {
                guard let args = try NativeJSON.object(with: proposal.call.arguments) as? [String: Any], let parts = args["typePath"] as? [String], parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") }) else { throw MacWebAgentRun.problem("A new-note proposal has no exact creation folder.") }
                let destination = parts.joined(separator: "/"); try NativePropertyDefinition.validateOwner(destination)
                let document = NoteDocument(path: "Note.md", content: proposal.after, modified: .distantPast)
                let filename = NativeNoteRename.suggestedFilename(document.title, path: "Note.md"), prefix = destination.isEmpty ? "" : destination + "/"
                var chosen = prefix + filename, suffix = 2
                while occupied.contains(chosen.lowercased()) { chosen = prefix + (filename as NSString).deletingPathExtension + " \(suffix).md"; suffix += 1 }
                afterPath = chosen; occupied.insert(chosen.lowercased())
                notices.append("New-note proposal “" + proposal.label + "” will use " + chosen + "; the web journal did not freeze a filename.")
            }
            let primary = NativeAgentNote(.init(path: afterPath, content: proposal.after, modified: .distantPast))
            var companions: [NativeAgentCompanion] = []
            for old in proposal.before.dropFirst() {
                guard let after = proposal.relatedAfter.first(where: { $0.id == old.id }) else { throw MacWebAgentRun.problem("A linked-note proposal is incomplete.") }
                companions.append(.init(before: .init(old.document), after: .init(after.document)))
            }
            let call = NativeAgentCall(id: "web-proposal-" + proposalIDs[index].uuidString.lowercased(), name: proposal.call.name, arguments: String(decoding: proposal.call.arguments, as: UTF8.self))
            var native = NativeAgentProposal(id: proposalIDs[index], call: call, before: before.first, after: primary)
            native.companions = companions.isEmpty ? nil : companions
            native.status = proposal.status == "applied" ? "applied" : proposal.status == "rejected" || proposal.status == "conflict" ? "rejected" : "pending"
            if !before.isEmpty {
                let old = Dictionary(uniqueKeysWithValues: before.map { ($0.path, Data($0.content.utf8)) })
                let next = Dictionary(uniqueKeysWithValues: native.afters.map { ($0.path, Data($0.content.utf8)) })
                let changes = Set(old.keys).union(next.keys).sorted().compactMap { path -> VaultFileChange? in old[path] == next[path] ? nil : .init(path: path, before: old[path], after: next[path]) }
                if !changes.isEmpty { native.organization = .init(changes: changes, dependencies: [], mappings: Dictionary(uniqueKeysWithValues: zip(before, native.afters).filter { $0.path != $1.path }.map { ($0.path, $1.path) }), bindings: [], created: [:]) }
            }
            run.proposals.append(native)
        }
        for (index, receipt) in web.receipts.enumerated() {
            guard let proposalIndex = web.proposals.firstIndex(where: { $0.id == receipt.proposalID }) else { throw MacWebAgentRun.problem("A receipt has no corresponding proposal.") }
            run.receipts.append(.init(id: receiptIDs[index], date: receipt.date, proposalIDs: [proposalIDs[proposalIndex]], before: receipt.before.map { .init($0.document) }, after: receipt.after.map { .init($0.document) }, undoneAt: receipt.undoneAt))
        }
        run.event("Imported complete web journal with reviewed current native settings and connection. Original provider configuration and read coverage were not persisted by the web run; no historical read grants were inferred.")
        if web.status == "running" { notices.append("The source was marked running. Stop it in the original client before import; usage from an unreported in-flight request is unknown and cannot be reconstructed.") }
        notices.append("Current instructions, workflow, limits and connection will be frozen for continuation. Import sends no provider request and applies no note proposal.")
        if !run.canResume { notices.append("The preserved cumulative usage reaches these native limits. Imported history and review remain available; continuation cannot send another request within this budget.") }
        let transcript = run.messages
        let compaction: MacAgentCompactionPlan?
        let activeBytes = try MacAgentCompaction.encoder.encode(run.messages).count
        if run.messages.count > 240 || activeBytes > 2_000_000 {
            let inputLimit = contextCapacity.map { $0 - run.budget.maxOutputTokens }
            let plan = try await MacAgentCompactionPlan.prepare(run, inputLimit: inputLimit); compaction = plan; run = plan.applying(to: run)
            notices.append("The complete active transcript needs \(plan.state.ranges.count) summary fragments before continuation. Import sends none. Resume will use the selected provider, charge each summary to these saved limits, and retain its progress across Stop. Exact messages and image inputs remain archived.")
        } else { compaction = nil }
        let encoded = try compaction.map { try MacAgentCompaction.encode(run, state: $0.state, archives: [$0.state.archive], hashes: $0.retired) } ?? NativeAgentJournal.encode(run)
        var object = try NativeJSON.object(with: encoded) as! [String: Any]
        object["macProvider"] = try NativeJSON.object(with: JSONEncoder().encode(binding))
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let storage = try agentJournalChanges(bytes, previous: nil, id: id)
        let record = storage.record
        var dependencies: [VaultFileChange] = [
            .init(path: ".zerus/ai/settings.json", before: settings.bytes, after: settings.bytes),
            .init(path: ".zerus/ai/instructions.md", before: guidance.instructionsBytes, after: guidance.instructionsBytes),
            .init(path: ".zerus/ai/memory.md", before: guidance.memoryBytes, after: guidance.memoryBytes)]
        if let workflow, NativeAgentWorkflow.customPath(workflow.id) {
            let document = try agentWorkflowDocument(workflow.id)
            guard document.workflow == workflow else { throw MacWebAgentRun.problem("The selected workflow changed during preparation.") }
            dependencies.append(.init(path: workflow.id, before: document.bytes, after: document.bytes))
        }
        let grants = run.readIDs.map { nativeID -> String in
            let note = notes.first { NativeAgentNote.identity($0) == nativeID } ?? snapshots.last { NativeAgentNote.identity($0.document) == nativeID }?.document
            return (run.writeIDs.contains(nativeID) ? "Read and write: " : "Read only: ") + (note.map { $0.title + " — " + $0.path } ?? nativeID) + (notes.contains { NativeAgentNote.identity($0) == nativeID } ? "" : " (currently unavailable)")
        }
        return .init(root: root, source: source, children: children, sourceInventory: sourceInventory, record: record, attachments: history.attachments, conversation: chat, dependencies: dependencies, grants: grants, notices: notices, transcript: transcript, compaction: compaction, storage: storage, importIndex: importIndex)
    }

    func importMacWebAgentMigration(_ review: MacWebAgentMigrationReview, owner: String) throws -> NativeAgentRecord {
        guard review.root == root, review.record.run.owner == owner, let provenance = review.record.run.webMigration,
              review.record.run.chatID == review.conversation.conversation.id else { throw MacWebAgentRun.problem("The reviewed vault or owner changed.") }
        try validateMacWebAgentImportIndex(review.importIndex)
        let chat = try conversationSnapshot(review.record.run.chatID)
        guard chat.descriptor == review.conversation.descriptor, chat.records == review.conversation.records,
              chat.conversation.owner.id == owner, chat.conversation.archivedAt == nil, chat.conversation.deletedAt == nil else { throw MacWebAgentRun.problem("The conversation changed after review. Reopen it before importing.") }
        var changes = review.dependencies + chat.records.map { VaultFileChange(path: $0.key, before: $0.value, after: $0.value) } + (review.compaction?.changes ?? []) + [review.importIndex.change] + review.importIndex.dependencies
        changes += [.init(path: ".zerus/chats/" + chat.conversation.id + "/conversation.json", before: chat.descriptor, after: chat.descriptor),
                    .init(path: ".zerus/chat-tombstones/" + chat.conversation.id + ".json", before: nil, after: nil),
                    .init(path: review.source.path, before: review.source.bytes, after: review.source.bytes),
                    .init(path: provenance.archivePath, before: nil, after: review.source.bytes)] + review.storage.changes
        for child in review.children {
            guard let destination = provenance.childSources?.first(where: { $0.sourcePath == child.path }), destination.digest == child.digest else { throw MacWebAgentRun.problem("A reviewed worker source changed.") }
            changes += [.init(path: child.path, before: child.bytes, after: child.bytes), .init(path: destination.archivePath, before: nil, after: child.bytes)]
        }
        let expected = Set(chat.records.keys), origin = root, chatID = chat.conversation.id
        let sourceFolder = try url(for: ".zerus/ai/runs/" + chatID)
        try applyTransaction(changes, historySource: "ai-web-import") {
            guard try Self.conversationEventPaths(root: origin, id: chatID) == expected else { throw MacWebAgentRun.problem("Conversation events changed during import.") }
            guard try Self.webSourceInventory(sourceFolder) == review.sourceInventory else { throw MacWebAgentRun.problem("The source journal inventory changed. Review the parent and workers again.") }
        }
        return review.record
    }
    private nonisolated static func webSourceInventory(_ folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { ($0 as NSString).pathExtension.lowercased() == "json" })
    }
}
