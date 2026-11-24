import Foundation

/// Child conversations live in the parent's compare-and-swap journal. Only one
/// child request is in flight, using the parent's durable request reservation.
struct MacAgentAnalysisState: Codable, Sendable {
    var version = 1
    let callID: String
    var children: [NativeAgentRun]
    var startedAtParentSeconds: Double? = nil
    var inFlight: NativeAgentRequestReservation? = nil
    var next: Int? { children.firstIndex { $0.status == "running" } }
    static let reads: Set<String> = ["note_get", "note_list", "search", "note_schema"]
    static func prefix(_ value: String, bytes: Int) -> String {
        var data = Data(value.utf8.prefix(max(0, bytes)))
        while !data.isEmpty { if let text = String(data: data, encoding: .utf8) { return text }; data.removeLast() }
        return ""
    }
    func resultContent(maxAnswerBytes: Int) throws -> String {
        let answers = children.map { child -> String in
            let content = child.messages.last(where: { $0.role == "assistant" && ($0.toolCalls?.isEmpty != false) })?.content ?? "No final answer."
            let reason = child.messages.last(where: { $0.role == "user" && $0.content.hasPrefix("Runtime:") })?.content ?? ""
            let answer = child.status == "complete" ? content : "Analysis interrupted: " + reason + "\n" + content
            return answer.utf8.count > maxAnswerBytes ? Self.prefix(answer, bytes: maxAnswerBytes) + "\n[Analysis truncated to fit the parent's synthesis context.]" : answer
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: ["ok": true, "analyses": answers, "trusted": false, "readOnly": true], options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    static func continuationIDs(_ record: NativeAgentRecord, includingFinished: Bool) throws -> [UUID] {
        let object = try NativeJSON.object(with: record.metadataBytes) as! [String: Any]
        var states = (object["macAnalysis"] as? [String: Any]).flatMap { state in
            includingFinished || record.run.pendingCalls.contains(where: { $0.name == "analyze_notes" && $0.id == state["callID"] as? String }) ? [state] : nil
        } ?? []
        if includingFinished { states += object["macAnalysisHistory"] as? [[String: Any]] ?? [] }
        return states.flatMap { ($0["children"] as? [[String: Any]] ?? []).compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) } }
    }
    static func read(_ record: NativeAgentRecord, requirePending: Bool = true) throws -> Self? {
        let object = try NativeJSON.object(with: record.metadataBytes) as! [String: Any]
        guard let raw = object["macAnalysis"] else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(Self.self, from: JSONSerialization.data(withJSONObject: raw))
        guard state.version == 1, state.children.count == 2, Set(state.children.map(\.id)).count == 2,
              record.run.preferences?.workers == true,
              !requirePending || record.run.pendingCalls.contains(where: { $0.id == state.callID && $0.name == "analyze_notes" }) else { throw VaultFailure(message: "This saved analysis state is unsupported. Its journal is kept.") }
        if let start = state.startedAtParentSeconds {
            guard start.isFinite, start >= 0, start <= record.run.activeSeconds else { throw VaultFailure(message: "This saved analysis clock is unsupported. Its journal is kept.") }
        }
        if let request = state.inFlight {
            guard let index = state.next, request.input >= 0, request.input <= state.children[index].budget.maxInputTokens,
                  (1...state.children[index].budget.maxOutputTokens).contains(request.output) else { throw VaultFailure(message: "This saved analysis allowance is unsupported.") }
            if let parent = record.run.requestReservation {
                guard parent.id == request.id, parent.input == request.input, parent.output == request.output else { throw VaultFailure(message: "The analysis request allowance does not match its parent.") }
            }
        } else if record.run.requestReservation != nil { throw VaultFailure(message: "This analysis has no matching request allowance.") }
        for child in state.children {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            _ = try NativeAgentJournal.decode(encoder.encode(child), id: child.id)
            guard child.mode == .ask, child.owner == record.run.owner, child.chatID == record.run.chatID,
                  child.scopeKind == .selected, Set(child.readIDs).isSubset(of: Set(record.run.readIDs)),
                  child.writeIDs.isEmpty, child.createFolders.isEmpty, child.attachments?.isEmpty != false,
                  child.requestReservation == nil, child.preferences?.workers == false,
                  ["running", "complete", "partial"].contains(child.status), child.question == nil else {
                throw VaultFailure(message: "This saved analysis has unsupported permissions. Its journal is kept.")
            }
        }
        return state
    }
}

extension VaultFiles {
    private func macAnalysisStore(_ run: NativeAgentRun, state: MacAgentAnalysisState?, previous: Data) throws -> NativeAgentRecord {
        var original = try MacAgentPayloads.expanded(NativeJSON.object(with: previous) as! [String: Any], id: run.id, read: { try self.agentPayload($0) })
        let oldState = original.removeValue(forKey: "macAnalysis")
        var history = original.removeValue(forKey: "macAnalysisHistory") as? [[String: Any]] ?? []
        let base = try JSONSerialization.data(withJSONObject: original)
        var object = try NativeJSON.object(with: agentEncode(run, previous: base)) as! [String: Any]
        if var state {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            if state.inFlight == nil {
                let activeIndex = state.next
                for index in state.children.indices where try encoder.encode(state.children[index]).count > 1_000_000 {
                    var child = state.children[index]
                    if activeIndex == index { child.activeSeconds = state.startedAtParentSeconds.map { max(0, run.activeSeconds - $0) } ?? child.activeSeconds }
                    child.messages = [.init(role: "user", content: MacAgentAnalysisState.prefix(child.objective, bytes: 8000)), .init(role: "assistant", content: "Analysis interrupted: its transcript reached the saved storage limit; no further worker call was executed.")]
                    child.reads = []; child.status = "partial"; state.children[index] = child
                    if activeIndex == index { state.startedAtParentSeconds = nil }
                }
            }
            object["macAnalysis"] = try NativeJSON.object(with: encoder.encode(state))
        } else {
            if let oldState { history.append(oldState as? [String: Any] ?? ["unsupportedState": oldState]) }
        }
        // Keep recent transcripts within a bounded journal; older workers retain
        // their identities, usage and an explicitly marked conclusion summary.
        if try JSONSerialization.data(withJSONObject: history).count > 1_000_000 {
            history = history.map { entry in
                var next = entry
                next["transcriptCompacted"] = true
                next["children"] = (entry["children"] as? [[String: Any]] ?? []).map { child -> [String: Any] in
                    var summary = child.filter { ["id", "steps", "status", "inputTokens", "outputTokens", "activeSeconds"].contains($0.key) }
                    summary["objective"] = MacAgentAnalysisState.prefix(child["objective"] as? String ?? "", bytes: 512)
                    let messages = child["messages"] as? [[String: Any]] ?? []
                    summary["conclusion"] = MacAgentAnalysisState.prefix(messages.last(where: { $0["role"] as? String == "assistant" })?["content"] as? String ?? child["conclusion"] as? String ?? "", bytes: 1024)
                    return summary
                }
                return next
            }
        }
        if !history.isEmpty { object["macAnalysisHistory"] = history }
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let storage = try agentJournalChanges(bytes, previous: previous, id: run.id)
        let result = storage.record
        _ = try MacAgentAnalysisState.read(result)
        try applyTransaction(storage.changes, historySource: "ai")
        return result
    }
    func beginMacAnalysis(_ record: NativeAgentRecord, owner: String, call: NativeAgentCall) throws -> NativeAgentRecord {
        var run = try agentChecked(record, owner: owner)
        guard call.name == "analyze_notes", run.pendingCalls.contains(call) else { throw VaultFailure(message: "This analysis call is not pending.") }
        let existing: MacAgentAnalysisState?
        do { existing = try MacAgentAnalysisState.read(record, requirePending: false) }
        catch {
            run.messages.append(.init(role: "tool", content: "{\"ok\":false,\"error\":\"The prior analysis state could not be read. It was archived without executing another worker; start a new run if its results are needed.\"}", toolCallId: call.id))
            run.event("Archived unreadable analysis metadata; no worker call executed.")
            return try macAnalysisStore(run, state: nil, previous: record.bytes)
        }
        if var state = existing {
            if !run.pendingCalls.contains(where: { $0.id == state.callID && $0.name == "analyze_notes" }) {
                run.event("Archived analysis progress already declined by another client.")
                let retired = try macAnalysisStore(run, state: nil, previous: record.bytes)
                return try beginMacAnalysis(retired, owner: owner, call: call)
            }
            guard state.callID == call.id else { throw VaultFailure(message: "Finish the pending independent analysis first.") }
            if let allowance = state.inFlight, let index = state.next {
                guard run.requestReservation == nil else { throw VaultFailure(message: "Settle the interrupted parent request before resuming its analysis.") }
                state.children[index].steps += 1; state.children[index].inputTokens += allowance.input; state.children[index].outputTokens += allowance.output
                state.children[index].activeSeconds = state.startedAtParentSeconds.map { max(0, run.activeSeconds - $0) } ?? 0
                state.inFlight = nil
                run.event("The interrupted worker's reserved allowance is also kept in its own analysis budget.")
                return try macAnalysisStore(run, state: state, previous: record.bytes)
            }
            return try macAnalysisStore(run, state: state, previous: record.bytes)
        }
        let children: [NativeAgentRun]
        do {
            guard run.preferences?.workers == true else { throw VaultFailure(message: "Enable independent analysis workers in Run defaults, then start a new run.") }
            guard record.bytes.count < 4_000_000 else { throw VaultFailure(message: "This run's journal has too little room for independent analysis. Start a new run with the relevant context.") }
            guard run.withinBudget, run.question == nil, run.requestReservation == nil else { throw VaultFailure(message: "This run cannot start independent analysis within its saved limits.") }
            guard let args = try NativeJSON.object(with: Data(call.arguments.utf8)) as? [String: Any], Set(args.keys) == ["question", "selectors"],
                  let question = args["question"] as? String, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.utf16.count <= 8000,
                  let selectors = args["selectors"] as? [String], (1...12).contains(selectors.count), selectors.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 1000 }) else { throw VaultFailure(message: "Ask one analysis question within 8,000 characters about one to twelve exact note selectors.") }
            let notes = try scan().notes
            let selected = try selectors.map { try agentResolve($0, run: run, notes: notes) }
            let ids = Array(Set(selected.map(NativeAgentNote.identity))).sorted()
            let allowance = (run.budget.maxTotalTokens - run.inputTokens - run.outputTokens - run.budget.maxInputTokens - 1000) / 2
            guard allowance >= 8000, run.budget.maxSteps - run.steps >= 3, Double(run.budget.maxMinutes * 60) - run.activeSeconds > 30 else { throw VaultFailure(message: "Insufficient remaining token or step budget for two independent analyses and a final answer. Keep the parent's input allowance, one output step and synthesis time available.") }
            children = ["Find supporting evidence and useful connections.", "Independently check contradictions, missing evidence and coverage."].map { angle in
                var child = NativeAgentRun(id: UUID(), chatID: run.chatID, owner: owner, objective: question + "\n" + angle, mode: .ask, scopeLabel: "Independent analysis of \(ids.count) permitted notes", scopeKind: .selected, readFolder: nil, readIDs: ids, writeIDs: [], createFolders: [])
                var limits = run.budget; limits.maxSteps = min(8, limits.maxSteps); limits.maxMinutes = min(3, limits.maxMinutes); limits.maxOutputTokens = min(3000, limits.maxOutputTokens); limits.maxTotalTokens = allowance
                child.limits = limits; child.guidance = .init(); child.currentReadID = ids.first
                var preferences = NativeAgentPreferences(); preferences.mode = .ask; preferences.textFallback = run.preferences?.textFallback == true
                child.preferences = preferences
                child.messages = [.init(role: "user", content: child.objective)]
                return child
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            let bytes = try JSONSerialization.data(withJSONObject: ["ok": false, "error": error.localizedDescription])
            run.messages.append(.init(role: "tool", content: String(decoding: bytes, as: UTF8.self), toolCallId: call.id)); run.event("Independent analysis refused.")
            return try agentStore(run, previous: record.bytes)
        }
        run.event("Started two independent read-only analyses; their requests share this run's limits.")
        return try macAnalysisStore(run, state: .init(callID: call.id, children: children), previous: record.bytes)
    }
    func readMacAnalysis(_ record: NativeAgentRecord, owner: String, index: Int, call: NativeAgentCall) throws -> NativeAgentRecord {
        let run = try agentChecked(record, owner: owner)
        var state = try requireMacAnalysis(record, index: index)
        var child = state.children[index]
        guard child.pendingCalls.contains(call), run.requestReservation == nil else { throw VaultFailure(message: "This analysis read is not pending.") }
        let result: [String: Any]
        do {
            guard MacAgentAnalysisState.reads.contains(call.name), let args = try NativeJSON.object(with: Data(call.arguments.utf8)) as? [String: Any] else { throw VaultFailure(message: "Independent analysis can only use its declared note read tools. No mutation or nested worker was executed.") }
            result = try agentReadTool(call.name, arguments: args, run: &child, notes: agentAvailable(run, notes: scan().notes))
        } catch is CancellationError { throw CancellationError() }
        catch { result = ["ok": false, "error": error.localizedDescription] }
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
        child.messages.append(.init(role: "tool", content: bytes.count <= 400_000 ? String(decoding: bytes, as: UTF8.self) : "{\"ok\":false,\"error\":\"Choose a smaller read.\"}", toolCallId: call.id))
        state.children[index] = child
        return try macAnalysisStore(run, state: state, previous: record.bytes)
    }
    private func requireMacAnalysis(_ record: NativeAgentRecord, index: Int) throws -> MacAgentAnalysisState {
        guard let state = try MacAgentAnalysisState.read(record), state.next == index else { throw VaultFailure(message: "This independent analysis step is no longer active.") }
        return state
    }
    func reserveMacAnalysis(_ record: NativeAgentRecord, owner: String, index: Int, input: Int, output: Int) throws -> NativeAgentRecord {
        var run = try agentChecked(record, owner: owner)
        var state = try requireMacAnalysis(record, index: index)
        let child = state.children[index]
        guard run.canRequest, run.steps < run.budget.maxSteps - 1, child.canRequest, state.inFlight == nil, child.pendingCalls.isEmpty,
              Double(run.budget.maxMinutes * 60) - run.activeSeconds > 30,
              state.startedAtParentSeconds.map({ run.activeSeconds - $0 < Double(child.budget.maxMinutes * 60) }) ?? true,
              input >= 0, input <= min(run.budget.maxInputTokens, child.budget.maxInputTokens),
              (1...min(run.budget.maxOutputTokens, child.budget.maxOutputTokens)).contains(output),
              input + output + run.budget.maxInputTokens + 1000 <= run.budget.maxTotalTokens - run.inputTokens - run.outputTokens,
              input + output <= child.budget.maxTotalTokens - child.inputTokens - child.outputTokens else { throw VaultFailure(message: "This independent analysis cannot reserve another request within the saved parent and worker limits.") }
        run.requestReservation = .init(id: UUID(), input: input, output: output); run.steps += 1
        state.inFlight = run.requestReservation
        if state.startedAtParentSeconds == nil { state.startedAtParentSeconds = run.activeSeconds }
        run.event("Requested independent analysis \(index + 1), reserving \(input) input and \(output) output tokens.")
        return try macAnalysisStore(run, state: state, previous: record.bytes)
    }
    func replyMacAnalysis(_ record: NativeAgentRecord, owner: String, index: Int, reply: MacAgentCompletion, source: String?, refusal: String?, input: Int, output: Int, seconds: Double) throws -> NativeAgentRecord {
        var run = try agentChecked(record, owner: owner)
        var state = try requireMacAnalysis(record, index: index), child = state.children[index]
        guard run.requestReservation != nil, child.pendingCalls.isEmpty, seconds.isFinite, seconds >= 0, (0...1_000_000).contains(input), (0...1_000_000).contains(output),
              !reply.calls.contains(where: { call in child.messages.flatMap { $0.toolCalls ?? [] }.contains(where: { $0.id == call.id }) }) else { throw VaultFailure(message: "This analysis reply has unsupported usage or call identity.") }
        child.messages.append(.init(role: "assistant", content: reply.content, toolCalls: refusal != nil || reply.calls.isEmpty ? nil : reply.calls, textToolSource: refusal == nil ? source : nil))
        child.steps += 1; child.inputTokens += input; child.outputTokens += output
        child.activeSeconds = state.startedAtParentSeconds.map { max(0, run.activeSeconds - $0 + seconds) } ?? seconds
        child.status = refusal != nil ? "partial" : reply.calls.isEmpty ? "complete" : "running"
        if let refusal { child.messages.append(.init(role: "user", content: "Runtime: " + refusal)) }
        run.requestReservation = nil; run.inputTokens += input; run.outputTokens += output
        state.inFlight = nil
        state.children[index] = child
        if child.status != "running" { state.startedAtParentSeconds = nil }
        return try macAnalysisStore(run, state: state, previous: record.bytes)
    }
    func finishMacAnalysisChild(_ record: NativeAgentRecord, owner: String, index: Int, reason: String) throws -> NativeAgentRecord {
        var run = try agentChecked(record, owner: owner)
        var state = try requireMacAnalysis(record, index: index)
        if let request = state.inFlight {
            if run.requestReservation != nil { run.settleInterruptedRequest() }
            state.children[index].steps += 1; state.children[index].inputTokens += request.input; state.children[index].outputTokens += request.output
            state.inFlight = nil
        }
        state.children[index].activeSeconds = state.startedAtParentSeconds.map { max(0, run.activeSeconds - $0) } ?? 0
        state.children[index].status = "partial"; state.children[index].messages.append(.init(role: "user", content: "Runtime: Analysis interrupted: " + reason))
        state.startedAtParentSeconds = nil
        return try macAnalysisStore(run, state: state, previous: record.bytes)
    }
    func finishMacAnalysis(_ record: NativeAgentRecord, owner: String, maxAnswerBytes: Int) throws -> NativeAgentRecord {
        var run = try agentChecked(record, owner: owner)
        guard let state = try MacAgentAnalysisState.read(record), state.next == nil, run.requestReservation == nil else { throw VaultFailure(message: "The independent analyses are not finished.") }
        guard (0...16_000).contains(maxAnswerBytes) else { throw VaultFailure(message: "Unsupported analysis summary allowance.") }
        run.messages.append(.init(role: "tool", content: try state.resultContent(maxAnswerBytes: maxAnswerBytes), toolCallId: state.callID))
        run.event("Independent read-only analyses finished. Their usage is included in this run.")
        return try macAnalysisStore(run, state: nil, previous: record.bytes)
    }
}
