# Zerus AI chat harness review

Reviewed on 30 September 2026. Status: proposed improvements for review.

Zerus has a useful foundation for a capable notes agent: desktop tool execution, a broad CLI, shared conversation history, source snapshots, and some undo and conflict protection. The main gaps are in how these pieces work together. A request should drive discovery, a plan when needed, coordinated edits, verification, and a clear result, with enough continuity to recover from interruptions.

My recommendation is to build one shared notes harness around the existing vault operations and provider choices. Keep the user experience centered on notes. A richer harness should understand the vault, edit precisely, and finish delegated work while remaining easy to review and steer.

This is a code and documentation review of the current checkout, including existing local changes. It is not a live provider benchmark or a screenshot-based interface audit. Findings below distinguish observed behavior from proposed choices and risks inferred from the implementation. No application behavior was changed for this review.

## What already works

- Desktop uses AI SDK `ToolLoopAgent` with six exposed tools, including access to the bundled Zerus CLI. The CLI already supports creation, properties, types, links, history, undo, and bulk operations. Desktop capability is broader than the two direct edit tools suggest.
- Desktop and mobile share vault-local conversation events, ownership, saved context, and source snapshots. Conversation history survives across devices; durable execution of an unfinished task is a separate capability that still needs work.
- Desktop streams text through native events, supports Stop, and retains some interrupted output. It also records tool activity on completed answers. Streaming exists even though the custom AI SDK model's `doStream` method is unimplemented.
- Direct edits preserve frontmatter. Desktop replacement checks for intervening edits; mobile actions carry revisions. Some supported changes have before and after snapshots and an undo action that refuses to overwrite later edits.
- Note context and tool output are treated as untrusted data. Desktop approvals bind consent to the previewed CLI arguments. These protections should remain as the harness gains autonomy.
- Uploaded documents already have extraction, model-capacity budgeting, and searchable excerpts. That work can inform a better context manager for notes and conversation history.

Evidence: [desktop agent](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-sdk-agent.ts:406), [CLI capabilities](/Users/tiagopereira/Documents/Codex/Zerus-remote/docs/CLI.md:16), [shared history](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/mobile-chat-history.ts:87), and [AI chat guide](/Users/tiagopereira/Documents/Codex/Zerus-remote/docs/ai-chat.md:1).

## What limits the experience today

| Observed constraint | Consequence for note work | Evidence |
| --- | --- | --- |
| Desktop defaults to eight generation steps and requests 2,048 output tokens per step. | Searching, reading several notes, editing, and verifying can exhaust the loop. Long replacement bodies compete with a small output allowance. The Codex transport does not forward that token limit to its turn request. | [configuration](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-agent-policy.ts:25), [loop](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-sdk-agent.ts:451), [Codex turn](/Users/tiagopereira/Documents/Codex/Zerus-remote/src-tauri/src/lib.rs:1074) |
| Tool schemas are inserted into prose; the model emits XML-tagged JSON. One tool call per response is required. | Native tool calling, multiple independent reads per reply, reliable call IDs, and provider finish metadata are lost at the transport boundary. Malformed tags can end the request. | [tool protocol](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-sdk-agent.ts:245), [native requests](/Users/tiagopereira/Documents/Codex/Zerus-remote/src-tauri/src/lib.rs:1305) |
| The Codex provider starts a new app-server and an ephemeral thread for each generation step. Built-in actions are disabled. | Selecting Codex currently supplies inference to Zerus's outer loop; it does not supply the full persistent Codex harness. Process startup and transcript replay may add overhead, which has not been measured here. | [thread configuration](/Users/tiagopereira/Documents/Codex/Zerus-remote/src-tauri/src/lib.rs:968), [process startup](/Users/tiagopereira/Documents/Codex/Zerus-remote/src-tauri/src/lib.rs:1049) |
| Mobile retrieves context, makes one provider call, and applies returned action tags. It permits at most three actions and one action per existing note. | The model cannot inspect a tool result, retrieve missing content, correct an error, or verify an edit within that run. Mobile and desktop have substantially different capabilities. | [mobile generation](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/components/mobile/AIChat.tsx:730), [action limits](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/mobile-ai-actions.ts:116) |
| Direct desktop writes affect only the current note. | Other notes require the generic CLI, and note creation, organization, properties, and links have no dedicated tool schemas. | [direct tools](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-sdk-agent.ts:430) |
| Desktop direct reads return at most 16,000 body characters without a truncation field or continuation handle. Mobile retrieval uses up to five notes, normally with 1,600-character excerpts. | The model can miss later sections. Whole-body replacement remains available, creating a risk of dropping content it never saw. Revision checking alone does not establish that a rewrite preserved unseen content. This risk was identified from code, not demonstrated against a user's vault. | [desktop read](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-tools.ts:383), [mobile excerpts](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/mobile-note-retrieval.ts:14), [mobile replacement](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/mobile-ai-actions.ts:151) |
| The direct search tool uses a literal substring and returns the start of matching notes. Listing has a limit but no cursor. | Multiword questions can miss relevant notes; excerpts may omit the actual match; the model cannot exhaustively page through the direct listing. The CLI offers richer filters, but requires command discovery. | [search and list](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-tools.ts:401) |
| Direct tools enforce the selected context, while CLI calls use the active vault and accept a supplied alternative vault. | The Context picker does not define one enforced boundary for all tools. A user cannot reliably infer the agent's full reach from that selection. | [execution branches](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/components/ai/AiPanel.tsx:1075), [vault arguments](/Users/tiagopereira/Documents/Codex/Zerus-remote/src-tauri/src/lib.rs:186) |
| Write authorization uses English regular expressions and only the current message. | Natural requests, other languages, mixed instructions, and follow-ups can be rejected. One boolean also cannot represent permission for a particular operation on particular notes. | [desktop authorization](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-agent-policy.ts:42), [mobile authorization](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/mobile-ai-actions.ts:86) |
| In-flight tool events are held in component state; completed tool details are formatted and clipped for storage. | A crash can lose the execution trail. The clipped display record is also reused for follow-up context and approval parsing. CLI mutations bypass the direct-edit snapshots attached to chat answers, even though CLI history exists separately. | [activity formatting](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/components/ai/AiPanel.tsx:150), [finalization](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/components/ai/AiPanel.tsx:1273) |
| Direct edits report success after updating the note store, before awaiting the debounced save. | A successful tool response confirms an optimistic update, rather than a persisted note. Save conflicts or failures can surface later. | [apply and success](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/components/ai/AiPanel.tsx:1186), [save scheduling](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/store/notes-store.ts:2474) |
| Desktop drops older history using a 24,000-character budget; mobile normally sends six recent messages clipped to 1,200 characters each. Mobile updates conversation summaries; desktop consumes an existing summary. | Important decisions and outstanding work can fall out of view. There is no shared token-aware compaction of the accumulating tool loop or structured task state. | [desktop history](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-chat-experience.ts:24), [mobile prompt](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/mobile-ai-response.ts:28), [memory updates](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/components/mobile/AIChat.tsx:711) |
| The adapter reports undefined usage and synthesizes `stop` or `tool-calls`. Desktop's composer is disabled while running. | The harness cannot accurately explain budget exhaustion or truncated output, and the user must stop work before correcting its direction. | [response metadata](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-sdk-agent.ts:337), [composer](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/components/ai/AiPanel.tsx:1986) |

## Improvements to review

Priority definitions: P0 protects the integrity and predictability of note changes; P1 delivers the core delegated-work experience; P2 adds continuity, customization, and scale. Effort is relative: small means a focused change, medium spans a few subsystems, and large requires coordinated runtime, persistence, and interface work. These are scope estimates, not delivery dates.

| Proposal | What the user would gain | Priority | Relative effort |
| --- | --- | --- | --- |
| 1. Read sections and patch precise text | Change one paragraph or heading without regenerating the whole note; inspect every needed section of a long note. | P0 | Medium |
| 2. One enforced permission and scope model | Select Ask, Review, or Edit behavior and a clear note boundary. Authorized follow-ups continue the same task; restrictions remain enforceable. | P0 | Large |
| 3. Verified writes and a shared change journal | Every edit has a save receipt, a readable diff, and recoverable history, including changes made through the CLI. | P0 | Large |
| 4. Structured approvals bound to a change set | Approve the displayed notes and revisions through a card; an intervening vault change cannot silently expand the approved operation. | P0 | Medium to large |
| 5. One agent runtime for desktop and mobile | The same request supports discovery, action, repair, and verification on either platform, using platform-specific storage and provider transports. | P1 | Large |
| 6. Native structured tool calling | More reliable tool arguments, provider metadata, and multiple independent reads in a step; text tags become a fallback for compatible endpoints that need them. | P1 | Large |
| 7. Explicit tools for note operations | Create notes, patch sections, update properties, inspect links, and organize notes without guessing CLI syntax. | P1 | Medium to large |
| 8. Search and retrieval that can investigate | Search titles, prose, properties, and relationships; page through results; fetch passages around matches; reformulate a query when needed. | P1 | Medium |
| 9. A loop that tracks task completion | Keep a task's objective and pending steps visible; continue until verified completion or an explicit limit; identify partial completion accurately. | P1 | Medium to large |
| 10. Persistent run events and safe resume | Resume after a network failure or restart without repeating a successful edit or losing its result. | P1 | Large |
| 11. Progress, steering, and structured questions | See which notes are being read or changed; correct the agent while it works; answer a concrete ambiguity through a small picker. | P1 | Medium |
| 12. Token-aware context and compaction | Preserve decisions and outstanding work while pruning obsolete tool output. Show when coverage is partial. | P1 | Medium to large |
| 13. Vault instructions and editable memory | Remember naming conventions, writing preferences, and organization rules across chats, with visible sources and a reset control. | P2 | Medium |
| 14. Reusable note workflows | Invoke meeting cleanup, literature synthesis, duplicate review, or weekly review as editable workflows. | P2 | Medium |
| 15. Provider capabilities and budget controls | Choose supported reasoning effort and task limits; see actual usage where available; handle truncation and provider incompatibility explicitly. | P1 | Medium |
| 16. Outcome evaluations | Measure whether realistic note tasks finish correctly and safely across models and platforms. | P1 | Medium |
| 17. Optional workers for large vault analysis | Delegate independent reading or comparisons with separate context; coordinate edits through the main run. | P2 | Large |

### Protect long notes and use precise edits

Add a read contract that returns note ID, revision, total size, the returned range or heading, whether more content exists, and a continuation handle. Add a patch tool with expected revision, exact old text or a stable section target, and replacement text. Reject ambiguous matches and return an actionable conflict.

Require a complete read before a complete rewrite, or construct the replacement from a known full snapshot. A generic instruction to preserve content is insufficient when the model never received that content. The mobile exact-text replacement already provides a useful starting point; share its behavior across platforms.

### Make authorization useful across a whole task

Use explicit interaction modes: Ask allows reading; Review prepares changes without applying them; Edit allows the requested changes within the declared scope. Read scope and edit scope should be visible separately so a selected note can be the writing target while relevant vault notes support the work.

Carry an authorized objective and bounded capabilities across continuations. Keep explicit prohibitions such as “do not delete” as operation restrictions rather than rejecting every edit in the same sentence. Natural-language interpretation can help prepare a plan, but runtime enforcement should check structured capabilities and targets rather than trust a model-issued authorization flag.

Enforce the same boundary in every execution path, including the native CLI bridge. Define how changing scope or conversation ownership affects a running task. Preserve the existing rule that note contents, attachments, and tool output cannot grant permissions.

### Give every change a receipt and one review surface

Route direct tools and CLI-backed tools through one mutation service. It should record the intent before writing, require a revision where applicable, await storage confirmation, and return changed IDs, resulting revisions, and history transaction IDs. Existing `flushNoteWrites`, CLI atomic writes, and CLI history can support this work.

Show a grouped diff with note links and per-note results. Offer undo for the whole run and individual changes, including created notes, property changes, and organization changes where supported. A run spanning several files should report any partially committed set and provide recovery; ordinary filesystem writes do not automatically make a multi-file operation atomic.

For approvals, persist structured proposal data separately from display strings. Bind approval to the vault, concrete targets, revisions, operations, and proposed content. Today the consent code binds exact CLI arguments, but a bulk query is evaluated again when applied. The same arguments can therefore match a different note set later. See [bulk execution](/Users/tiagopereira/Documents/Codex/Zerus-remote/src-tauri/crates/zerus-cli/src/main.rs:2987). Revalidate the approved set and surface any changed scope.

### Give the agent a complete notes toolset

Suggested initial tools are `search_notes`, `list_notes`, `read_note`, `read_note_section`, `create_note`, `patch_note`, `update_note_properties`, `list_note_links`, `organize_notes`, `preview_changes`, and `apply_changes`. Add tools for updating a plan and asking the user a structured question when the runtime supports pausing and resuming.

Each operation should identify concrete notes, obey scope, expose revisions, and return structured results. Discover schema definitions and preserve stable Zerus links when editing properties or relationships. Keep the CLI as a useful backend and an optional advanced escape hatch within the same policy boundary.

Start retrieval improvements with the strongest existing local search capabilities, match-centered passages, filters, paging, and link traversal. Add a local index when scale warrants it. Semantic retrieval and reranking are optional later experiments, to be retained only if evaluations show better results. They are not prerequisites for a capable note agent.

### Continue work and recover safely

Use one shared run controller with provider and vault adapters. It should manage the objective, plan, read revisions, completed tool calls, pending approvals, pending user input, changes, budgets, and completion state. Move this state out of individual chat components.

An example proposed starting limit is 30 steps for delegated editing, combined with elapsed-time and token limits. Tune it using measured tasks. Larger limits alone do not guarantee completion: detect no progress, repeated errors, and unfinished plan items; reserve room for a final status; checkpoint before stopping.

The current desktop duplicate-call guard rejects any identical tool call within a request, including rereading after a write or retrying a failed read. Reads should be repeatable or cached by revision. Writes should have durable idempotency keys, so reconnecting can retrieve an earlier receipt instead of applying the edit again. See [duplicate-call guard](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/components/ai/AiPanel.tsx:1068).

Persist events as work happens: run started, tool started, tool completed, change committed, approval requested, user input requested, paused, interrupted, and finished. The existing vault-local chat event format provides a base, but completed conversation messages alone are insufficient for execution recovery. Stop must reach an active operation where cancellation is supported. The current CLI subprocess bridge has no stream ID or cancellation handle, so stopping provider generation does not establish cancellation of an already running CLI command.

### Make the ongoing work legible and steerable

Render an activity timeline that says “Searching Projects,” “Reading Decision Log,” or “Updated the Status property on 4 notes.” Preserve short progress messages between steps. The current desktop UI clears streaming text as each step or tool starts; a sequence of activity events would preserve useful continuity.

Keep the composer usable while work runs, with clear Queue and Steer choices. Process steering at a safe tool boundary and recheck the plan and capabilities before continuing. Add structured questions for ambiguous note titles and destinations, and inline approval cards with approve and reject actions. Use readable summaries and diffs as the default review surface, with raw JSON available in details.

### Manage context and memory deliberately

Budget the complete request: instructions, tool schemas, recent messages, note passages, documents, images, and accumulating tool results. Keep source revision and coverage metadata attached to passages. Re-read a note when its revision changes. Large CLI output should be parsed, summarized, or paged rather than repeatedly copied into every later model request.

Share compaction behavior across mobile and desktop. Keep the current objective, constraints, approvals, key decisions, touched notes, and unfinished work outside a lossy prose summary. Store older evidence so it can be retrieved again. Conversation summaries and persistent writing preferences have different purposes and should be editable separately.

Use an explicitly configured vault instructions file or settings editor for trusted conventions. Ordinary note prose must remain reference data. Suggested memory should have a visible provenance, a bounded size, and an easy edit or forget action. Load reusable workflows on demand so their full instructions do not fill every prompt.

## Architecture choice

The proposed primary path is a shared Zerus harness with the existing AI SDK loop and secure native provider transports. Give those transports real tool messages, usage, finish reasons, and streamed events. Keep credentials in the existing native credential stores. Use the vault backend for tool operations on mobile and browser, and the existing core or CLI operations on desktop behind the same contracts.

This preserves the current provider choices and makes note behavior a Zerus feature across platforms. The installed AI SDK documentation already describes loop control, per-step context preparation, tool-call repair, and structured approval handling. Verify the installed version's APIs during implementation; the repository currently declares AI SDK 7.

There is also a Codex-specific option: use a persistent app-server connection and resumed threads, and register only the intended Zerus operations. The official app-server protocol supports thread resume, steering, compaction, and tool lifecycle events. Custom dynamic tools are experimental and require capability opt-in, so that integration needs version detection and a compatibility path. These capabilities make it a candidate for desktop acceleration; relying on it alone would leave mobile and other providers needing a separate solution. This is an architectural recommendation, not a verified integration. [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server).

Modern Claude Code documents a gather, act, verify loop, persistent sessions, checkpoints, permissions, compaction, and steering. These behaviors are the useful reference for a notes harness. [How Claude Code works](https://code.claude.com/docs/en/how-claude-code-works). Its persistent project instructions and editable memory provide a separate reference for conventions across conversations. [Claude memory documentation](https://code.claude.com/docs/en/memory).

Both OpenAI and Anthropic expose native structured tool protocols. Adapting Zerus's tools to them avoids making ordinary answer text the primary execution protocol. [OpenAI function calling](https://developers.openai.com/api/docs/guides/function-calling), [Claude tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview).

## Recommended implementation order

1. **Reliable note operations.** Add complete and ranged reads, revision-bound patching, verified save receipts, and unified scope enforcement. Make all supported changes visible through a shared journal. Correct small authorization and command-classification defects during this phase.
2. **A shared agent runtime.** Introduce native tool transports, a shared desktop and mobile loop, dedicated note tools, stronger retrieval, task state, persisted execution events, and bounded recovery. Evaluate with real note tasks as each capability lands.
3. **A collaborative chat experience.** Add Ask, Review, and Edit controls; grouped diffs; structured approval and ambiguity cards; progress; Queue and Steer; token-aware compaction; and safe resume. Runtime state and event contracts from the earlier phases should drive the UI.
4. **Personalization and large workflows.** Add trusted vault instructions, editable memory, reusable workflows, and optional independent analysis workers. Prioritize these using measured usage and evaluation results.

The initial product milestone should be: “Find the notes relevant to this project, clean up their formatting, update their properties, and show everything you changed.” It should work without selecting every source manually or issuing each edit as a separate command. Full completion includes confirmed persistence, a verified result, and recoverable changes.

## Small fixes that can land independently

- Correct the read-only CLI classifier for `type list`; the command exists, but the current classifier treats it as a mutation. See [classification](/Users/tiagopereira/Documents/Codex/Zerus-remote/src/lib/ai-sdk-agent.ts:97).
- Allow valid edits with an explicit no-delete restriction instead of rejecting the entire request. Add supported multilingual and merge intent cases while transitioning toward structured task permissions.
- Add truncation and total-length metadata to direct note reads. Prevent whole-body replacement from a partial read.
- Await the existing note-save flush before returning a successful edit receipt.
- Preserve actual provider finish reasons and expose partial completion when the step limit is reached.
- Preserve completed tool activity when handling a failed or interrupted run; the current catch path does not attach `completedToolCalls` to its interrupted answer.
- Separate complete machine-readable tool records from the 6,000-character display formatting. Approval and recovery data must not depend on clipped JSON.

These improve reliability immediately, but do not by themselves deliver the shared runtime or a complete multi-note experience.

## Acceptance checks for the proposed harness

| Scenario | Observable success |
| --- | --- |
| Clean up a long note whose relevant section is beyond the first excerpt | The agent fetches that section, changes only the requested text, and preserves the tail of the note. |
| “Please edit this note but do not delete anything” | The allowed content edit succeeds; deletion remains unavailable. |
| “Organiza estas notas” in an explicitly enabled Edit mode | The task works without requiring English authorization keywords and stays within the granted scope. |
| Merge several duplicate notes and update their references | The agent discovers candidates, presents or applies the authorized change set, preserves useful content, updates stable references, and verifies the result. |
| Search one selected type while other matching notes exist elsewhere | Every execution path obeys the declared read boundary; expansion is handled through the configured scope policy. |
| Edit a note while the agent is preparing its patch | A revision conflict prevents a stale write, and the agent can reread and prepare a fresh patch. |
| Add a matching note after a bulk preview | The approved operation does not silently include the new note. |
| Lose the connection after a successful append | Resume retrieves the existing receipt and does not append the same text again. |
| Stop during an operation | No later operation starts; an uncancellable committed operation is accurately reported and recoverable where supported. |
| Continue a complex conversation after compaction | The objective, restrictions, decisions, touched notes, and unfinished work remain available. |
| Put tool instructions in note content or an attachment | The instructions remain reference data and cannot authorize or redirect writes. |
| Fail a storage write or conflict during a run | The run reports the failed save and exact committed subset, rather than claiming that all requested changes succeeded. |
| Steer a running cleanup toward a different folder | The update is acknowledged and the next safe step follows the revised scope without replaying completed writes. |
| Run the same task on desktop and mobile | Results satisfy the same tool and policy contracts, with explicit capability limits where a platform cannot execute an operation. |

Measure task completion, correct note selection, preservation of unrelated content, verified persistence, recovery without duplicate edits, unsupported claims, elapsed time, tool calls, and tokens. Keep deterministic contract checks separate from a small provider-backed evaluation set using disposable vaults. Do not use passing mocked transport tests as proof of live provider quality.

## Checks performed for this review

The existing desktop policy and agent tests passed: **2 files, 23 tests** with `pnpm exec vitest run src/lib/ai-agent-policy.test.ts src/lib/ai-sdk-agent.test.ts`. They exercise the current loop, authorization, exact-argument consent, and cancellation around provider responses. The native provider calls are mocked in the agent tests.

A read-only execution of `authorizesAiNoteMutation` confirmed these results:

| Request | Current result |
| --- | --- |
| Rewrite this so it is clearer. | Authorized |
| Please edit this note but do not delete anything. | Denied |
| Merge these duplicate notes. | Denied |
| Continue. | Denied |
| Organiza estas notas. | Denied |

No provider calls, user-vault mutations, desktop builds, mobile builds, or live interface captures were performed. Latency, model task success, and the inferred long-note preservation risk still need controlled end-to-end evaluation during implementation.
