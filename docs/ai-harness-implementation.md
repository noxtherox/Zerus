# Notes harness implementation

Implemented on 30 September 2026 from the [17-item review](ai-harness-review.md). The primary architecture is a shared Zerus notes runtime, using AI SDK's tool loop and secure native provider adapters on desktop and mobile. It exposes notes operations rather than a terminal or web browser.

| Review item                 | Implemented behavior                                                                                                                    |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Precise reads and edits  | Ranges, headings, coverage, revisions, unique passage patches; complete-read requirement for whole-body replacement.                    |
| 2. Modes and scopes         | Ask, Review, Edit; captured read/write IDs; optional current-note edit restriction; current-context and ownership checks before writes. |
| 3. Save receipts and undo   | Awaited note-store writes, read-back verification, full snapshots, grouped diffs, individual change-set and whole-run undo.             |
| 4. Concrete approvals       | Durable proposals contain the exact note set, paths, contents, revisions and operation. Revalidate before applying.                     |
| 5. Shared mobile loop       | Desktop and mobile use the same runtime, schema registry, context manager, controls and run journal.                                    |
| 6. Native tools             | Native schemas, tool-call IDs and tool results in Rust and Swift transports; explicit compatibility fallback.                           |
| 7. Rich note operations     | Create, patch, properties, configured reciprocal relations, schema discovery, links, archive/pin/type move/Trash.                       |
| 8. Retrieval                | Ranked lexical search, property/type filters, pagination, match-centered passages and scoped backlinks.                                 |
| 9. Plans and completion     | Persistent plan, bounded continuation, repeated-failure detection, completion/partial/waiting/interrupted state.                        |
| 10. Durable recovery        | Checkpoints before writes, stable creation IDs, operation keys, partial multi-note save recovery and resume.                            |
| 11. Collaborative controls  | Tool activity, questions, exact approval cards, editable busy composer, Queue and Steer.                                                |
| 12. Context management      | Conservative token estimates, complete archived fragments, summaries, retained runtime state and paired tool messages.                  |
| 13. Instructions and memory | Vault-local editors and files, bounded guidance, manual reset; model suggestions cannot persist permissions or memory.                  |
| 14. Workflows               | Four built-in workflows and custom vault Markdown workflows loaded on demand.                                                           |
| 15. Provider controls       | Effort, actual usage where reported, finish reasons, elapsed time and estimated token limits including summaries/workers.               |
| 16. Evaluations             | Disposable-vault deterministic outcomes, native bridge tests, browser save/reload/undo verification, opt-in live provider evaluation.   |
| 17. Independent workers     | Two bounded analysis perspectives over explicit permitted notes; read-only, opt-in, separate durable child runs.                        |

Core ownership: `src/lib/ai-harness.ts` enforces note operations; `ai-harness-state.ts` owns durable data; `ai-harness-store.ts` adapts the real note store; `ai-sdk-agent.ts` controls generation and budgets; `ai-native-model.ts` owns tool transport mapping. Shared presentation lives in `src/components/ai/NotesAgentControls.tsx` and `useNotesAgent.ts`.

## Verification and practical limits

The deterministic evaluations exercise actual runtime saves and receipt persistence in a disposable vault. Browser verification exercised a disposable note in local browser storage: prepare an exact proposal, approve it, confirm the editor's saved content, reload the page, reopen the journal, and undo the change while preserving the original content. The preview calls no provider.

Native Rust request-building and mobile bridge serialization are tested. The Swift provider manager is typechecked independently and plugin syntax is checked. Live provider evaluation and a physical iPhone run remain pending; source implementation and transport checks do not establish model quality or an end-to-end iOS release. No desktop/iOS release artifacts or version changes are part of this implementation.

Codex currently retains its text-tool compatibility path and a new app-server session per generation. Its per-generation output-token limit is advisory; the current transport does not send a hard output ceiling to the app-server. Persistent Codex thread resume, app-server steering and experimental dynamic tools are an optional later integration. Zerus's own run resume and steering work independently of that choice.

Search remains lexical. Semantic indexing and reranking were optional experiments in the review and are not included. The agent can inspect existing schemas and edit configured relationships; creating reciprocal schemas, changing type schemas, moving managed file assets, permanent deletion and arbitrary CLI operations remain outside chat's tool surface. Relation-preserving type moves require compatible destination definitions. A legacy backlink outside edit scope must be made editable before an agent rename can proceed.

Multi-note filesystem writes are recoverable, not atomic. Stop prevents new steps and reaches active provider cancellation; an already-started storage write may finish and is verified/journaled. Resume needs the original context and current chat ownership. Native provider capabilities vary; native-tool support, effort and usage must be checked with the chosen model. Workers and compaction can add provider calls, bounded by the configured run budget.
