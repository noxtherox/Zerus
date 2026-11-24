import XCTest
import Combine
import AppKit
@testable import Zerus_Native

@MainActor final class MacAgentControllerTests: XCTestCase {
    func testLargeRootMetadataKeepsPermissionsProviderAndExactFieldsAcrossToolsCompactionAndResume() async throws {
        try await fixture { root, workspace, controller, store, provider, route in
            let io = try XCTUnwrap(workspace.io), expectedBinding = try provider.binding
            let archivedChild = UUID(), analysisConclusion = String(repeating: "Saved analysis evidence. ", count: 2000)
            let preferences = try await controller.workspace.preferences(); var enabled = preferences.value; enabled.workers = true
            _ = try await controller.workspace.savePreferences(enabled, expected: preferences)
            var record = try await controller.workspace.start(objective: "Check Beta with the exact saved permissions", mode: .ask, scope: .init(paths: ["Beta.md"]), chatID: "large-root-metadata")
            record = try await controller.workspace.bindProvider(record, binding: provider.binding)
            let grants = record.run.readIDs + (0..<30_000).map { "retained-\($0)-" + String(repeating: "x", count: 50) }
            let foreign = "\u{feff}" + String(repeating: "m", count: 6_500_000) + "末"
            let providerExtra = String(repeating: "future-provider-field", count: 2000)
            var object = try XCTUnwrap(NativeJSON.object(with: record.bytes) as? [String: Any])
            object["readIDs"] = grants; object["foreignMetadata"] = foreign
            object["macAnalysisHistory"] = [["children": [["id": archivedChild.uuidString]], "conclusion": analysisConclusion]]
            var binding = try XCTUnwrap(object["macProvider"] as? [String: Any]); binding["futureField"] = providerExtra; object["macProvider"] = binding
            let expanded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            XCTAssertGreaterThan(expanded.count, 8_000_000, "The fixture must exercise the old manifest limit")
            let storage: NativeAgentStoragePlan
            do { storage = try await io.agentJournalChanges(expanded, previous: record.bytes, id: record.id) }
            catch { XCTFail("Saving exact root metadata failed: \(String(reflecting: error))"); return }
            try await io.applyTransaction(storage.changes); record = storage.record
            let header = try XCTUnwrap(NativeJSON.object(with: record.bytes) as? [String: Any])
            XCTAssertEqual(NativeHistory.integer(header["version"]), 8)
            XCTAssertEqual(NativeHistory.integer(header["macRunVersion"]), record.run.version)
            XCTAssertLessThan(record.bytes.count, 8_000_000)
            XCTAssertEqual(record.run.readIDs, grants); XCTAssertTrue(record.run.writeIDs.isEmpty)
            XCTAssertEqual(try MacAgentProviderBinding.read(record), expectedBinding)
            XCTAssertTrue(try MacAgentAnalysisState.continuationIDs(record, includingFinished: true).contains(archivedChild))
            let groups = try XCTUnwrap(header["macFieldGroups"] as? [[String: Any]])
            let references = try groups.map { reference -> (String, Data) in
                let digest = try XCTUnwrap(reference["digest"] as? String)
                let path = MacAgentPayloads.path(record.id, digest: digest)
                return (path, try Data(contentsOf: root.appendingPathComponent(path)))
            }
            let pair = try XCTUnwrap(references.first { (try? NativeJSON.object(with: $0.1) as? [String: Any])?["foreignMetadata"] != nil })
            let payloadPath = pair.0, payloadFile = root.appendingPathComponent(pair.0), payload = pair.1
            XCTAssertEqual((try NativeJSON.object(with: payload) as? [String: Any])?["foreignMetadata"] as? String, foreign)
            let directory = payloadFile.deletingLastPathComponent(), originals = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
            let reopened = try await controller.workspace.records(); record = try XCTUnwrap(reopened.records.first { $0.id == record.id })
            record = try await controller.workspace.pause(record, reason: "Reopen exact fields")
            record = try await controller.workspace.resume(record)
            XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)), originals, "Unchanged large fields must reuse their immutable payloads")
            XCTAssertEqual(try MacAgentProviderBinding.read(record), expectedBinding)
            let calls = [NativeAgentCall(id: "metadata-beta", name: "note_get", arguments: #"{"selector":"beta"}"#), NativeAgentCall(id: "metadata-denied", name: "note_get", arguments: #"{"selector":"alpha"}"#)]
            record = try await controller.workspace.response(record, content: "Read within the saved boundary", calls: calls, input: 10, output: 5, seconds: 0.1)
            for call in calls { record = try await controller.workspace.tool(record, call: call) }
            let results = record.run.messages.filter { $0.role == "tool" }
            let allowed = try XCTUnwrap(NativeJSON.object(with: Data(XCTUnwrap(results.first { $0.toolCallId == "metadata-beta" }).content.utf8)) as? [String: Any])
            let denied = try XCTUnwrap(NativeJSON.object(with: Data(XCTUnwrap(results.first { $0.toolCallId == "metadata-denied" }).content.utf8)) as? [String: Any])
            XCTAssertEqual(allowed["id"] as? String, "beta"); XCTAssertEqual(denied["ok"] as? Bool, false)
            XCTAssertTrue((denied["error"] as? String)?.contains("outside") == true)
            XCTAssertNil(ChatHTTPFixture.captured(route))
            var next = record.run; next.event("Prepared while preserving exact metadata")
            let nextBytes = try await io.agentEncode(next, previous: record.bytes)
            let pending = try await io.agentJournalChanges(nextBytes, previous: record.bytes, id: record.id)
            let corrupt = payload + Data(" ".utf8); try corrupt.write(to: payloadFile)
            do { try await io.applyTransaction(pending.changes); XCTFail("A changed field payload must invalidate the transaction") }
            catch { XCTAssertTrue(error.localizedDescription.contains("changed"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id))), record.bytes)
            XCTAssertEqual(try Data(contentsOf: payloadFile), corrupt)
            let broken = try await controller.workspace.records()
            XCTAssertTrue(broken.unreadable.contains(NativeAgentJournal.path(record.id)))
            try payload.write(to: payloadFile)
            let oversized = try FileHandle(forWritingTo: payloadFile)
            try oversized.truncate(atOffset: UInt64(MacAgentPayloads.maximum + 1)); try oversized.close()
            do { _ = try await io.agentPayload(payloadPath); XCTFail("An oversized synced payload must be refused before decoding") }
            catch { XCTAssertTrue(error.localizedDescription.contains("bounded storage allowance"), error.localizedDescription) }
            try payload.write(to: payloadFile)
            var conflicting = try XCTUnwrap(NativeJSON.object(with: record.bytes) as? [String: Any])
            let invalid = try JSONSerialization.data(withJSONObject: ["owner": "Other owner"])
            let invalidPath = MacAgentPayloads.path(record.id, digest: NativeHistory.hash(invalid))
            try invalid.write(to: root.appendingPathComponent(invalidPath))
            var conflictingGroups = try XCTUnwrap(conflicting["macFieldGroups"] as? [[String: Any]])
            conflictingGroups.append(["digest": NativeHistory.hash(invalid), "bytes": invalid.count]); conflicting["macFieldGroups"] = conflictingGroups
            do { _ = try await io.agentDecode(JSONSerialization.data(withJSONObject: conflicting), id: record.id); XCTFail("Payloads cannot replace manifest identities") }
            catch { XCTAssertTrue(error.localizedDescription.contains("conflicts with its manifest"), error.localizedDescription) }
            let analysis = NativeAgentCall(id: "metadata-analysis", name: "analyze_notes", arguments: #"{"question":"Check Beta","selectors":["beta"]}"#)
            record = try await controller.workspace.response(record, content: "Keep analysis checkpoints", calls: [analysis], input: 1, output: 1, seconds: 0)
            record = try await controller.workspace.beginAnalysis(record, call: analysis)
            let children = try XCTUnwrap(MacAgentAnalysisState.read(record)).children
            XCTAssertEqual(children.count, 2); XCTAssertTrue(children.allSatisfy { $0.readIDs == ["beta"] && $0.writeIDs.isEmpty })
            for index in children.indices { record = try await controller.workspace.endAnalysisChild(record, index: index, reason: "Explicit checkpoint interruption") }
            record = try await controller.workspace.endAnalysis(record, maxAnswerBytes: 1000)
            XCTAssertNil(try MacAgentAnalysisState.read(record))
            record = try await controller.workspace.beginCompaction(record)
            XCTAssertNotNil(try MacAgentCompaction.read(record))
            XCTAssertEqual(try MacAgentProviderBinding.read(record), expectedBinding)
            ChatHTTPFixture.register(try self.textReply("Beta was read; Alpha remains outside the chosen scope.", next: self.answer("Continued with exact metadata.")), path: route)
            try await self.finished(controller, timeout: 60) { controller.resume(record, store: store, provider: provider) }
            XCTAssertNil(controller.issue, controller.issue ?? "")
            let complete = try XCTUnwrap(controller.current)
            XCTAssertEqual(complete.run.status, "complete"); XCTAssertEqual(complete.run.readIDs, grants)
            XCTAssertEqual(try MacAgentProviderBinding.read(complete), expectedBinding)
            XCTAssertNil(try MacAgentCompaction.read(complete)); XCTAssertFalse(try MacAgentCompaction.archives(complete).isEmpty)
            let finalData = try await io.agentEncode(complete.run, previous: complete.bytes)
            let final = try XCTUnwrap(NativeJSON.object(with: finalData) as? [String: Any])
            XCTAssertEqual(final["foreignMetadata"] as? String, foreign)
            XCTAssertEqual((final["macProvider"] as? [String: Any])?["futureField"] as? String, providerExtra)
            XCTAssertEqual((final["macAnalysisHistory"] as? [[String: Any]])?.first?["conclusion"] as? String, analysisConclusion)
            XCTAssertTrue(try MacAgentAnalysisState.continuationIDs(complete, includingFinished: true).contains(archivedChild))
            XCTAssertEqual(try Data(contentsOf: payloadFile), payload)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Alpha.md")), Data(self.alpha.utf8))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Beta.md")), Data(self.beta.utf8))
        }
    }

    func testLargeCallReplyKeepsAllArgumentsUsageAndResultsThroughCompaction() async throws {
        try await fixture { root, _, controller, store, provider, route in
            let settings = try await controller.workspace.limits(); var limits = settings.limits
            limits.maxSteps = 100; limits.maxMinutes = 30; limits.maxInputTokens = 48_000; limits.maxOutputTokens = 1024; limits.maxTotalTokens = 1_000_000
            _ = try await controller.workspace.saveLimits(limits, expected: settings)
            var record = try await controller.workspace.start(objective: "Keep the exact response and refuse unsupported searches", mode: .ask, scope: .init(paths: ["Beta.md"]), chatID: "large-call-storage")
            record = try await controller.workspace.bindProvider(record, binding: provider.binding)
            let arguments = String(decoding: try JSONSerialization.data(withJSONObject: ["query": String(repeating: "\\", count: 180_000)]), as: UTF8.self)
            let calls = (0..<12).map { NativeAgentCall(id: "large-call-\($0)", name: "search", arguments: arguments) }
            XCTAssertLessThan(arguments.utf8.count, 400_000)
            do { record = try await controller.workspace.response(record, content: "Keep every refused call.", calls: calls, input: 123, output: 45, seconds: 0.25) }
            catch { XCTFail("Storing a bounded multi-call reply failed: \(String(reflecting: error))"); return }
            XCTAssertEqual(record.run.steps, 1); XCTAssertEqual(record.run.inputTokens, 123); XCTAssertEqual(record.run.outputTokens, 45)
            XCTAssertLessThan(record.bytes.count, 8_000_000); XCTAssertEqual(record.run.version, 6)
            let saved = try await controller.workspace.records()
            record = try XCTUnwrap(saved.records.first { $0.id == record.id })
            XCTAssertEqual(record.run.messages.last?.toolCalls, calls)
            let directory = root.appendingPathComponent(".zerus/native-ai/payloads/" + record.id.uuidString.lowercased())
            let payload = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            let exact = try Data(contentsOf: payload)
            try (exact + Data(" ".utf8)).write(to: payload)
            let corrupt = try await controller.workspace.records()
            XCTAssertTrue(corrupt.unreadable.contains(NativeAgentJournal.path(record.id)))
            XCTAssertNil(ChatHTTPFixture.captured(route))
            try exact.write(to: payload)
            for call in calls { record = try await controller.workspace.tool(record, call: call) }
            XCTAssertTrue(record.run.pendingCalls.isEmpty); XCTAssertTrue(record.run.pending.isEmpty); XCTAssertTrue(record.run.reads.isEmpty)
            let results = record.run.messages.filter { $0.role == "tool" }
            XCTAssertEqual(results.compactMap(\.toolCallId), calls.map(\.id))
            for result in results {
                let object = try XCTUnwrap(NativeJSON.object(with: Data(result.content.utf8)) as? [String: Any])
                XCTAssertEqual(object["ok"] as? Bool, false)
                XCTAssertTrue((object["error"] as? String)?.contains("query") == true, result.content)
            }
            let compacting = try await controller.workspace.beginCompaction(record)
            let state = try XCTUnwrap(MacAgentCompaction.read(compacting))
            let archived = try JSONDecoder().decode([NativeAgentMessage].self, from: Data(contentsOf: root.appendingPathComponent(state.archive.messagesPath)))
            XCTAssertEqual(archived.flatMap { $0.toolCalls ?? [] }, calls)
            XCTAssertEqual(archived.compactMap(\.toolCallId), calls.map(\.id))
            let sent = self.expectation(description: "summary request started"), stopped = self.expectation(description: "summary stopped")
            let observer = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in stopped.fulfill() }
            ChatHTTPFixture.register(.init(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Partial summary\"}}]}\n\n", remaining: [], paused: true, onStart: { sent.fulfill() }), path: route)
            XCTAssertTrue(controller.resume(compacting, store: store, provider: provider))
            await self.fulfillment(of: [sent], timeout: 45)
            let reservation = try XCTUnwrap(controller.current?.run.requestReservation)
            controller.stop(); await self.fulfillment(of: [stopped], timeout: 10); withExtendedLifetime(observer) {}
            let interrupted = try XCTUnwrap(controller.current)
            XCTAssertEqual(interrupted.run.inputTokens, 123 + reservation.input); XCTAssertEqual(interrupted.run.outputTokens, 45 + reservation.output)
            XCTAssertNil(interrupted.run.requestReservation); XCTAssertEqual(interrupted.run.steps, 2)
            XCTAssertEqual(try MacAgentCompaction.read(interrupted)?.next, 0)
            let resumed = try await controller.workspace.resume(interrupted, answer: nil)
            XCTAssertEqual(resumed.run.inputTokens, interrupted.run.inputTokens); XCTAssertEqual(resumed.run.outputTokens, interrupted.run.outputTokens)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Beta.md")), Data(self.beta.utf8))
        }
    }
    func testCompactionJournalRejectsInvalidLimitsBeforeProgressValidation() throws {
        let id = UUID(), archive = MacAgentCompaction.Archive(id: UUID(), messagesDigest: String(repeating: "a", count: 64), textDigest: String(repeating: "b", count: 64), messageCount: 1, archivedCount: 1)
        let state = MacAgentCompaction(archive: archive, ranges: [[0, 1]], inputLimit: 4096, outputLimit: 256)
        var run = NativeAgentRun(id: id, chatID: "corrupt-context", owner: "fixture-owner", objective: "Preserve malformed journals", mode: .ask, scopeLabel: "No notes", scopeKind: .selected, readFolder: nil, readIDs: [], writeIDs: [], createFolders: [])
        run.version = 4; run.limits = .defaults; run.compactionPending = true; run.messages = [.init(role: "user", content: state.placeholder)]
        let bytes = try MacAgentCompaction.encode(run, state: state, archives: [archive], hashes: [])
        var object = try XCTUnwrap(NativeJSON.object(with: bytes) as? [String: Any]), limits = try XCTUnwrap(object["limits"] as? [String: Any])
        limits["maxInputTokens"] = 0; object["limits"] = limits
        XCTAssertThrowsError(try NativeAgentJournal.decode(JSONSerialization.data(withJSONObject: object), id: id)) { error in
            XCTAssertTrue(error.localizedDescription.contains("AI limits are unsupported or out of range"), error.localizedDescription)
        }
    }
    func testCompactionRefusesChangedArchivesAndToolRepliesAndReservesTheFinalStep() async throws {
        for variant in ["tools", "budget", "archive"] {
            try await fixture { root, _, controller, store, provider, route in
                let settings = try await controller.workspace.limits(); var limits = settings.limits
                limits.maxInputTokens = 8192; limits.maxOutputTokens = 1024; if variant == "budget" { limits.maxSteps = 2 }
                _ = try await controller.workspace.saveLimits(limits, expected: settings)
                var record = try await controller.workspace.start(objective: "Keep the original note intact", mode: .review, scope: .init(paths: ["Beta.md"]), chatID: "compaction-guard")
                let read = NativeAgentCall(id: "guard-read", name: "note_get", arguments: #"{"selector":"beta"}"#)
                record = try await controller.workspace.response(record, content: "", calls: [read], input: 10, output: 5, seconds: 0)
                record = try await controller.workspace.tool(record, call: read)
                record = try await controller.workspace.bindProvider(record, binding: provider.binding)
                record = try await controller.workspace.beginCompaction(record)
                let state = try XCTUnwrap(MacAgentCompaction.read(record)), before = try Data(contentsOf: root.appendingPathComponent("Beta.md"))
                if variant == "tools" {
                    ChatHTTPFixture.register(try self.call("summary-mutation", "note_append", ["selector": "beta", "revision": NativeAgentNote.hash(self.beta), "text": "Must not execute"]), path: route)
                } else {
                    var chain = try self.textReply("Ordinary answer.")
                    for _ in state.ranges { chain = try self.textReply("Reference summary.", next: chain) }
                    ChatHTTPFixture.register(chain, path: route)
                }
                if variant == "archive" {
                    let file = root.appendingPathComponent(state.archive.messagesPath)
                    try (Data(contentsOf: file) + Data(" ".utf8)).write(to: file)
                }
                try await self.finished(controller) { controller.resume(record, store: store, provider: provider) }
                let result = try XCTUnwrap(controller.current)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Beta.md")), before); XCTAssertTrue(result.run.pending.isEmpty)
                XCTAssertEqual(result.run.compactionPending, true)
                XCTAssertNil(result.run.requestReservation)
                if variant == "tools" {
                    XCTAssertTrue(controller.issue?.contains("provider returned tools") == true, controller.issue ?? "")
                    XCTAssertEqual(result.run.inputTokens, 20); XCTAssertEqual(result.run.steps, 2)
                    XCTAssertEqual(try MacAgentCompaction.read(result)?.next, 0)
                    XCTAssertFalse(result.run.messages.flatMap { $0.toolCalls ?? [] }.contains { $0.id == "summary-mutation" })
                    let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(state.archive.directory), includingPropertiesForKeys: nil)
                    let replies = files.filter { $0.lastPathComponent.hasPrefix("reply-") }
                    XCTAssertEqual(replies.count, 1); XCTAssertTrue(String(decoding: try Data(contentsOf: XCTUnwrap(replies.first)), as: UTF8.self).contains("summary-mutation"))
                } else {
                    XCTAssertNil(ChatHTTPFixture.captured(route), "Archive and budget refusals must happen before another provider request")
                    XCTAssertTrue(controller.issue?.contains(variant == "budget" ? "Insufficient saved step" : "context archive changed") == true, controller.issue ?? "")
                    XCTAssertEqual(result.run.steps, 1)
                }
            }
        }
    }
    func testNativeCompactionArchivesPriorJournalAndRequiresFreshReadsAfterSummary() async throws {
        try await fixture { root, _, controller, store, provider, route in
            let selectedProvider = MacAgentProvider.api(profile: .init(provider: .anthropic, endpoint: try provider.binding.endpoint, model: "claude-compaction"), key: "synthetic-key")
            let beta = "---\nzerus-id: beta\n---\n# Beta\n\n" + String(repeating: "Original factual detail and complete evidence. ", count: 1000)
            let note = root.appendingPathComponent("Beta.md"); try Data(beta.utf8).write(to: note)
            let settings = try await controller.workspace.limits(); var limits = settings.limits; limits.maxInputTokens = 8192; limits.maxOutputTokens = 1024
            _ = try await controller.workspace.saveLimits(limits, expected: settings)
            var record = try await controller.workspace.start(objective: "Summarize Beta and keep its source intact", mode: .review, scope: .init(paths: ["Beta.md"]), chatID: "native-compaction", history: String(repeating: "Earlier reference facts and constraints must survive in the complete archive.\n", count: 1200))
            let read = NativeAgentCall(id: "pre-compact-read", name: "note_get", arguments: #"{"selector":"beta","length":16000}"#)
            record = try await controller.workspace.response(record, content: "Read Beta", calls: [read], input: 10, output: 5, seconds: 0)
            record = try await controller.workspace.tool(record, call: read)
            record = try await controller.workspace.bindProvider(record, binding: selectedProvider.binding)
            XCTAssertEqual(record.run.reads.count, 1)
            let originalMessages = try MacAgentCompaction.encoder.encode(record.run.messages)
            XCTAssertNil(record.run.webMigration)
            var chain = try self.textReply("Untrusted combined reference summary of Beta.", anthropic: true, thinking: true)
            for _ in 0..<30 { chain = try self.textReply("Untrusted combined reference summary of Beta.", anthropic: true, thinking: true, next: chain) }
            ChatHTTPFixture.register(chain, path: route)
            try await self.finished(controller) { controller.resume(record, store: store, provider: selectedProvider) }
            XCTAssertNil(controller.issue)
            let summarized = try XCTUnwrap(controller.current)
            let archive = try XCTUnwrap(MacAgentCompaction.archives(summarized).first)
            let prior = try NativeAgentJournal.decode(Data(contentsOf: root.appendingPathComponent(archive.directory + "/prior-journal.json")), id: summarized.id)
            XCTAssertEqual(try MacAgentCompaction.encoder.encode(prior.run.messages), originalMessages, "Automatic compaction keeps every prior native model message")
            XCTAssertNil(try MacAgentCompaction.read(summarized))
            let replies = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(archive.directory), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("reply-") }
            XCTAssertFalse(replies.isEmpty)
            for reply in replies {
                let raw = String(decoding: try Data(contentsOf: reply), as: UTF8.self)
                XCTAssertFalse(raw.contains("Read before editing."), "Provider thinking stays device-private; compaction archives contain the summary and usage")
                XCTAssertFalse(raw.contains("signed-fallback-fixture"))
            }
            XCTAssertEqual(summarized.run.reads.count, 0, "Old read coverage must not authorize edits after source text leaves the active model context")
            let append = NativeAgentCall(id: "append-after-summary", name: "note_append", arguments: String(decoding: try JSONSerialization.data(withJSONObject: ["selector": "beta", "revision": NativeAgentNote.hash(beta), "text": "Must require a new read"]), as: UTF8.self))
            var denied = try await controller.workspace.response(summarized, content: "", calls: [append], input: 0, output: 0, seconds: 0)
            denied = try await controller.workspace.tool(denied, call: append)
            let result = try XCTUnwrap(NativeJSON.object(with: Data(XCTUnwrap(denied.run.messages.last).content.utf8)) as? [String: Any])
            XCTAssertEqual(result["ok"] as? Bool, false); XCTAssertTrue((result["error"] as? String)?.contains("Read this note at its current revision") == true)
            XCTAssertTrue(denied.run.pending.isEmpty); XCTAssertEqual(try Data(contentsOf: note), Data(beta.utf8))
            let question = NativeAgentCall(id: "question-after-summary", name: "ask_user", arguments: #"{"question":"Which exact constraints should be preserved?"}"#)
            var waiting = try await controller.workspace.response(denied, content: "", calls: [question], input: 0, output: 0, seconds: 0)
            waiting = try await controller.workspace.tool(waiting, call: question)
            XCTAssertNotNil(waiting.run.question)
            let answer = String(repeating: "Exact constraint must not disappear. ", count: 1000)
            ChatHTTPFixture.remove(route)
            ChatHTTPFixture.register(try self.textReply("Must not summarize the current user answer.", anthropic: true), path: route)
            try await self.finished(controller) { controller.resume(waiting, answer: answer, store: store, provider: selectedProvider) }
            XCTAssertNil(ChatHTTPFixture.captured(route), "An oversized current answer must not be silently replaced by a summary")
            XCTAssertTrue(controller.current?.run.messages.contains { $0.role == "user" && $0.content == "Answer to your question: " + answer } == true)
            XCTAssertEqual(controller.current?.run.steps, waiting.run.steps)
            XCTAssertTrue(controller.issue?.contains("nothing was sent") == true, controller.issue ?? "")
        }
    }
    func testLargeWebHistoryCompactsDurablyWithoutLosingImagesReceiptsOrCallIdentity() async throws {
        for fallback in [false, true] {
            try await fixture { root, workspace, controller, store, provider, route in
                let selectedProvider: MacAgentProvider = fallback ? .api(profile: .init(provider: .compatible, endpoint: try provider.binding.endpoint, model: "fixture-model", contextWindow: 32_000), key: "synthetic-key") : provider
                let io = try XCTUnwrap(workspace.io)
                let limits = try await controller.workspace.limits(); var budget = limits.limits
                budget.maxInputTokens = 12_000; budget.maxOutputTokens = 1024
                if fallback { budget.maxInputTokens = 48_000; budget.maxTotalTokens = 1_000_000; budget.maxSteps = 100 }
                _ = try await controller.workspace.saveLimits(budget, expected: limits)
                if fallback { let settings = try await controller.workspace.preferences(); var value = settings.value; value.textFallback = true; _ = try await controller.workspace.savePreferences(value, expected: settings) }
                let chat = try await io.createConversation(device: .init(id: "fixture-owner", name: "Compaction Mac"), text: "Continue the full saved work", scope: Data(#"{"kind":"type","path":["inbox"],"includeSubtypes":false}"#.utf8))
                let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/web-agent-migration.json")
                let saved = try XCTUnwrap(NativeJSON.object(with: Data(contentsOf: fixtureURL)) as? [String: Any])
                var web = try XCTUnwrap(saved["run"] as? [String: Any]); web["chatId"] = chat.conversation.id
                web["objective"] = "Continue the original long-history objective and retain the verified proposal."
                web["usage"] = ["inputTokens": 0, "outputTokens": 0, "steps": 0, "elapsedMs": 0]
                for note in try XCTUnwrap(saved["notes"] as? [[String: Any]]) {
                    let file = root.appendingPathComponent(try XCTUnwrap(note["path"] as? String)); try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(XCTUnwrap(note["content"] as? String).utf8).write(to: file)
                }
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 6, bitsPerPixel: 24))
                bitmap.setColor(.green, atX: 0, y: 0); let image = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:]))
                var messages: [[String: Any]] = [["role": "user", "content": [["type": "text", "text": "Original archive sentinel — preserve the first factual decision."], ["type": "file", "mediaType": "image/jpeg", "data": image.base64EncodedString()]]],
                    ["role": "assistant", "content": [["type": "tool-call", "toolCallId": "archived-read", "toolName": "note_get", "input": ["selector": "note-1"]]]],
                    ["role": "tool", "content": [["type": "tool-result", "toolCallId": "archived-read", "toolName": "note_get", "output": ["type": "text", "value": "Original verified read result."]]]]]
                if fallback { messages.append(["role": "user", "content": String(repeating: "Historical factual detail and rejected approach. ", count: 50_000)]) }
                for index in 0..<(fallback ? 4 : 260) {
                    let text = !fallback && index < 256 ? "Earlier turn \(index). " + String(repeating: "Historical factual detail and rejected approach. ", count: 12) : "Recent preserved turn \(index)."
                    messages.append(["role": "user", "content": text]); messages.append(["role": "assistant", "content": text])
                }
                web["messages"] = messages
                let source = try JSONSerialization.data(withJSONObject: web, options: [.sortedKeys]), path = ".zerus/ai/runs/" + chat.conversation.id + "/migration-web-run.json", sourceURL = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true); try source.write(to: sourceURL)
                let prepared = try await controller.workspace.prepareWebMigration(path: path, binding: selectedProvider.binding)
                if fallback { XCTAssertLessThan(messages.count, 240); XCTAssertGreaterThan(try MacAgentCompaction.encoder.encode(prepared.transcript).count, 2_000_000) }
                XCTAssertEqual(prepared.transcript.count, messages.count); XCTAssertEqual(prepared.record.run.compactionPending, true)
                try await controller.importWebMigration(prepared, store: store)
                XCTAssertNil(ChatHTTPFixture.captured(route), "Import archives the full transcript without making a summary request")
                let initial = try XCTUnwrap(controller.current), state = try XCTUnwrap(MacAgentCompaction.read(initial))
                XCTAssertGreaterThan(state.ranges.count, 1)
                let archive = try Data(contentsOf: root.appendingPathComponent(state.archive.messagesPath))
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let archived = try decoder.decode([NativeAgentMessage].self, from: archive)
                XCTAssertEqual(archived.count, messages.count); XCTAssertEqual(archived.first?.content, "Original archive sentinel — preserve the first factual decision.")
                XCTAssertEqual(archived[1].toolCalls?.first?.id, archived[2].toolCallId)
                let second = self.expectation(description: "second summary request in flight")
                let pausedScript = ChatHTTPFixture.Script(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Unfinished summary\"}}]}\n\n", remaining: [], paused: true, onStart: { second.fulfill() })
                ChatHTTPFixture.register(try self.textReply("Saved first combined reference summary.", next: pausedScript), path: route)
                XCTAssertTrue(controller.resume(initial, store: store, provider: selectedProvider))
                await self.fulfillment(of: [second], timeout: fallback ? 30 : 12)
                let stopped = await controller.stopAndCheckpoint(); XCTAssertTrue(stopped)
                let interrupted = try XCTUnwrap(controller.current), progress = try XCTUnwrap(MacAgentCompaction.read(interrupted))
                if fallback { XCTAssertLessThanOrEqual(progress.inputLimit + budget.maxOutputTokens, 32_000) }
                XCTAssertEqual(progress.next, 1); XCTAssertEqual(progress.summary, "Saved first combined reference summary.")
                XCTAssertNil(interrupted.run.requestReservation); XCTAssertEqual(interrupted.run.steps, 2); XCTAssertGreaterThan(interrupted.run.inputTokens, 10)
                XCTAssertFalse(controller.live.contains("Unfinished summary"), "Reference summaries must not become the user's assistant reply")
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(state.archive.messagesPath)), archive)
                let noteURL = root.appendingPathComponent("inbox/Note-1.md"), before = try Data(contentsOf: noteURL)
                try await controller.reviewProposals([XCTUnwrap(interrupted.run.pending.first).id]); try await controller.approve(XCTUnwrap(controller.review))
                try await controller.reviewUndo(XCTUnwrap(controller.current?.run.receipts.last).id); try await controller.approve(XCTUnwrap(controller.review))
                XCTAssertEqual(try Data(contentsOf: noteURL), before); XCTAssertEqual(controller.current?.run.compactionPending, true)
                var chain = try self.textReply("Final answer after durable compaction.")
                for index in (progress.next..<progress.ranges.count).reversed() { chain = try self.textReply("Combined summary through fragment \(index + 1). Verified decisions and unfinished work retained.", next: chain) }
                ChatHTTPFixture.register(chain, path: route)
                let resumable = try XCTUnwrap(controller.current)
                try await self.finished(controller, timeout: fallback ? 60 : 8) { controller.resume(resumable, store: store, provider: selectedProvider) }
                XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Final answer after durable compaction.")
                let completed = try XCTUnwrap(controller.current)
                XCTAssertNil(try MacAgentCompaction.read(completed)); XCTAssertNil(completed.run.compactionPending)
                XCTAssertEqual(completed.run.steps, progress.ranges.count + 2)
                XCTAssertEqual(completed.run.inputTokens, interrupted.run.inputTokens + progress.ranges.count * 10)
                XCTAssertTrue(completed.run.messages.first?.content.contains("Combined summary through fragment \(progress.ranges.count)") == true)
                XCTAssertEqual(completed.run.reads.count, 0, "A summary does not unlock native note writes")
                let wire = String(decoding: try JSONSerialization.data(withJSONObject: self.requestObject(XCTUnwrap(ChatHTTPFixture.captured(route)))), as: UTF8.self)
                XCTAssertTrue(wire.contains("original long-history objective")); XCTAssertTrue(wire.contains("Recent preserved turn \(fallback ? 3 : 259)")); XCTAssertTrue(wire.contains("image_url"))
                let attachment = try XCTUnwrap(completed.run.attachments?.first); XCTAssertEqual(try store.read(attachment), image)
                XCTAssertEqual(try Data(contentsOf: sourceURL), source)
                if !fallback {
                    XCTAssertFalse(completed.run.messages.flatMap { $0.toolCalls ?? [] }.contains { $0.id == "archived-read" })
                    ChatHTTPFixture.register(try self.call("archived-read", "note_get", ["selector": "note-1"]), path: route)
                    try await self.finished(controller) { controller.resume(completed, store: store, provider: selectedProvider) }
                    XCTAssertTrue(controller.issue?.contains("reused a tool-call identity from archived history") == true, controller.issue ?? "")
                    XCTAssertEqual(controller.current?.run.reads.count, 0)
                    XCTAssertFalse(controller.current?.run.messages.flatMap { $0.toolCalls ?? [] }.contains { $0.id == "archived-read" } == true)
                }
            }
        }
    }
    func testLargeImportedProposalKeepsExactReviewAndUndoAcrossReopening() async throws {
        try await fixture { root, workspace, controller, store, provider, route in
            let io = try XCTUnwrap(workspace.io)
            let chat = try await io.createConversation(device: .init(id: "fixture-owner", name: "Storage Mac"), text: "Continue large reviewed work", scope: Data(#"{"kind":"type","path":["inbox"],"includeSubtypes":false}"#.utf8))
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/web-agent-migration.json")
            let fixture = try XCTUnwrap(NativeJSON.object(with: Data(contentsOf: url)) as? [String: Any])
            let old = "---\nzerus-id: note-1\n---\n# Alpha\n\nOriginal writing."
            let before = old + "\n" + String(repeating: "Exact source detail must survive review and Undo. ", count: 70_000)
            let after = before + "\n\nWeb staged writing."
            func enlarged(_ value: Any) -> Any {
                if let text = value as? String { return text.replacingOccurrences(of: old, with: before) }
                if let list = value as? [Any] { return list.map(enlarged) }
                if let object = value as? [String: Any] { return object.mapValues(enlarged) }
                return value
            }
            var web = try XCTUnwrap(enlarged(fixture["run"]!) as? [String: Any]); web["chatId"] = chat.conversation.id
            web["readIds"] = ["note-1", "note-2", "note-3"]; web["writeIds"] = ["note-1", "note-2", "note-3"]
            for note in try XCTUnwrap(enlarged(fixture["notes"]!) as? [[String: Any]]) {
                let target = root.appendingPathComponent(try XCTUnwrap(note["path"] as? String))
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(XCTUnwrap(note["content"] as? String).utf8).write(to: target)
            }
            let gamma = "---\nzerus-id: note-3\n---\n# Gamma\n\nIndependent pin target."
            try Data(gamma.utf8).write(to: root.appendingPathComponent("inbox/Gamma.md"))
            let path = ".zerus/ai/runs/" + chat.conversation.id + "/migration-web-run.json", target = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let source = try JSONSerialization.data(withJSONObject: web, options: [.sortedKeys]); try source.write(to: target)
            let review: MacWebAgentMigrationReview
            do { review = try await controller.workspace.prepareWebMigration(path: path, binding: provider.binding) }
            catch { XCTFail("Preparing the large review failed: \(String(reflecting: error))"); return }
            XCTAssertNil(ChatHTTPFixture.captured(route)); XCTAssertEqual(review.record.run.pending.first?.before?.content, before)
            try await controller.importWebMigration(review, store: store)
            let imported = try XCTUnwrap(controller.current)
            let reopened = try await controller.workspace.records().records.first { $0.id == imported.id }
            let record = try XCTUnwrap(reopened)
            XCTAssertEqual(record.run.pending.first?.after.content, after)
            XCTAssertLessThan(record.bytes.count, 8_000_000)
            try await controller.open(record)
            XCTAssertEqual(record.run.version, 7)
            let directory = root.appendingPathComponent(".zerus/native-ai/payloads/" + record.id.uuidString.lowercased())
            let payload = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            let exactPayload = try Data(contentsOf: payload)
            try await controller.reviewProposals([XCTUnwrap(record.run.pending.first).id])
            let prepared = try XCTUnwrap(controller.review)
            try (exactPayload + Data(" ".utf8)).write(to: payload)
            do { try await controller.approve(prepared); XCTFail("Changed review data must refuse Apply") }
            catch { XCTAssertTrue(error.localizedDescription.contains("payload"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox/Note-1.md")), Data(before.utf8))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id))), record.bytes)
            try exactPayload.write(to: payload)
            try await controller.approve(prepared)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox/Note-1.md")), Data(after.utf8))
            let saved = try XCTUnwrap(controller.current), receipt = try XCTUnwrap(saved.run.receipts.last)
            let savedRecords = try await controller.workspace.records()
            try await controller.open(XCTUnwrap(savedRecords.records.first { $0.id == saved.id }))
            try await controller.reviewUndo(receipt.id); try await controller.approve(XCTUnwrap(controller.review))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox/Note-1.md")), Data(before.utf8))
            XCTAssertNotNil(controller.current?.run.receipts.last?.undoneAt)
            XCTAssertEqual(try Data(contentsOf: target), source)
            XCTAssertNil(ChatHTTPFixture.captured(route))
            ChatHTTPFixture.register(try self.answer("Continued with all large review records retained."), path: route)
            let resumable = try XCTUnwrap(controller.current)
            try await self.finished(controller, timeout: 30) { controller.resume(resumable, store: store, provider: provider) }
            XCTAssertNil(controller.issue, controller.issue ?? "")
            XCTAssertEqual(controller.current?.run.status, "complete")
            XCTAssertEqual(controller.current?.run.receipts.last?.before.first?.content, before)
            XCTAssertNotNil(controller.current?.run.receipts.last?.undoneAt)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox/Note-1.md")), Data(before.utf8))
            let betaPath = root.appendingPathComponent("inbox/Note-2.md"), beta = try String(contentsOf: betaPath, encoding: .utf8)
            let reads = [NativeAgentCall(id: "read-small-body", name: "note_get", arguments: #"{"selector":"note-2"}"#), NativeAgentCall(id: "read-pin-target", name: "note_get", arguments: #"{"selector":"note-3"}"#)]
            var mixed = try await controller.workspace.response(XCTUnwrap(controller.current), content: "", calls: reads, input: 0, output: 0, seconds: 0)
            for call in reads { mixed = try await controller.workspace.tool(mixed, call: call) }
            let append = NativeAgentCall(id: "append-small-body", name: "note_append", arguments: "{\"selector\":\"note-2\",\"revision\":\"" + NativeAgentNote.hash(beta) + "\",\"text\":\"Native addition.\"}")
            let pin = NativeAgentCall(id: "pin-independent-note", name: "note_organize", arguments: "{\"selector\":\"note-3\",\"revision\":\"" + NativeAgentNote.hash(gamma) + "\",\"pinned\":true}")
            mixed = try await controller.workspace.response(mixed, content: "", calls: [append, pin], input: 0, output: 0, seconds: 0)
            for call in [append, pin] { mixed = try await controller.workspace.tool(mixed, call: call) }
            XCTAssertEqual(mixed.run.pending.count, 2)
            try await controller.open(mixed)
            do { try await controller.reviewProposals(Set(mixed.run.pending.map(\.id))); try await controller.approve(XCTUnwrap(controller.review)) }
            catch { XCTFail("Mixed approval failed: \(String(reflecting: error))"); return }
            let applied = try XCTUnwrap(controller.current)
            XCTAssertEqual(applied.run.receipts.count, 3)
            XCTAssertEqual(try String(contentsOf: betaPath, encoding: .utf8), beta + "\n\nNative addition.")
            XCTAssertTrue(NoteDocument(path: "inbox/Gamma.md", content: try String(contentsOf: root.appendingPathComponent("inbox/Gamma.md"), encoding: .utf8), modified: .distantPast).pinned)
            for receipt in applied.run.receipts.suffix(2) {
                try await controller.reviewUndo(receipt.id); try await controller.approve(XCTUnwrap(controller.review))
            }
            XCTAssertEqual(try Data(contentsOf: betaPath), Data(beta.utf8))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox/Gamma.md")), Data(gamma.utf8))
            XCTAssertEqual(controller.current?.run.receipts.first?.before.first?.content, before)
        }
    }
    func testWebRunImportKeepsOriginalHistoryThenReviewsAppliesUndoesAndContinues() async throws {
        for fallback in [false, true] {
            try await fixture { root, workspace, controller, store, provider, route in
                let io = try XCTUnwrap(workspace.io)
                let scope = Data(#"{"kind":"type","path":["inbox"],"includeSubtypes":false}"#.utf8)
                let chat = try await io.createConversation(device: .init(id: "fixture-owner", name: "Migration Mac"), text: "Continue saved work", scope: scope)
                let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/web-agent-migration.json")
                let fixture = try XCTUnwrap(NativeJSON.object(with: Data(contentsOf: url)) as? [String: Any])
                var web = try XCTUnwrap(fixture["run"] as? [String: Any]); web["chatId"] = chat.conversation.id
                for note in try XCTUnwrap(fixture["notes"] as? [[String: Any]]) {
                    let target = root.appendingPathComponent(try XCTUnwrap(note["path"] as? String))
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(XCTUnwrap(note["content"] as? String).utf8).write(to: target)
                }
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 6, bitsPerPixel: 24))
                bitmap.setColor(.blue, atX: 0, y: 0)
                let jpeg = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:]))
                var messages = try XCTUnwrap(web["messages"] as? [[String: Any]])
                messages += [["role": "assistant", "content": [
                    ["type": "tool-call", "toolCallId": "saved-call", "toolName": "note_list", "input": [:]],
                    ["type": "tool-call", "toolCallId": "saved-call", "toolName": "note_schema", "input": ["selector": "note-1"]]]],
                    ["role": "tool", "content": [
                        ["type": "tool-result", "toolCallId": "saved-call", "toolName": "note_schema", "output": ["type": "json", "value": ["schema": "Preserved schema result"]]],
                        ["type": "tool-result", "toolCallId": "saved-call", "toolName": "note_list", "output": ["type": "json", "value": ["notes": "Preserved list result"]]]]]]
                messages.append(["role": "user", "content": [["type": "text", "text": "Keep the frozen image."], ["type": "file", "mediaType": "image/jpeg", "data": ["type": "data", "data": jpeg.base64EncodedString()]]]])
                messages.append(["role": "assistant", "content": [["type": "tool-call", "toolCallId": "pending-analysis", "toolName": "analyze_notes", "input": ["question": "Check the source", "selectors": ["note-1"]]]]])
                web["messages"] = messages
                var child = web
                child["id"] = "migration-worker"; child["parentRunId"] = web["id"]; child["objective"] = "Independent evidence check"
                child["mode"] = "ask"; child["writeIds"] = []; child["createTypes"] = []; child["proposals"] = []; child["receipts"] = []; child["events"] = []; child["status"] = "complete"
                child["messages"] = [["role": "user", "content": "Check the source"], ["role": "assistant", "content": "Saved independent analysis evidence."]]
                child["usage"] = ["inputTokens": 7, "outputTokens": 3, "budgetTokens": 12, "steps": 1, "elapsedMs": 100]
                let childSource = try JSONSerialization.data(withJSONObject: child, options: [.sortedKeys])
                if fallback {
                    var events = try XCTUnwrap(web["events"] as? [[String: Any]])
                    events.append(["id": "accounted-child", "at": try XCTUnwrap(web["updatedAt"] as? String), "kind": "activity", "text": "Independent read-only analysis finished", "detail": ["runs": [["id": "migration-worker"]]]])
                    web["events"] = events
                }
                let source = try JSONSerialization.data(withJSONObject: web, options: [.prettyPrinted, .sortedKeys])
                let path = ".zerus/ai/runs/" + chat.conversation.id + "/migration-web-run.json", target = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); try source.write(to: target)
                try childSource.write(to: target.deletingLastPathComponent().appendingPathComponent("migration-worker.json"))
                if fallback { let snapshot = try await controller.workspace.preferences(); var preferences = snapshot.value; preferences.textFallback = true; _ = try await controller.workspace.savePreferences(preferences, expected: snapshot) }
                let catalog = try await controller.workspace.webRecords(chatID: chat.conversation.id)
                XCTAssertEqual(catalog.records.filter { $0.parentRunID == nil }.count, 1); XCTAssertEqual(catalog.records.count, 2); XCTAssertTrue(catalog.issues.isEmpty)
                let prepared = try await controller.workspace.prepareWebMigration(path: path, binding: provider.binding)
                let competing = try await controller.workspace.prepareWebMigration(path: path, binding: provider.binding)
                XCTAssertNotEqual(prepared.id, competing.id, "Each reviewed attempt needs isolated frozen-input ownership")
                XCTAssertEqual(prepared.record.run.inputTokens, fallback ? 160 : 169); XCTAssertEqual(prepared.record.run.outputTokens, fallback ? 40 : 43)
                XCTAssertEqual(prepared.record.run.steps, 2); XCTAssertEqual(prepared.record.run.activeSeconds, 1.25)
                XCTAssertEqual(prepared.record.run.reads.count, 0, "Web revision strings never become native read coverage")
                XCTAssertEqual(prepared.record.run.pending.count, 1)
                XCTAssertEqual(prepared.record.run.pending.first?.call.name, "note_append", "Imported proposal labels retain the original tool operation")
                XCTAssertTrue(prepared.record.run.permitsCreation("inbox")); XCTAssertFalse(prepared.record.run.permitsCreation("inbox/Child")); XCTAssertFalse(prepared.record.run.permitsPath("inbox/Child/A.md"))
                let before = try Data(contentsOf: root.appendingPathComponent("inbox/Note-1.md"))
                try (source + Data(" ".utf8)).write(to: target)
                do { try await controller.importWebMigration(prepared, store: store); XCTFail("An image-bearing import must reject changed source bytes") }
                catch { XCTAssertTrue(error.localizedDescription.contains("changed outside Zerus"), error.localizedDescription) }
                let inputDirectory = store.directory.appendingPathComponent("Attachments")
                XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: inputDirectory.path)) ?? [], [], "A refused import must clean its newly prepared images")
                XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("AttachmentRunInputs/" + prepared.id.uuidString.lowercased() + ".json").path))
                try source.write(to: target)
                try await controller.importWebMigration(prepared, store: store)
                let originalInputs = try FileManager.default.contentsOfDirectory(atPath: inputDirectory.path).sorted()
                do { try await controller.importWebMigration(competing, store: store); XCTFail("A competing reviewed import must not create another active run") }
                catch { XCTAssertTrue(error.localizedDescription.contains("Another import"), error.localizedDescription) }
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inputDirectory.path).sorted(), originalInputs)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(NativeAgentJournal.path(competing.id)).path))
                do { _ = try await controller.workspace.prepareWebMigration(path: path, binding: provider.binding); XCTFail("An active imported source must be opened instead of imported twice") }
                catch { XCTAssertTrue(error.localizedDescription.contains("already"), error.localizedDescription) }
                XCTAssertNil(ChatHTTPFixture.captured(route), "Review and import must not send a paid request")
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox/Note-1.md")), before)
                XCTAssertEqual(try Data(contentsOf: target), source)
                let deniedCall = NativeAgentCall(id: "native-outside-create", name: "note_create", arguments: #"{"title":"Outside","body":"Must not be created","folder":"inbox/Child"}"#)
                var denied = try await controller.workspace.response(XCTUnwrap(controller.current), content: "", calls: [deniedCall], input: 0, output: 0, seconds: 0)
                denied = try await controller.workspace.tool(denied, call: deniedCall)
                let denial = try XCTUnwrap(NativeJSON.object(with: Data(XCTUnwrap(denied.run.messages.last).content.utf8)) as? [String: Any])
                XCTAssertEqual(denial["ok"] as? Bool, false); XCTAssertTrue((denial["error"] as? String)?.contains("creation folder is outside") == true)
                XCTAssertEqual(denied.run.pending.count, 1); XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("inbox/Child").path))
                try await controller.open(denied)
                let imported = try XCTUnwrap(controller.current), provenance = try XCTUnwrap(imported.run.webMigration)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(provenance.archivePath)), source)
                let childArchive = try XCTUnwrap(provenance.childSources?.first)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(childArchive.archivePath)), childSource)
                XCTAssertTrue(imported.run.pendingCalls.isEmpty)
                let reopened = try NativeAgentJournal.decode(Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(imported.id))), id: imported.id)
                let image = try XCTUnwrap(reopened.run.attachments?.first)
                try store.validate(run: reopened.id, chat: chat.conversation.id, items: [image]); XCTAssertEqual(try store.read(image), jpeg)
                XCTAssertEqual(reopened.run.messages[1].toolCalls?.first?.id, reopened.run.messages[2].toolCallId)
                let repeated = try XCTUnwrap(reopened.run.messages[3].toolCalls)
                XCTAssertEqual(repeated.count, 2); XCTAssertNotEqual(repeated[0].id, repeated[1].id)
                XCTAssertEqual(reopened.run.messages[4].toolCallId, repeated[1].id); XCTAssertEqual(reopened.run.messages[5].toolCallId, repeated[0].id)
                try await controller.reviewProposals([XCTUnwrap(imported.run.pending.first).id])
                try await controller.approve(XCTUnwrap(controller.review))
                XCTAssertEqual(String(decoding: try Data(contentsOf: root.appendingPathComponent("inbox/Note-1.md")), as: UTF8.self), "---\nzerus-id: note-1\n---\n# Alpha\n\nOriginal writing.\n\nWeb staged writing.")
                let saved = try XCTUnwrap(controller.current), receipt = try XCTUnwrap(saved.run.receipts.last)
                try await controller.reviewUndo(receipt.id); try await controller.approve(XCTUnwrap(controller.review))
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox/Note-1.md")), before)
                XCTAssertNotNil(controller.current?.run.receipts.last?.undoneAt)
                ChatHTTPFixture.register(try self.answer("Continued the imported work."), path: route)
                let resumable = try XCTUnwrap(controller.current)
                try await self.finished(controller) { controller.resume(resumable, store: store, provider: provider) }
                XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.status, "complete")
                let request = try self.requestObject(XCTUnwrap(ChatHTTPFixture.captured(route)))
                let wire = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
                XCTAssertTrue(wire.contains("Original writing.")); XCTAssertTrue(wire.contains("image_url")); XCTAssertTrue(wire.contains("saved-call") || fallback && wire.contains("Runtime tool result"))
                XCTAssertTrue(wire.contains("Saved independent analysis evidence."))
                XCTAssertEqual(try Data(contentsOf: target), source)
                ChatHTTPFixture.remove(route)
                let deleted = try XCTUnwrap(controller.current), oldArchive = root.appendingPathComponent(provenance.archivePath)
                let indexURL = root.appendingPathComponent(".zerus/native-ai/web-imports/" + NativeHistory.hash(path) + ".json")
                let originalIndexBytes = try Data(contentsOf: indexURL)
                var index = try XCTUnwrap(NativeJSON.object(with: originalIndexBytes) as? [String: Any])
                var boundedIndex = index; boundedIndex["updatedAt"] = ""; boundedIndex["padding"] = ""
                let base = try JSONSerialization.data(withJSONObject: boundedIndex, options: [.sortedKeys, .withoutEscapingSlashes])
                boundedIndex["padding"] = String(repeating: "x", count: 64_000 - base.count)
                let boundedBytes = try JSONSerialization.data(withJSONObject: boundedIndex, options: [.sortedKeys, .withoutEscapingSlashes])
                XCTAssertEqual(boundedBytes.count, 64_000)
                try boundedBytes.write(to: indexURL)
                do { try await controller.deleteCurrent(); XCTFail("A status update must not publish an index beyond its readable size allowance"); return }
                catch { XCTAssertTrue(error.localizedDescription.contains("size"), error.localizedDescription) }
                XCTAssertEqual(try Data(contentsOf: indexURL), boundedBytes)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(deleted.id))), deleted.bytes)
                try originalIndexBytes.write(to: indexURL)
                index["future"] = ["keep": true]
                try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]).write(to: indexURL)
                let activePath = root.appendingPathComponent(NativeAgentJournal.path(deleted.id))
                try FileManager.default.removeItem(at: activePath)
                do { _ = try await controller.workspace.prepareWebMigration(path: path, binding: provider.binding); XCTFail("A missing active journal may still be syncing; it must not release its source") }
                catch { XCTAssertTrue(error.localizedDescription.contains("already"), error.localizedDescription) }
                try deleted.bytes.write(to: activePath)
                try await controller.deleteCurrent()
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(NativeAgentJournal.path(deleted.id)).path))
                // A delayed sync may resurrect the old journal after deletion.
                let ghost = root.appendingPathComponent(NativeAgentJournal.path(deleted.id))
                try deleted.bytes.write(to: ghost)
                do { _ = try await controller.workspace.resume(deleted, answer: nil); XCTFail("A retired import must not resume after its old journal reappears") }
                catch { XCTAssertTrue(error.localizedDescription.contains("deleted or replaced"), error.localizedDescription) }
                XCTAssertEqual(try Data(contentsOf: ghost), deleted.bytes)
                try FileManager.default.removeItem(at: ghost)
                let replacementSource = source + Data(" ".utf8); try replacementSource.write(to: target)
                let reimport = try await controller.workspace.prepareWebMigration(path: path, binding: provider.binding)
                XCTAssertNotEqual(reimport.id, deleted.id)
                do { try await controller.importWebMigration(reimport, store: store) }
                catch { XCTFail("Re-import after deletion failed: \(String(reflecting: error))"); return }
                let replacement = try XCTUnwrap(controller.current), replacementImage = try XCTUnwrap(replacement.run.attachments?.first)
                XCTAssertNotEqual(replacementImage.id, image.id)
                try store.validate(run: deleted.id, chat: chat.conversation.id, items: [image])
                try store.validate(run: replacement.id, chat: chat.conversation.id, items: [replacementImage])
                XCTAssertEqual(try store.read(image), jpeg); XCTAssertEqual(try store.read(replacementImage), jpeg)
                XCTAssertEqual(try Data(contentsOf: oldArchive), source)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(XCTUnwrap(replacement.run.webMigration).archivePath)), replacementSource)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(childArchive.archivePath)), childSource)
                let latest = try await controller.workspace.records()
                XCTAssertEqual(latest.records.filter { $0.run.webMigration?.sourcePath == path }.map(\.id), [replacement.id])
                let legacy = root.appendingPathComponent(".zerus/native-ai/web-sources/" + MacWebAgentRun.nativeID(chat.conversation.id + "/migration-web-run").uuidString.lowercased() + ".json")
                XCTAssertEqual(try Data(contentsOf: legacy), source, "The legacy reservation must retain the first exact source")
                let changedIndex = try XCTUnwrap(NativeJSON.object(with: Data(contentsOf: indexURL)) as? [String: Any])
                XCTAssertEqual((changedIndex["future"] as? [String: Any])?["keep"] as? Bool, true)
                try deleted.bytes.write(to: ghost)
                try await controller.open(deleted)
                try await controller.deleteCurrent()
                XCTAssertFalse(FileManager.default.fileExists(atPath: ghost.path))
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(replacement.id))), replacement.bytes)
                let pausedReplacement = try await controller.workspace.pause(replacement, reason: "Keep replacement available after retired-journal cleanup")
                XCTAssertEqual(pausedReplacement.id, replacement.id)
                try await controller.open(pausedReplacement)
                let owner = MacChatDevice(id: "fixture-owner", name: "Migration Mac")
                let removedChat = try await io.changeConversation(io.conversationSnapshot(chat.conversation.id), device: owner, change: .delete)
                _ = try await ageDeletedConversation(removedChat, at: Date().addingTimeInterval(-31 * 24 * 60 * 60), root: root, io: io)
                let retained = try await io.conversations(device: owner)
                XCTAssertEqual(retained.purgedIDs, [chat.conversation.id], retained.issues.joined(separator: "\n"))
                XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(NativeAgentJournal.path(replacement.id)).path))
                let expiredIndex = try XCTUnwrap(NativeJSON.object(with: Data(contentsOf: indexURL)) as? [String: Any])
                XCTAssertEqual(expiredIndex["state"] as? String, "deleted")
                XCTAssertEqual((expiredIndex["future"] as? [String: Any])?["keep"] as? Bool, true)
                XCTAssertEqual(try Data(contentsOf: oldArchive), source)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(childArchive.archivePath)), childSource)
                try store.validate(run: replacement.id, chat: chat.conversation.id, items: [replacementImage])
                XCTAssertEqual(try store.read(replacementImage), jpeg)
                await controller.reload(); XCTAssertNil(controller.current); XCTAssertTrue(controller.records.isEmpty)
                XCTAssertNil(ChatHTTPFixture.captured(route), "Deletion and re-import must not send a provider request")
            }
        }
    }
    func testWebRunImportRetainsReceiptsQuestionsAndRefusesStaleReviews() async throws {
        for variant in ["receipt", "partial", "source-changed", "settings-changed", "owner-changed"] {
            try await fixture { root, workspace, controller, store, provider, route in
                let io = try XCTUnwrap(workspace.io)
                let chat = try await io.createConversation(device: .init(id: "fixture-owner", name: "Migration Mac"), text: "Continue reviewed work", scope: Data(#"{"kind":"type","path":["inbox"],"includeSubtypes":false}"#.utf8))
                let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/web-agent-receipt.json")
                let fixture = try XCTUnwrap(NativeJSON.object(with: Data(contentsOf: url)) as? [String: Any])
                var web = try XCTUnwrap(fixture["run"] as? [String: Any]); web["chatId"] = chat.conversation.id
                if variant == "partial" { var proposals = try XCTUnwrap(web["proposals"] as? [[String: Any]]); proposals[0]["status"] = "applying"; web["proposals"] = proposals }
                for note in try XCTUnwrap(fixture["notes"] as? [[String: Any]]) {
                    let target = root.appendingPathComponent(try XCTUnwrap(note["path"] as? String))
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(XCTUnwrap(note["content"] as? String).utf8).write(to: target)
                }
                let source = try JSONSerialization.data(withJSONObject: web, options: [.sortedKeys]), path = ".zerus/ai/runs/" + chat.conversation.id + "/migration-web-run.json", target = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); try source.write(to: target)
                let prepared = try await controller.workspace.prepareWebMigration(path: path, binding: provider.binding)
                XCTAssertEqual(prepared.record.run.receipts.count, 1)
                XCTAssertEqual(prepared.record.run.trackedPlan?.map(\.status), [.complete, .running])
                XCTAssertEqual(prepared.record.run.question, "Should Beta keep the additional paragraph?")
                if variant.hasSuffix("changed") {
                    switch variant {
                    case "source-changed": try (source + Data(" ".utf8)).write(to: target)
                    case "settings-changed": try Data("{}".utf8).write(to: root.appendingPathComponent(".zerus/ai/settings.json"))
                    default: _ = try await io.changeConversation(chat, device: .init(id: "other-owner", name: "Other"), change: .claim)
                    }
                    do { try await controller.importWebMigration(prepared, store: store); XCTFail("Changed review must refuse before creating a native run") }
                    catch { XCTAssertTrue(error.localizedDescription.contains(variant == "owner-changed" ? "conversation changed after review" : "changed outside Zerus"), error.localizedDescription) }
                    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(NativeAgentJournal.path(prepared.id)).path))
                    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(try XCTUnwrap(prepared.record.run.webMigration).archivePath).path))
                    XCTAssertNil(ChatHTTPFixture.captured(route)); return
                }
                try await controller.importWebMigration(prepared, store: store)
                let imported = try XCTUnwrap(controller.current), receipt = try XCTUnwrap(imported.run.receipts.first)
                if variant == "partial" {
                    let first = try XCTUnwrap(imported.run.proposals.first)
                    try await controller.reviewProposals([first.id])
                    XCTAssertTrue(try XCTUnwrap(controller.review).changedNotes.isEmpty, "Earlier web writes must be acknowledged without rewriting their notes")
                    try await controller.approve(XCTUnwrap(controller.review))
                    XCTAssertEqual(controller.current?.run.receipts.count, 1, "A recovered partial apply must not duplicate the existing receipt")
                }
                let note = root.appendingPathComponent("inbox/Note-1.md"), saved = try Data(contentsOf: note), newer = saved + Data("\nIndependent newer writing.".utf8)
                try newer.write(to: note)
                do { try await controller.reviewUndo(receipt.id); XCTFail("Imported Undo must retain newer work") }
                catch { XCTAssertTrue(error.localizedDescription.contains("changed after the imported receipt"), error.localizedDescription) }
                XCTAssertEqual(try Data(contentsOf: note), newer)
                try saved.write(to: note); try await controller.reviewUndo(receipt.id); try await controller.approve(XCTUnwrap(controller.review))
                XCTAssertEqual(String(decoding: try Data(contentsOf: note), as: UTF8.self), "---\nzerus-id: note-1\n---\n# Alpha\n\nOriginal writing.")
                ChatHTTPFixture.register(try self.answer("Continued after the saved answer."), path: route)
                let resumable = try XCTUnwrap(controller.current)
                try await self.finished(controller) { controller.resume(resumable, answer: "Keep it", store: store, provider: provider) }
                XCTAssertNil(controller.issue); XCTAssertNil(controller.current?.run.question)
                XCTAssertTrue(controller.current?.run.messages.contains { $0.content == "Answer to your question: Keep it" } == true)
                XCTAssertEqual(try Data(contentsOf: target), source)
            }
        }
    }
    func testWebRunStoppedBeforeItsFirstRequestContinuesItsSavedObjective() async throws {
        try await fixture { root, workspace, controller, store, provider, route in
            let io = try XCTUnwrap(workspace.io)
            let chat = try await io.createConversation(device: .init(id: "fixture-owner", name: "Migration Mac"), text: "Continue the saved run", scope: Data(#"{"kind":"vault"}"#.utf8))
            let web: [String: Any] = ["version": 1, "id": "unstarted-web-run", "chatId": chat.conversation.id, "ownerId": "old-web-owner", "objective": "Explain the distinct original objective from the saved web run.", "mode": "ask", "readIds": ["alpha"], "writeIds": [], "createTypes": [], "scopeKey": #"{"kind":"vault"}"#, "status": "running", "plan": [], "proposals": [], "receipts": [], "events": [], "messages": [], "usage": ["inputTokens": 0, "outputTokens": 0, "steps": 0, "elapsedMs": 0], "updatedAt": "2026-11-19T12:00:00Z"]
            let source = try JSONSerialization.data(withJSONObject: web, options: [.sortedKeys])
            let path = ".zerus/ai/runs/" + chat.conversation.id + "/unstarted-web-run.json", target = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); try source.write(to: target)
            let prepared = try await controller.workspace.prepareWebMigration(path: path, binding: provider.binding)
            XCTAssertEqual(prepared.record.run.messages.first?.role, "user")
            XCTAssertEqual(prepared.record.run.messages.first?.content, "Explain the distinct original objective from the saved web run.")
            try await controller.importWebMigration(prepared, store: store)
            XCTAssertNil(ChatHTTPFixture.captured(route))
            let imported = try XCTUnwrap(controller.current)
            ChatHTTPFixture.register(try self.answer("Continued the saved objective."), path: route)
            try await self.finished(controller) { controller.resume(imported, store: store, provider: provider) }
            XCTAssertNil(controller.issue)
            let request = try self.requestObject(XCTUnwrap(ChatHTTPFixture.captured(route)))
            XCTAssertTrue(String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self).contains("Explain the distinct original objective from the saved web run."))
            XCTAssertEqual(try Data(contentsOf: target), source)
        }
    }
    func testOrganizationNativeAndFallbackCallsWaitForReviewThenResumeAndUndo() async throws {
        for fallback in [false, true] {
            try await fixture { root, workspace, controller, store, provider, route in
                if fallback {
                    let saved = try await controller.workspace.preferences(); var value = saved.value; value.textFallback = true
                    _ = try await controller.workspace.savePreferences(value, expected: saved)
                }
                let args: [String: Any] = ["selector": "alpha", "revision": NativeAgentNote.hash(self.alpha), "typePath": ["Filed"]]
                let organize: ChatHTTPFixture.Script, read: ChatHTTPFixture.Script
                if fallback {
                    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["name": "note_organize", "arguments": args]), as: UTF8.self)
                    organize = try self.textReply("<zerus_tool>" + json + "</zerus_tool>")
                    read = try self.textReply("<note_get>alpha</note_get>", next: organize)
                } else { organize = try self.call("organize", "note_organize", args); read = try self.call("read", "note_get", ["selector": "alpha"], next: organize) }
                ChatHTTPFixture.register(read, path: route)
                try await self.finished(controller) { controller.start(prompt: "File Alpha", mode: .review, scope: .init(paths: ["Alpha.md"], organizationFolder: "Filed", allowOrganizationMoves: true), chatID: "organization-controller", store: store, provider: provider) }
                XCTAssertNil(controller.issue); XCTAssertNotNil(controller.current?.run.pending.first?.organization)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Alpha.md")), Data(self.alpha.utf8))
                let review = try XCTUnwrap(controller.review)
                try await controller.approve(review)
                XCTAssertEqual(workspace.selection, "Filed/Alpha.md"); XCTAssertNil(workspace.noteDiskChange)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Filed/Alpha.md")), Data(self.alpha.utf8))
                ChatHTTPFixture.register(try self.answer("Filed with a verified receipt."), path: route)
                let approved = try XCTUnwrap(controller.current)
                try await self.finished(controller) { controller.resume(approved, store: store, provider: provider) }
                XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Filed with a verified receipt.")
                try await controller.reviewUndo(XCTUnwrap(controller.current?.run.receipts.first).id)
                try await controller.approve(XCTUnwrap(controller.review))
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Alpha.md")), Data(self.alpha.utf8)); XCTAssertEqual(workspace.selection, "Alpha.md")
            }
        }
    }

    func testEditModeSavesAPinButRequiresReviewForTrash() async throws {
        for trash in [false, true] {
            try await fixture { root, _, controller, store, provider, route in
                let organize = try self.call("organize", "note_organize", ["selector": "alpha", "revision": NativeAgentNote.hash(self.alpha), trash ? "trash" : "pinned": true], next: self.answer("Saved with a verified receipt."))
                ChatHTTPFixture.register(try self.call("read", "note_get", ["selector": "alpha"], next: organize), path: route)
                try await self.finished(controller) { controller.start(prompt: trash ? "Trash Alpha" : "Pin Alpha", mode: .edit, scope: .init(paths: ["Alpha.md"]), chatID: "organization-controller", store: store, provider: provider) }
                XCTAssertNil(controller.issue)
                if trash {
                    XCTAssertNotNil(controller.review); XCTAssertTrue(controller.current?.run.receipts.isEmpty == true)
                    XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), self.alpha)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".trash/Alpha.md").path))
                } else {
                    XCTAssertNil(controller.review); XCTAssertEqual(controller.current?.run.receipts.count, 1)
                    let saved = NoteDocument(path: "Alpha.md", content: try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), modified: .distantPast)
                    XCTAssertTrue(saved.pinned); XCTAssertEqual(saved.parts.body, NoteDocument(path: "Alpha.md", content: self.alpha, modified: .distantPast).parts.body)
                }
            }
        }
    }

    func testUnsupportedWorkerReplyBecomesPartialWithoutStoppingTheParent() async throws {
        try await fixture { _, _, controller, store, provider, route in
            let saved = try await controller.workspace.preferences(); var value = saved.value; value.workers = true
            _ = try await controller.workspace.savePreferences(value, expected: saved)
            let tooManyCalls = (0..<13).map { self.function("oversized-batch-\($0)", "note_get", ["selector": "alpha"]) }
            let worker = try self.calls(tooManyCalls, next: self.textReply("Independent check.", next: self.answer("Final answer after refused worker reply.")))
            ChatHTTPFixture.register(try self.call("analysis-invalid", "analyze_notes", ["question": "Check", "selectors": ["alpha"]], next: worker), path: route)
            try await self.finished(controller) { controller.start(prompt: "Check Alpha", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "analysis-invalid", store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Final answer after refused worker reply.")
            let result = try XCTUnwrap(controller.current?.run.messages.first { $0.toolCallId == "analysis-invalid" })
            XCTAssertTrue(result.content.contains("Analysis interrupted")); XCTAssertTrue(result.content.contains("unsupported agent calls"), result.content)
            XCTAssertTrue(controller.current?.run.reads.isEmpty == true); XCTAssertNil(controller.current?.run.requestReservation)
        }
    }

    func testAnalysisLeavesAParentStepForSynthesisWhenWorkersReachTheLimit() async throws {
        try await fixture { _, _, controller, store, provider, route in
            let saved = try await controller.workspace.preferences(); var preferences = saved.value; preferences.workers = true
            _ = try await controller.workspace.savePreferences(preferences, expected: saved)
            let snapshot = try await controller.workspace.limits(); var limits = snapshot.limits; limits.maxSteps = 4
            _ = try await controller.workspace.saveLimits(limits, expected: snapshot)
            let final = try self.answer("Synthesis after bounded analysis.")
            let secondRead = try self.call("read-two", "note_get", ["selector": "alpha"], next: final)
            let firstRead = try self.call("read-one", "note_get", ["selector": "alpha"], next: secondRead)
            ChatHTTPFixture.register(try self.call("analysis-budget", "analyze_notes", ["question": "Check", "selectors": ["alpha"]], next: firstRead), path: route)
            try await self.finished(controller) { controller.start(prompt: "Check Alpha", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "analysis-budget", store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Synthesis after bounded analysis.")
            XCTAssertEqual(controller.current?.run.steps, 4); XCTAssertEqual(controller.current?.run.status, "complete")
            XCTAssertTrue(controller.current?.run.messages.contains { $0.toolCallId == "analysis-budget" && $0.content.contains("Analysis interrupted") } == true)
        }
    }

    func testWorkerTimeoutProducesAPartialResultAndContinuesTheParent() async throws {
        try await fixture { _, _, controller, store, provider, route in
            let preferences = try await controller.workspace.preferences(); var value = preferences.value; value.workers = true
            _ = try await controller.workspace.savePreferences(value, expected: preferences)
            var record = try await controller.workspace.start(objective: "Check Alpha", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "analysis-deadline")
            record = try await controller.workspace.bindProvider(record, binding: provider.binding)
            let call = NativeAgentCall(id: "analysis-timeout", name: "analyze_notes", arguments: #"{"question":"Check","selectors":["alpha"]}"#)
            record = try await controller.workspace.response(record, content: "", calls: [call], input: 10, output: 5, seconds: 0)
            record = try await controller.workspace.beginAnalysis(record, call: call)
            record = try await controller.workspace.reserveAnalysis(record, index: 0, input: 10, output: 10)
            record = try await controller.workspace.elapsed(record, seconds: 179.8)
            record = try await controller.workspace.pause(record, reason: "Previously stopped near the worker deadline")
            let worker = ChatHTTPFixture.Script(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Partial\"}}]}\n\n", remaining: [], paused: true, next: try self.textReply("Second worker finished.", next: self.answer("Synthesis despite worker timeout.")))
            ChatHTTPFixture.register(worker, path: route)
            let paused = record
            try await self.finished(controller) { controller.resume(paused, store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Synthesis despite worker timeout.")
            XCTAssertEqual(controller.current?.run.status, "complete")
            XCTAssertTrue(controller.current?.run.messages.contains { $0.toolCallId == call.id && $0.content.contains("time limit") } == true)
        }
    }

    func testLargeAnalysisAnswersBecomeBoundedPartialResultsInsteadOfBlockingSynthesis() async throws {
        try await fixture { _, _, controller, store, provider, route in
            let preferences = try await controller.workspace.preferences(); var value = preferences.value; value.workers = true
            _ = try await controller.workspace.savePreferences(value, expected: preferences)
            let large = String(repeating: "Evidence ", count: 30_000)
            let second = try self.textReply(large, next: self.answer("Synthesis of bounded evidence."))
            let first = try self.textReply(large, next: second)
            ChatHTTPFixture.register(try self.call("analysis-large", "analyze_notes", ["question": "Check", "selectors": ["alpha"]], next: first), path: route)
            try await self.finished(controller) { controller.start(prompt: "Check Alpha", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "analysis-large", store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Synthesis of bounded evidence.")
            let result = try XCTUnwrap(controller.current?.run.messages.first { $0.toolCallId == "analysis-large" })
            XCTAssertLessThan(result.content.utf8.count, 100_000)
            XCTAssertTrue(result.content.contains("truncated"), "Truncation must be disclosed to the parent")
        }
    }

    func testIndependentAnalysisKeepsScopedReadOnlyChildrenAndDurableCompletedWork() async throws {
        try await fixture { root, _, controller, store, provider, route in
            let settings = try await controller.workspace.preferences(); var preferences = settings.value; preferences.workers = true
            _ = try await controller.workspace.savePreferences(preferences, expected: settings)
            let firstAnswer = try self.answer("Support from Alpha.")
            let firstRead = try self.call("worker-read", "note_get", ["selector": "alpha"], next: firstAnswer)
            ChatHTTPFixture.register(try self.call("analysis", "analyze_notes", ["question": "Check the evidence", "selectors": ["alpha"]], next: firstRead), path: route)
            var stoppedAfterFirst = false, secondWorkerErrors: [String] = []
            let observer = controller.$current.compactMap { $0 }.sink { record in
                if let state = try? MacAgentAnalysisState.read(record), state.children[1].status == "complete" {
                    secondWorkerErrors = state.children[1].messages.filter { $0.role == "tool" }.map(\.content)
                }
                if !stoppedAfterFirst, let state = try? MacAgentAnalysisState.read(record), state.children.first?.status == "complete" {
                    stoppedAfterFirst = true; controller.stop()
                }
            }
            try await self.finished(controller) { controller.start(prompt: "Analyze Alpha", mode: .review, scope: .init(paths: ["Alpha.md"]), chatID: "analysis-fixture", store: store, provider: provider) }
            withExtendedLifetime(observer) {}
            XCTAssertTrue(stoppedAfterFirst); XCTAssertEqual(controller.current?.run.status, "interrupted")
            let paused = try XCTUnwrap(controller.current), state = try XCTUnwrap(MacAgentAnalysisState.read(paused))
            XCTAssertEqual(state.children[0].messages.last?.content, "Support from Alpha."); XCTAssertEqual(state.next, 1)
            XCTAssertEqual(paused.run.steps, 3); XCTAssertEqual(paused.run.inputTokens, 30); XCTAssertEqual(paused.run.outputTokens, 15)
            XCTAssertTrue(paused.run.reads.isEmpty, "Worker reads cannot authorize a parent write")
            let forbidden = try self.call("worker-write", "note_append", ["selector": "alpha", "revision": NativeAgentNote.hash(self.alpha), "text": "Must not save"], next: self.call("worker-outside", "note_get", ["selector": "beta"], next: self.textReply("Missing evidence.", next: self.answer("Synthesis."))))
            ChatHTTPFixture.register(forbidden, path: route)
            try await self.finished(controller) { controller.resume(paused, store: store, provider: provider) }
            withExtendedLifetime(observer) {}
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Synthesis.")
            let completed = try XCTUnwrap(controller.current)
            XCTAssertEqual(completed.run.steps, 7); XCTAssertEqual(completed.run.inputTokens, 70); XCTAssertEqual(completed.run.outputTokens, 35)
            XCTAssertNil(try MacAgentAnalysisState.read(completed)); XCTAssertTrue(completed.run.proposals.isEmpty); XCTAssertTrue(completed.run.reads.isEmpty)
            let result = try XCTUnwrap(completed.run.messages.first { $0.toolCallId == "analysis" })
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
            XCTAssertEqual(object["analyses"] as? [String], ["Support from Alpha.", "Missing evidence."]); XCTAssertEqual(object["trusted"] as? Bool, false)
            XCTAssertTrue(secondWorkerErrors.contains { $0.contains("No mutation or nested worker was executed") })
            XCTAssertTrue(secondWorkerErrors.contains { $0.contains("outside the chosen context") })
            XCTAssertFalse(secondWorkerErrors.joined().contains("Second note."))
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), self.alpha)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Beta.md"), encoding: .utf8), self.beta)
        }
    }

    func testStoppingAnAnalysisRequestSettlesItsAllowanceAndResumesItsSavedChildren() async throws {
        try await fixture { _, _, controller, store, provider, route in
            let saved = try await controller.workspace.preferences(); var preferences = saved.value; preferences.workers = true
            _ = try await controller.workspace.savePreferences(preferences, expected: saved)
            let sent = self.expectation(description: "worker transport began")
            let worker = ChatHTTPFixture.Script(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Partial worker\"}}]}\n\n", remaining: [], paused: true, onStart: { sent.fulfill() })
            ChatHTTPFixture.register(try self.call("analysis-stop", "analyze_notes", ["question": "Check", "selectors": ["alpha"]], next: worker), path: route)
            XCTAssertTrue(controller.start(prompt: "Check Alpha", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "analysis-stop", store: store, provider: provider))
            await self.fulfillment(of: [sent], timeout: 5)
            let active = try XCTUnwrap(controller.current), reservation = try XCTUnwrap(active.run.requestReservation)
            let ids = try XCTUnwrap(MacAgentAnalysisState.read(active)).children.map(\.id)
            let stopped = await controller.stopAndCheckpoint(); XCTAssertTrue(stopped)
            let paused = try XCTUnwrap(controller.current)
            XCTAssertNil(paused.run.requestReservation); XCTAssertEqual(paused.run.inputTokens, 10 + reservation.input); XCTAssertEqual(paused.run.outputTokens, 5 + reservation.output)
            XCTAssertEqual(try MacAgentAnalysisState.read(paused)?.children.map(\.id), ids)
            ChatHTTPFixture.register(try self.textReply("First analysis", next: self.textReply("Second analysis", next: self.answer("Final synthesis"))), path: route)
            try await self.finished(controller) { controller.resume(paused, store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Final synthesis")
            XCTAssertEqual(controller.current?.run.steps, 5)
            XCTAssertEqual(controller.current?.run.inputTokens, 40 + reservation.input); XCTAssertEqual(controller.current?.run.outputTokens, 20 + reservation.output)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(controller.current).bytes) as? [String: Any])
            let history = try XCTUnwrap(object["macAnalysisHistory"] as? [[String: Any]])
            let children = try XCTUnwrap(history.first?["children"] as? [[String: Any]])
            XCTAssertEqual(children[0]["steps"] as? Int, 2, "An interrupted paid request counts toward the worker's limit too")
            XCTAssertEqual(children[0]["inputTokens"] as? Int, 10 + reservation.input)
            XCTAssertEqual(children[0]["outputTokens"] as? Int, 5 + reservation.output)
        }
    }

    func testIndependentAnalysisRefusesDisabledOrOutsideSelectorsBeforeWorkerRequests() async throws {
        for variant in ["disabled", "outside", "budget", "tokens"] {
            try await fixture { _, _, controller, store, provider, route in
                if variant != "disabled" {
                    let saved = try await controller.workspace.preferences(); var preferences = saved.value; preferences.workers = true
                    _ = try await controller.workspace.savePreferences(preferences, expected: saved)
                }
                if variant == "budget" {
                    let saved = try await controller.workspace.limits(); var limits = saved.limits; limits.maxSteps = 2
                    _ = try await controller.workspace.saveLimits(limits, expected: saved)
                }
                if variant == "tokens" {
                    let saved = try await controller.workspace.limits(); var limits = saved.limits; limits.maxTotalTokens = 24_000; limits.maxInputTokens = 16_000; limits.maxOutputTokens = 1024
                    _ = try await controller.workspace.saveLimits(limits, expected: saved)
                }
                ChatHTTPFixture.register(try self.call("analysis-denied", "analyze_notes", ["question": "Check", "selectors": [variant == "outside" ? "beta" : "alpha"]], next: self.answer("No analysis available.")), path: route)
                try await self.finished(controller) { controller.start(prompt: "Check", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "analysis-refusal", store: store, provider: provider) }
                XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.steps, 2)
                let result = try XCTUnwrap(controller.current?.run.messages.first { $0.toolCallId == "analysis-denied" })
                XCTAssertTrue(result.content.contains(variant == "outside" ? "outside the chosen context" : ["budget", "tokens"].contains(variant) ? "Insufficient remaining token or step budget" : "Enable independent analysis workers"), result.content)
                XCTAssertNil(try MacAgentAnalysisState.read(XCTUnwrap(controller.current)))
            }
        }
    }

    func testGrowingWorkerTranscriptBecomesPartialAndStillAllowsSynthesis() async throws {
        try await fixture { root, _, controller, store, provider, route in
            try Data(("---\nzerus-id: beta\n---\n# Beta\n\n" + String(repeating: "漢", count: 40_000)).utf8).write(to: root.appendingPathComponent("Beta.md"))
            let preferences = try await controller.workspace.preferences(); var value = preferences.value; value.workers = true
            _ = try await controller.workspace.savePreferences(value, expected: preferences)
            let snapshot = try await controller.workspace.limits(); var limits = snapshot.limits; limits.maxInputTokens = 200_000; limits.maxTotalTokens = 1_000_000
            _ = try await controller.workspace.saveLimits(limits, expected: snapshot)
            let final = try self.textReply("Second worker completed.", next: self.answer("Synthesis after storage limit."))
            let batch = (0..<12).map { self.function("read-\($0)", "note_get", ["selector": "beta", "length": 32_000]) }
            let script = try self.calls(batch, next: final)
            ChatHTTPFixture.register(try self.call("analysis-storage", "analyze_notes", ["question": "Inspect evidence", "selectors": ["beta"]], next: script), path: route)
            try await self.finished(controller) { controller.start(prompt: "Inspect Beta", mode: .ask, scope: .init(paths: ["Beta.md"]), chatID: "analysis-storage", store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Synthesis after storage limit.")
            let record = try XCTUnwrap(controller.current), result = try XCTUnwrap(record.run.messages.first { $0.toolCallId == "analysis-storage" })
            XCTAssertTrue(result.content.contains("storage limit"), result.content)
            XCTAssertLessThan(record.bytes.count, 4_000_000)
            XCTAssertNil(try MacAgentAnalysisState.read(record))
        }
    }

    func testIndependentAnalysisSupportsTextFallbackAndSeparateAnthropicContinuations() async throws {
        for anthropic in [false, true] {
            try await fixture { _, _, controller, store, provider, route in
                let settings = try await controller.workspace.preferences(); var preferences = settings.value; preferences.workers = true; preferences.textFallback = true
                _ = try await controller.workspace.savePreferences(preferences, expected: settings)
                let connection = anthropic ? MacAgentProvider.api(profile: .init(provider: .anthropic, endpoint: "https://fixture.invalid" + route, model: "fixture-model"), key: "synthetic-key") : provider
                let analyze = #"<zerus_tool>{"name":"analyze_notes","arguments":{"question":"Compare evidence","selectors":["alpha"]}}</zerus_tool>"#
                let end = try self.textReply("Final synthesis.", anthropic: anthropic)
                let second = try self.textReply("Independent check.", anthropic: anthropic, next: end)
                let support = try self.textReply("Support.", anthropic: anthropic, next: second)
                let read = try self.textReply("<note_get>alpha</note_get>", anthropic: anthropic, thinking: anthropic, next: support)
                ChatHTTPFixture.register(try self.textReply(analyze, anthropic: anthropic, thinking: anthropic, next: read), path: route)
                try await self.finished(controller) { controller.start(prompt: "Compare Alpha", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "analysis-fallback", store: store, provider: connection) }
                XCTAssertNil(controller.issue); XCTAssertEqual(controller.live, "Final synthesis."); XCTAssertEqual(controller.current?.run.steps, 5)
                let current = try XCTUnwrap(controller.current), raw = try XCTUnwrap(JSONSerialization.jsonObject(with: current.bytes) as? [String: Any])
                let archive = try XCTUnwrap(raw["macAnalysisHistory"] as? [[String: Any]]), children = try XCTUnwrap(archive.first?["children"] as? [[String: Any]])
                let firstMessages = try XCTUnwrap(children[0]["messages"] as? [[String: Any]])
                XCTAssertTrue(firstMessages.contains { $0["textToolSource"] as? String == "<note_get>alpha</note_get>" })
                XCTAssertTrue(current.run.reads.isEmpty)
                let request = try self.requestObject(XCTUnwrap(ChatHTTPFixture.captured(route)))
                XCTAssertNil(request["tools"])
                if anthropic {
                    for child in children {
                        let id = try XCTUnwrap((child["id"] as? String).flatMap(UUID.init(uuidString:)))
                        let cache = controller.workspace.continuations.bound(endpoint: "https://fixture.invalid" + route, model: "fixture-model", apiKey: "synthetic-key", run: id)
                        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory.path), "Completed child continuations should be cleaned up")
                    }
                }
            }
        }
    }

    private let alpha = "---\nzerus-id: alpha\n---\n# Alpha\n\nOriginal writing.\n"
    private let beta = "---\nzerus-id: beta\n---\n# Beta\n\nSecond note.\n"
    func testReviewLoopStagesWithoutSavingThenApprovalAndResumeKeepTheBinding() async throws {
        try await fixture { root, workspace, controller, store, provider, route in
            let preview = try self.call("preview", "preview_changes", [:])
            let append = try self.call("append", "note_append", ["selector": "alpha", "revision": NativeAgentNote.hash(self.alpha), "text": "Approved addition."], next: preview)
            ChatHTTPFixture.register(try self.call("read", "note_get", ["selector": "alpha"], next: append), path: route)
            try await self.finished(controller) { controller.start(prompt: "Append a paragraph", mode: .review, scope: .init(paths: ["Alpha.md"], currentWritePath: "Alpha.md"), chatID: "fixture", store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.pending.count, 1)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), self.alpha, "Review must not save model proposals")
            let prepared = try XCTUnwrap(controller.review), saved = try XCTUnwrap(controller.current)
            let journal = root.appendingPathComponent(NativeAgentJournal.path(saved.id))
            var peer = try XCTUnwrap(JSONSerialization.jsonObject(with: saved.bytes) as? [String: Any]); peer["externalField"] = "peer update"
            let peerBytes = try JSONSerialization.data(withJSONObject: peer); try peerBytes.write(to: journal)
            do { try await controller.approve(prepared); XCTFail("A stale approval cannot overwrite a changed run journal") }
            catch { XCTAssertTrue(error.localizedDescription.contains("run changed"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: journal), peerBytes)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), self.alpha)
            try saved.bytes.write(to: journal)
            try await controller.approve(prepared)
            XCTAssertTrue(workspace.body.contains("Approved addition.")); XCTAssertEqual(controller.current?.run.receipts.count, 1)
            let record = try XCTUnwrap(controller.current), binding = try XCTUnwrap(MacAgentProviderBinding.read(record))
            XCTAssertEqual(binding.model, "fixture-model"); XCTAssertFalse(String(decoding: record.bytes, as: UTF8.self).contains("synthetic-key"))
            ChatHTTPFixture.register(try self.answer("Finished."), path: route)
            try await self.finished(controller) { controller.resume(record, store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.status, "complete"); XCTAssertEqual(controller.live, "Finished.")
            XCTAssertEqual(try MacAgentProviderBinding.read(XCTUnwrap(controller.current)), binding)
            let beforeUndo = try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8)
            let receipt = try XCTUnwrap(controller.current?.run.receipts.first)
            try await controller.reviewUndo(receipt.id)
            let undo = try XCTUnwrap(controller.review)
            XCTAssertEqual(undo.label, "Undo verified changes")
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), beforeUndo, "Reviewing Undo must not save yet")
            try await controller.approve(undo)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), self.alpha)
            XCTAssertNotNil(controller.current?.run.receipts.first?.undoneAt)
        }
    }
    func testTextFallbackCallsUseReviewAndPreserveProviderContinuations() async throws {
        for anthropic in [false, true] {
            try await fixture { root, _, controller, store, provider, route in
                let saved = try await controller.workspace.preferences(); var preferences = saved.value; preferences.textFallback = true
                _ = try await controller.workspace.savePreferences(preferences, expected: saved)
                let connection = anthropic ? MacAgentProvider.api(profile: .init(provider: .anthropic, endpoint: "https://fixture.invalid" + route, model: "fixture-model"), key: "synthetic-key") : provider
                let read = #"<zerus_tool>{"name":"note_get","arguments":{"selector":"alpha"}}</zerus_tool>"#
                let append = "<note_append>Fallback addition.</note_append>", preview = #"<zerus_tool>{"name":"preview_changes","arguments":{}}</zerus_tool>"#
                ChatHTTPFixture.register(try self.textReply(read, anthropic: anthropic, thinking: anthropic, next: self.textReply(append, anthropic: anthropic, next: self.textReply(preview, anthropic: anthropic))), path: route)
                try await self.finished(controller) { controller.start(prompt: "Append a paragraph", mode: .review, scope: .init(paths: ["Alpha.md"], currentReadPath: "Alpha.md"), chatID: "fallback-fixture", store: store, provider: connection) }
                XCTAssertNil(controller.issue)
                let record = try XCTUnwrap(controller.current), review = try XCTUnwrap(controller.review)
                XCTAssertEqual(record.run.pending.count, 1); XCTAssertEqual(record.run.messages.compactMap(\.textToolSource), [read, append, preview])
                XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), self.alpha)
                let request = try self.requestObject(XCTUnwrap(ChatHTTPFixture.captured(route)))
                XCTAssertNil(request["tools"], "Text-only requests must not offer native tool definitions")
                let messages = try XCTUnwrap(request["messages"] as? [[String: Any]])
                if anthropic {
                    let parts = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                    XCTAssertTrue(parts.contains { $0["type"] as? String == "thinking" && $0["signature"] as? String == "signed-fallback-fixture" })
                    XCTAssertFalse(parts.contains { ["tool_use", "tool_result"].contains($0["type"] as? String ?? "") })
                } else { XCTAssertFalse(messages.contains { $0["tool_calls"] != nil || $0["role"] as? String == "tool" }) }
                try await controller.approve(review)
                XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8).contains("Fallback addition."))
                let currentSettings = try await controller.workspace.preferences(); _ = try await controller.workspace.savePreferences(.init(), expected: currentSettings)
                ChatHTTPFixture.register(try self.textReply("Applied with a verified receipt.", anthropic: anthropic), path: route)
                try await self.finished(controller) { controller.resume(controller.current!, store: store, provider: connection) }
                XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.status, "complete")
                XCTAssertEqual(controller.current?.run.preferences?.textFallback, true, "A changed default must not change an existing run's transport protocol")
                _ = try NativeAgentJournal.decode(XCTUnwrap(controller.current).bytes, id: XCTUnwrap(controller.current).id)
            }
        }
    }

    func testTextFallbackOptInRefusesAmbiguousCallsAndKeepsReportedUsage() async throws {
        for variant in ["disabled", "literal", "inline-literal", "malformed", "trailing-newline", "multiline", "inline-prose", "multiple", "mixed", "native-only"] {
            try await fixture { root, _, controller, store, provider, route in
                if variant != "disabled" { let saved = try await controller.workspace.preferences(); var value = saved.value; value.textFallback = true; _ = try await controller.workspace.savePreferences(value, expected: saved) }
                let tag = #"<zerus_tool>{"name":"note_list","arguments":{}}</zerus_tool>"#
                let raw: String
                switch variant {
                case "literal": raw = "Example:\n```xml\n" + tag + "\n```"
                case "inline-literal": raw = "Use the `<note_get>` tag as an example."
                case "malformed": raw = "<zerus_tool>{"
                case "trailing-newline": raw = "Before\n<zerus_tool>{\"name\":\"note_get\"}\n"
                case "multiline": raw = "<zerus_tool>\n{\n  \"name\": \"note_get\"\n}\n"
                case "inline-prose": raw = "Let me read it: " + tag
                case "multiple": raw = tag + "\n" + tag
                case "native-only": raw = ""
                default: raw = tag
                }
                if variant == "mixed" || variant == "native-only" {
                    let wire: [String: Any] = ["choices": [["delta": ["content": raw, "tool_calls": [["index": 0, "id": "native-call", "type": "function", "function": ["name": "note_list", "arguments": "{}"]]]], "finish_reason": "tool_calls"]], "usage": ["prompt_tokens": 7, "completion_tokens": 11]]
                    ChatHTTPFixture.register(.init(first: "data: " + String(decoding: try JSONSerialization.data(withJSONObject: wire), as: UTF8.self) + "\n\ndata: [DONE]\n\n", remaining: []), path: route)
                } else { ChatHTTPFixture.register(try self.textReply(raw, input: 7, output: 11), path: route) }
                try await self.finished(controller) { controller.start(prompt: "Check the supplied example", mode: .edit, scope: .init(paths: ["Alpha.md"], currentReadPath: "Alpha.md"), chatID: "fallback-refusal", store: store, provider: provider) }
                let record = try XCTUnwrap(controller.current)
                XCTAssertTrue(record.run.messages.flatMap { $0.toolCalls ?? [] }.isEmpty, variant)
                XCTAssertTrue(record.run.messages.filter { $0.role == "tool" }.isEmpty, variant)
                XCTAssertTrue(record.run.proposals.isEmpty); XCTAssertEqual(record.run.inputTokens, 7); XCTAssertEqual(record.run.outputTokens, 11)
                XCTAssertEqual(record.run.steps, 1); XCTAssertNil(record.run.requestReservation)
                if ["disabled", "literal", "inline-literal"].contains(variant) { XCTAssertNil(controller.issue); XCTAssertEqual(record.run.status, "complete"); XCTAssertEqual(controller.live, raw) }
                else { XCTAssertTrue(controller.issue?.contains("text tool call") == true, controller.issue ?? "Missing refusal"); XCTAssertEqual(record.run.status, "interrupted"); XCTAssertTrue(record.run.messages.last?.content.contains("no tool from the previous reply was executed") == true) }
                XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), self.alpha)
                _ = try NativeAgentJournal.decode(record.bytes, id: record.id)
            }
        }
    }

    func testDeletingRunKeepsAppliedNotesAndRefusesStaleJournal() async throws {
        try await fixture { root, _, controller, store, provider, route in
            let final = try self.answer("Saved."), append = try self.call("append", "note_append", ["selector": "alpha", "revision": NativeAgentNote.hash(self.alpha), "text": "Keep this applied addition."], next: final)
            ChatHTTPFixture.register(try self.call("read", "note_get", ["selector": "alpha"], next: append), path: route)
            try await self.finished(controller) { controller.start(prompt: "Append", mode: .edit, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
            let record = try XCTUnwrap(controller.current), journal = root.appendingPathComponent(NativeAgentJournal.path(record.id)), note = try Data(contentsOf: root.appendingPathComponent("Alpha.md"))
            XCTAssertTrue(String(decoding: note, as: UTF8.self).contains("Keep this applied addition."))
            var external = try XCTUnwrap(JSONSerialization.jsonObject(with: record.bytes) as? [String: Any]); external["external"] = true
            let bytes = try JSONSerialization.data(withJSONObject: external); try bytes.write(to: journal)
            do { try await controller.deleteCurrent(); XCTFail("Stale delete must not remove an updated journal") }
            catch { XCTAssertTrue(error.localizedDescription.contains("run changed"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: journal), bytes)
            try await controller.open(NativeAgentJournal.decode(bytes, id: record.id)); try await controller.deleteCurrent()
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path)); XCTAssertNil(controller.current)
            XCTAssertFalse(controller.records.contains { $0.id == record.id }); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Alpha.md")), note)
        }
    }

    func testDeletingRunRefusesAnActivePeerWindow() async throws {
        try await fixture { root, _, controller, store, provider, route in
            ChatHTTPFixture.register(try self.answer("Initial answer."), path: route)
            try await self.finished(controller) { controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
            let record = try await controller.workspace.pause(XCTUnwrap(controller.current), reason: "Fixture pause")
            let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote("Alpha.md")
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChatHTTPFixture.self]
            let transport = URLSession(configuration: configuration); defer { transport.invalidateAndCancel() }
            let second = try MacAgentController(workspace: peer, owner: "fixture-owner", client: .init(session: transport))
            ChatHTTPFixture.register(.init(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Peer active\"}}]}\n\n", remaining: [], paused: true), path: route)
            let shown = self.expectation(description: "peer resumed request")
            let observation = second.$live.filter { $0 == "Peer active" }.prefix(1).sink { _ in shown.fulfill() }
            XCTAssertTrue(second.resume(record, store: store, provider: provider))
            await self.fulfillment(of: [shown], timeout: 5); withExtendedLifetime(observation) {}
            let journal = root.appendingPathComponent(NativeAgentJournal.path(record.id)), bytes = try Data(contentsOf: journal)
            do { try await controller.deleteCurrent(); XCTFail("An active peer must retain its journal") }
            catch { XCTAssertTrue(error.localizedDescription.contains("Stop this run in every window"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: journal), bytes)
            _ = await second.stopAndCheckpoint(); _ = await peer.prepareToCloseWindow()
        }
    }
    func testEditSavesOneNoteAutomaticallyButSeveralNotesWaitForReview() async throws {
        for variant in ["single", "parallel", "sequential"] {
            let batch = variant == "parallel", sequential = variant == "sequential"
            try await fixture { root, _, controller, store, provider, route in
                let readCalls: [[String: Any]] = [self.function("read-a", "note_get", ["selector": "alpha"])] + (batch || sequential ? [self.function("read-b", "note_get", ["selector": "beta"])] : [])
                let writes: [[String: Any]] = [self.function("append-a", "note_append", ["selector": "alpha", "revision": NativeAgentNote.hash(self.alpha), "text": "Edit addition."])] + (batch ? [self.function("append-b", "note_append", ["selector": "beta", "revision": NativeAgentNote.hash(self.beta), "text": "Batch addition."])] : [])
                let final = try self.answer("Changes prepared.")
                let afterFirst = sequential ? try self.call("append-b", "note_append", ["selector": "beta", "revision": NativeAgentNote.hash(self.beta), "text": "Second edit."], next: final) : final
                let second = try self.calls(writes, next: afterFirst)
                ChatHTTPFixture.register(try self.calls(readCalls, next: second), path: route)
                try await self.finished(controller) { controller.start(prompt: "Append", mode: .edit, scope: .init(paths: batch || sequential ? ["Alpha.md", "Beta.md"] : ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
                XCTAssertNil(controller.issue)
                let record = try XCTUnwrap(controller.current)
                if batch {
                    XCTAssertEqual(record.run.pending.count, 2); XCTAssertTrue(record.run.receipts.isEmpty); XCTAssertNotNil(controller.review)
                    XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8), self.alpha)
                    XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Beta.md"), encoding: .utf8), self.beta)
                } else if sequential {
                    XCTAssertEqual(record.run.receipts.count, 1); XCTAssertEqual(record.run.pending.count, 1); XCTAssertNotNil(controller.review)
                    XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8).contains("Edit addition."))
                    XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Beta.md"), encoding: .utf8), self.beta, "A second note must wait even after the first note was saved in an earlier step")
                } else {
                    XCTAssertEqual(record.run.receipts.count, 1); XCTAssertTrue(record.run.pending.isEmpty); XCTAssertNil(controller.review)
                    XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Alpha.md"), encoding: .utf8).contains("Edit addition."))
                }
            }
        }
    }
    func testStopSettlesTheReservationAndResumeDoesNotRepeatCompletedTools() async throws {
        try await fixture { root, _, controller, store, provider, route in
            let partial = "data: {\"choices\":[{\"delta\":{\"content\":\"Working café\"}}]}\n\n"
            ChatHTTPFixture.register(try self.call("read", "note_get", ["selector": "alpha"], next: .init(first: partial, remaining: [], paused: true)), path: route)
            let shown = expectation(description: "second request streaming"), observation = controller.$live.filter { $0 == "Working café" }.prefix(1).sink { _ in shown.fulfill() }
            XCTAssertTrue(controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider))
            await fulfillment(of: [shown], timeout: 5); withExtendedLifetime(observation) {}
            let reserved = try XCTUnwrap(controller.current), allowance = try XCTUnwrap(reserved.run.requestReservation)
            let left = await controller.stopAndCheckpoint(); XCTAssertTrue(left)
            let paused = try XCTUnwrap(controller.current)
            XCTAssertEqual(paused.run.status, "interrupted"); XCTAssertNil(paused.run.requestReservation)
            XCTAssertEqual(paused.run.inputTokens, reserved.run.inputTokens + allowance.input)
            XCTAssertEqual(paused.run.outputTokens, reserved.run.outputTokens + allowance.output)
            let disk = try NativeAgentJournal.decode(Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(paused.id))), id: paused.id)
            XCTAssertEqual(disk.bytes, paused.bytes); XCTAssertEqual(paused.run.messages.filter { $0.role == "tool" }.count, 1)
            ChatHTTPFixture.remove(route)
            let other = MacAgentProvider.api(profile: .init(provider: .compatible, endpoint: "https://fixture.invalid" + route, model: "other-model"), key: "synthetic-key")
            try await self.finished(controller) { controller.resume(paused, store: store, provider: other) }
            XCTAssertTrue(controller.issue?.contains("selected connection or model differs") == true); XCTAssertNil(ChatHTTPFixture.captured(route))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(paused.id))), paused.bytes)
            ChatHTTPFixture.register(try self.answer("Resumed."), path: route)
            try await self.finished(controller) { controller.resume(paused, store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.status, "complete")
            XCTAssertEqual(controller.current?.run.messages.filter { $0.role == "tool" }.count, 1)
        }
    }
    func testVaultSwitchAndCloseStopAndCheckpointTheActiveProvider() async throws {
        for closing in [false, true] {
            try await fixture { root, workspace, controller, store, provider, route in
                let shown = expectation(description: "provider active"), observation = controller.$live.filter { $0 == "Working" }.prefix(1).sink { _ in shown.fulfill() }
                ChatHTTPFixture.register(.init(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Working\"}}]}\n\n", remaining: [], paused: true), path: route)
                XCTAssertTrue(controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider))
                await fulfillment(of: [shown], timeout: 5); withExtendedLifetime(observation) {}
                let old = try XCTUnwrap(controller.current), nextRoot = root.appendingPathComponent("OtherVault")
                try FileManager.default.createDirectory(at: nextRoot, withIntermediateDirectories: true)
                if closing {
                    let closed = await workspace.prepareToCloseWindow(); XCTAssertTrue(closed)
                    XCTAssertEqual(workspace.root, root); XCTAssertTrue(workspace.agentController === controller)
                } else {
                    await workspace.openVault(nextRoot)
                    XCTAssertEqual(workspace.root, nextRoot); XCTAssertNil(workspace.agentController)
                }
                XCTAssertFalse(controller.running)
                let journal = try NativeAgentJournal.decode(Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(old.id))), id: old.id)
                XCTAssertEqual(journal.run.status, "interrupted"); XCTAssertNil(journal.run.requestReservation)
                XCTAssertFalse(FileManager.default.fileExists(atPath: nextRoot.appendingPathComponent(NativeAgentJournal.directory).path))
            }
        }
    }
    func testAnthropicRefusalClearsLiveOutputAndNeverStoresAnAnswer() async throws {
        try await fixture { _, _, controller, store, _, route in
            let wire = "data: {\"type\":\"message_start\",\"message\":{\"role\":\"assistant\",\"content\":[]}}\n\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"Partial output\"}}\n\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"refusal\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"
            ChatHTTPFixture.register(.init(first: wire, remaining: []), path: route)
            let provider = MacAgentProvider.api(profile: .init(provider: .anthropic, endpoint: "https://fixture.invalid" + route, model: "claude-fixture"), key: "synthetic-key")
            try await self.finished(controller) { controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
            XCTAssertEqual(controller.live, ""); XCTAssertTrue(controller.issue?.contains("refused") == true)
            XCTAssertEqual(controller.current?.run.status, "interrupted"); XCTAssertNil(controller.current?.run.requestReservation)
            XCTAssertTrue(controller.current?.run.messages.allSatisfy { $0.role != "assistant" } == true)
        }
    }
    func testSelectedModelCapacityStopsBeforeReservingOrSending() async throws {
        try await fixture { _, _, controller, store, _, route in
            let provider = MacAgentProvider.api(profile: .init(provider: .compatible, endpoint: "https://fixture.invalid" + route, model: "small-context", contextWindow: 4096), key: "synthetic-key")
            try await self.finished(controller) { controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
            XCTAssertTrue(controller.issue?.contains("model's context capacity") == true)
            XCTAssertNil(ChatHTTPFixture.captured(route))
            let record = try XCTUnwrap(controller.current)
            XCTAssertEqual(record.run.steps, 0); XCTAssertEqual(record.run.inputTokens, 0); XCTAssertEqual(record.run.outputTokens, 0)
            XCTAssertNil(record.run.requestReservation); XCTAssertEqual(record.run.status, "interrupted")
        }
    }
    func testMissingUsageEstimatesReasoningAsWellAsVisibleText() async throws {
        try await fixture { _, _, controller, store, provider, route in
            let value: [String: Any] = ["choices": [["message": ["content": "Answer.", "reasoning_content": String(repeating: "reason ", count: 1000)], "finish_reason": "stop"]]]
            ChatHTTPFixture.register(.init(first: String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self), remaining: [], contentType: "application/json"), path: route)
            try await self.finished(controller) { controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
            XCTAssertNil(controller.issue)
            let record = try XCTUnwrap(controller.current)
            XCTAssertGreaterThanOrEqual(record.run.outputTokens, 1000, "One thousand separate reasoning words must not be accounted as only the visible short answer")
            XCTAssertGreaterThan(record.run.inputTokens, 0); XCTAssertNil(record.run.requestReservation)
            XCTAssertEqual(record.run.status, "complete")
        }
    }
    func testRestoredJournalAllowsRetryingAFailedStopAndClosing() async throws {
        try await fixture { root, _, controller, store, provider, route in
            let visible = expectation(description: "active request"), observer = controller.$live.filter { $0 == "Partial" }.prefix(1).sink { _ in visible.fulfill() }
            ChatHTTPFixture.register(.init(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Partial\"}}]}\n\n", remaining: [], paused: true), path: route)
            XCTAssertTrue(controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider))
            await fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observer) {}
            let record = try XCTUnwrap(controller.current), file = root.appendingPathComponent(NativeAgentJournal.path(record.id))
            try Data("temporarily unreadable journal".utf8).write(to: file)
            let blocked = await controller.prepareToLeave(); XCTAssertFalse(blocked); XCTAssertTrue(controller.hasUnsavedState)
            try record.bytes.write(to: file)
            let recovered = await controller.prepareToLeave()
            XCTAssertTrue(recovered, "A restored journal must not require force-quitting the app")
            XCTAssertFalse(controller.hasUnsavedState)
            let saved = try NativeAgentJournal.decode(Data(contentsOf: file), id: record.id)
            XCTAssertEqual(saved.run.status, "interrupted"); XCTAssertNil(saved.run.requestReservation)
        }
    }
    func testResumeCannotStartDuringVaultTransitionOrAfterClosePreparation() async throws {
        try await fixture { _, workspace, controller, store, provider, route in
            ChatHTTPFixture.register(try self.answer("First."), path: route)
            try await self.finished(controller) { controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
            let record = try XCTUnwrap(controller.current)
            ChatHTTPFixture.remove(route); ChatHTTPFixture.register(try self.answer("Must not send."), path: route)
            workspace.busy = true
            let accepted = controller.resume(record, store: store, provider: provider)
            XCTAssertFalse(accepted)
            if accepted {
                let done = expectation(description: "unexpected resume stopped"), observer = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
                await fulfillment(of: [done], timeout: 5); withExtendedLifetime(observer) {}
            }
            workspace.busy = false
            XCTAssertNil(ChatHTTPFixture.captured(route))
            ChatHTTPFixture.remove(route)
            let closed = await workspace.prepareToCloseWindow(); XCTAssertTrue(closed)
            XCTAssertFalse(controller.resume(record, store: store, provider: provider), "Close preparation must hold off another paid request")
            XCTAssertNil(ChatHTTPFixture.captured(route))
        }
    }
    func testReplacedControllerCannotRunOutsideTheWindowLifecycle() async throws {
        try await fixture { _, workspace, controller, store, provider, route in
            let replacement = try MacAgentController(workspace: workspace, owner: "fixture-owner")
            ChatHTTPFixture.register(.init(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Old\"}}]}\n\n", remaining: [], paused: true), path: route)
            let accepted = controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider)
            XCTAssertFalse(accepted)
            if accepted {
                let visible = expectation(description: "unexpected old request"), observer = controller.$live.filter { $0 == "Old" }.prefix(1).sink { _ in visible.fulfill() }
                await fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observer) {}
            }
            let closed = await workspace.prepareToCloseWindow(); XCTAssertTrue(closed)
            XCTAssertFalse(controller.running); XCTAssertTrue(workspace.agentController === replacement)
        }
    }
    func testExplicitConnectionChoiceRepairsAnUnreadableProviderBinding() async throws {
        try await fixture { root, _, controller, store, provider, route in
            ChatHTTPFixture.register(try self.answer("First."), path: route)
            try await self.finished(controller) { controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
            let before = try XCTUnwrap(controller.current)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: before.bytes) as? [String: Any])
            object["macProvider"] = ["version": 2, "future": "provider"]
            let bytes = try JSONSerialization.data(withJSONObject: object)
            try bytes.write(to: root.appendingPathComponent(NativeAgentJournal.path(before.id)))
            let updated = try NativeAgentJournal.decode(bytes, id: before.id)
            ChatHTTPFixture.register(try self.answer("Rebound."), path: route)
            try await self.finished(controller) { controller.resume(updated, useSelectedConnection: true, store: store, provider: provider) }
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.status, "complete")
            XCTAssertEqual(try MacAgentProviderBinding.read(XCTUnwrap(controller.current))?.version, 1)
        }
    }
    func testDeadlineDoesNotReplaceTheNextRequestsCredentialError() async throws {
        try await fixture { root, _, controller, store, provider, route in
            let io = VaultFiles(root: root), settings = try await io.agentLimits()
            var limits = settings.limits; limits.maxMinutes = 1
            _ = try await io.saveAgentLimits(limits, expected: settings)
            var record = try await io.agentStart(objective: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "deadline-fixture", owner: "fixture-owner")
            record = try await controller.workspace.bindProvider(record, binding: provider.binding)
            record = try await io.agentElapsed(record, owner: "fixture-owner", seconds: 59.99)
            ChatHTTPFixture.register(.init(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Working\"}}]}\n\n", remaining: [], paused: true), path: route)
            try await self.finished(controller) { controller.resume(record, store: store, provider: provider) }
            XCTAssertTrue(controller.issue?.contains("saved time limit") == true)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(controller.current).run.activeSeconds, 60)
            let invalid = MacAgentProvider.api(profile: .init(provider: .compatible, endpoint: "https://fixture.invalid" + route, model: "fixture-model"), key: "")
            try await self.finished(controller) { controller.start(prompt: "New request", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: invalid) }
            XCTAssertTrue(controller.issue?.contains("Choose a saved model and API key") == true, controller.issue ?? "missing issue")
        }
    }
    func testExplicitDiscardUnblocksCloseWithoutChangingTheUnrecoverableJournal() async throws {
        try await fixture { root, workspace, controller, store, provider, route in
            let visible = expectation(description: "active partial"), observer = controller.$live.filter { $0 == "Partial" }.prefix(1).sink { _ in visible.fulfill() }
            ChatHTTPFixture.register(.init(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Partial\"}}]}\n\n", remaining: [], paused: true), path: route)
            XCTAssertTrue(controller.start(prompt: "Read", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider))
            await fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observer) {}
            let file = root.appendingPathComponent(NativeAgentJournal.path(try XCTUnwrap(controller.current).id)), broken = Data("unrecoverable synced journal".utf8)
            try broken.write(to: file)
            let blocked = await workspace.prepareToCloseWindow(); XCTAssertFalse(blocked); XCTAssertTrue(controller.hasUnsavedState)
            controller.discardUnsavedState()
            XCTAssertFalse(controller.hasUnsavedState); XCTAssertNil(controller.current); XCTAssertEqual(controller.live, "")
            XCTAssertEqual(try Data(contentsOf: file), broken)
            let allowed = await workspace.prepareToCloseWindow(); XCTAssertTrue(allowed)
        }
    }
    func testTemporaryReviewFailureCanBeRebuiltWithoutAnotherProviderRequest() async throws {
        try await fixture { _, workspace, controller, store, provider, route in
            let preview = try self.call("preview", "preview_changes", [:])
            let append = try self.call("append", "note_append", ["selector": "alpha", "revision": NativeAgentNote.hash(self.alpha), "text": "Pending addition."], next: preview)
            ChatHTTPFixture.register(try self.call("read", "note_get", ["selector": "alpha"], next: append), path: route)
            var held = false
            let observer = controller.$current.sink { record in if !held, record?.run.messages.last?.toolCallId == "preview" { held = true; workspace.busy = true } }
            try await self.finished(controller) { controller.start(prompt: "Append", mode: .review, scope: .init(paths: ["Alpha.md"]), chatID: "fixture", store: store, provider: provider) }
            withExtendedLifetime(observer) {}
            XCTAssertTrue(held); XCTAssertNotNil(controller.issue); XCTAssertNil(controller.review)
            workspace.busy = false; ChatHTTPFixture.remove(route)
            try await controller.refreshReview()
            XCTAssertNotNil(controller.review); XCTAssertNil(controller.issue); XCTAssertNil(ChatHTTPFixture.captured(route))
        }
    }
    private func finished(_ controller: MacAgentController, timeout: TimeInterval = 8, start: () -> Bool) async throws {
        let done = expectation(description: "run stopped"), observer = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
        guard start() else { XCTFail("The run was unexpectedly refused before starting"); return }
        await fulfillment(of: [done], timeout: timeout); withExtendedLifetime(observer) {}
    }
    private func function(_ id: String, _ name: String, _ arguments: [String: Any]) -> [String: Any] {
        ["id": id, "type": "function", "function": ["name": name, "arguments": String(decoding: try! JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)]]
    }
    private func call(_ id: String, _ name: String, _ arguments: [String: Any], next: ChatHTTPFixture.Script? = nil) throws -> ChatHTTPFixture.Script { try calls([function(id, name, arguments)], next: next) }
    private func calls(_ functions: [[String: Any]], next: ChatHTTPFixture.Script? = nil) throws -> ChatHTTPFixture.Script {
        let indexed = functions.enumerated().map { index, function -> [String: Any] in var function = function; function["index"] = index; return function }
        let value: [String: Any] = ["choices": [["index": 0, "delta": ["tool_calls": indexed], "finish_reason": "tool_calls"]], "usage": ["prompt_tokens": 10, "completion_tokens": 5]]
        return .init(first: "data: " + String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) + "\n\ndata: [DONE]\n\n", remaining: [], next: next)
    }
    private func textReply(_ text: String, anthropic: Bool = false, thinking: Bool = false, input: Int = 10, output: Int = 5, next: ChatHTTPFixture.Script? = nil) throws -> ChatHTTPFixture.Script {
        if anthropic {
            var parts: [[String: Any]] = []
            if thinking { parts.append(["type": "thinking", "thinking": "Read before editing.", "signature": "signed-fallback-fixture"]) }
            parts.append(["type": "text", "text": text])
            let wire: [String: Any] = ["type": "message", "role": "assistant", "content": parts, "stop_reason": "end_turn", "usage": ["input_tokens": input, "output_tokens": output]]
            return .init(first: String(decoding: try JSONSerialization.data(withJSONObject: wire), as: UTF8.self), remaining: [], contentType: "application/json", next: next)
        }
        let wire: [String: Any] = ["choices": [["delta": ["content": text], "finish_reason": "stop"]], "usage": ["prompt_tokens": input, "completion_tokens": output]]
        return .init(first: "data: " + String(decoding: try JSONSerialization.data(withJSONObject: wire), as: UTF8.self) + "\n\ndata: [DONE]\n\n", remaining: [], next: next)
    }
    private func requestObject(_ request: URLRequest) throws -> [String: Any] {
        let bytes: Data
        if let data = request.httpBody { bytes = data }
        else {
            let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
            bytes = data
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }
    private func answer(_ text: String) throws -> ChatHTTPFixture.Script {
        let value: [String: Any] = ["choices": [["delta": ["content": text], "finish_reason": "stop"]], "usage": ["prompt_tokens": 10, "completion_tokens": 5]]
        return .init(first: "data: " + String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) + "\n\ndata: [DONE]\n\n", remaining: [])
    }
    private func fixture(_ operation: (URL, MacWorkspace, MacAgentController, NativeChatAttachmentStore, MacAgentProvider, String) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-agent-controller-" + UUID().uuidString), defaults = UserDefaults.standard
        let recent = defaults.stringArray(forKey: "zerus.mac.recentVaults") ?? []
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(alpha.utf8).write(to: root.appendingPathComponent("Alpha.md")); try Data(beta.utf8).write(to: root.appendingPathComponent("Beta.md"))
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChatHTTPFixture.self]
        let session = URLSession(configuration: configuration), route = "/" + UUID().uuidString + "/chat/completions"
        let workspace = MacWorkspace(); await workspace.openVault(root); await workspace.openNote("Alpha.md")
        let originalTasks = workspace.taskDraftStore?.directory
        let controller = try MacAgentController(workspace: workspace, owner: "fixture-owner", client: .init(session: session))
        let store = NativeChatAttachmentStore(directory: root.appendingPathComponent("PrivateAttachments"))
        let provider = MacAgentProvider.api(profile: .init(provider: .compatible, endpoint: "https://fixture.invalid" + route, model: "fixture-model"), key: "synthetic-key")
        let result: Result<Void, Error>
        do { try await operation(root, workspace, controller, store, provider, route); result = .success(()) } catch { result = .failure(error) }
        _ = await controller.prepareToLeave(); _ = await workspace.prepareToCloseWindow()
        for record in controller.records { try? controller.workspace.continuations.remove(run: record.id) }
        session.invalidateAndCancel(); ChatHTTPFixture.remove(route)
        for location in [root, root.appendingPathComponent("OtherVault")] {
            defaults.removeObject(forKey: MacNavigationState.key(location)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(location.path))
        }
        for directory in Set([originalTasks, workspace.taskDraftStore?.directory].compactMap { $0 }) { try? FileManager.default.removeItem(at: directory) }
        defaults.set(recent, forKey: "zerus.mac.recentVaults"); try? FileManager.default.removeItem(at: root)
        try result.get()
    }
}
