# AI chat

Desktop and mobile share the vault's `.zerus/chats` event history. Open **History** on desktop or **Conversation history** on mobile to search titles and messages, rename, archive, delete, restore, or continue on another device. **New chat** preserves the previous conversation. Recently deleted chats follow the same 30-day retention policy on both platforms. Existing desktop conversations are migrated into the shared history.

Use **Context** to select notes, add notes outside the active folder, or return to the active scope. The selection is saved with the conversation and used by retrieval and note tools. Desktop **Preview context** shows the excerpts selected for the draft question; **Context used** on an answer preserves the excerpts as they were when that answer was generated. A later note edit does not rewrite those snapshots.

Answers support Markdown, note links, Copy, Save as note, Append to note, and Regenerate. Regeneration uses a read-only run. Desktop and mobile stream answer text and support Stop; completed tool activity, proposals and verified saves survive interruption. Scrolling up stops automatic following until **Jump to latest** is selected.

## Notes agent

Choose a mode beside the composer:

- **Ask** reads and analyzes notes without changing them.
- **Review** prepares exact proposals. Expand a proposal to inspect its diff, then approve or reject it. Approvals bind to the concrete notes, paths, revisions and content; an intervening edit refuses the stale proposal.
- **Edit** saves requested ordinary changes in the permitted edit scope. Moving notes to Trash and changes spanning multiple notes still require review.

The selected Context determines reading. **Edit current note only** permits broad reading while restricting changes to the current note; it cannot create notes. With no current note, it permits no writes. **Edit selected context** allows changes throughout the context. Creating or moving notes requires a vault or type context with an allowed destination. External notes and managed saved-link notes remain protected.

Tools support ranked lexical search, filters and pagination; complete or ranged reads with headings and continuation offsets; unique exact-text patches; creation; frontmatter properties; paired relation updates; links/backlinks; type schemas; pinning, archiving, type moves and recoverable Trash. Whole-body replacement requires complete read coverage at the current revision. Relation editing requires configured reciprocal definitions and every affected note in the edit scope. A move that would lose a populated relation definition is refused until the destination schema is compatible. A rename stages legacy backlink stabilization together with the renamed note and requires those sources to be editable.

The run panel shows plans, proposals, verified receipts, questions and activity. **Undo** restores exact snapshots and refuses to overwrite newer work. A multi-note proposal is undone as a change set; **Undo all run changes** reverses saved operations in order. Undoing creation moves the new note to Trash. Multi-note saves are recoverable operations rather than filesystem transactions: an interruption can leave a partially saved set, recorded for recovery.

Keep typing while the agent works. **Steer this run** supplies a correction at the next model step; **Queue next message** waits for the current run to finish. A structured question pauses execution until answered. **Resume saved run** restores the objective, plan, tool history and completed operations; restore the saved context first. Resuming never widens a previously captured edit capability. A save with an existing operation key returns its recorded result instead of repeating it.

Native function schemas and tool-call IDs are used for OpenAI, Anthropic, OpenRouter and compatible endpoints. Enable **Text tool fallback** only for an endpoint/model that does not support native tools. ChatGPT through Codex currently uses this fallback automatically and starts a separate app-server session per generation. It does not yet use persistent Codex threads or experimental dynamic tools. Its output-token setting is advisory because the current transport does not send a hard output ceiling to the app-server; subsequent steps are still checked against the estimated total budget. Advanced CLI compatibility calls translate supported reads into scoped tools; chat cannot spawn an unrestricted CLI or change vaults. The standalone desktop CLI remains available outside chat.

## Instructions, workflows and budgets

**Agent settings** configures step, output, context, elapsed-time and total-token limits, plus supported reasoning effort. Defaults are 30 steps, 8,192 output tokens, 48,000 context tokens, 10 minutes and 160,000 total tokens. Context is additionally capped by the selected model's reported capacity, with a conservative 32,768-token fallback when unavailable. Provider-reported usage appears in activity; the budget uses estimates when the provider omits usage. Summary and worker calls count against the total. Limits apply across resumed run usage; increase the budget when necessary. Provider capabilities and reasoning support vary by model.

The shared context manager estimates complete requests, including tools, images, history and output headroom. Older conversation fragments are summarized when needed; the objective, scope, plan and receipt/proposal state are retained separately. Complete archived evidence remains in the journal. Recent tool calls stay paired with their results. An oversized current request produces an explicit limit error instead of silently discarding it.

Vault instructions and memory are visible editors, saved in `.zerus/ai/instructions.md` and `.zerus/ai/memory.md`. Clear either editor and save to reset it. The model can suggest a memory update, but only this human-controlled editor persists it. Note prose, files, tool outputs, summaries and memory cannot grant permissions.

Choose meeting cleanup, related-note synthesis, duplicate review or weekly review from the workflow selector. Add custom Markdown workflows in `.zerus/ai/workflows/`; a leading heading names the workflow. Settings are stored in `.zerus/ai/settings.json`, and runs in `.zerus/ai/runs/<chat>/<run>.json`. These vault-local files contain note evidence and follow the vault's storage/sync policy. Run journals are removed with expired, deleted conversations after the normal 30-day retention period.

Independent analysis is off by default. When enabled, `analyze_notes` launches two bounded, read-only workers over the explicitly requested notes, one examining support and one examining contradictions. They cannot mutate or expand scope. Their results are reference data and can require extra paid model calls.

## Development preview

Run `pnpm dev` and open `/app`, then **Chat preview**. This development-only entry is labelled **Local preview** and does not call a provider. It exercises the shared runtime, approvals, durable receipts, history and undo in the browser's own vault. For a concrete review example, create a disposable note and send `Append "verification complete" to this note.` in Review mode. The deterministic preview supports this append demonstration and ordinary excerpt answers; it is not a simulated general-purpose model. Real provider tools and streaming require running the updated native app.

Validation: `pnpm typecheck`, `pnpm test`, `pnpm build`, targeted ESLint, `cargo test --manifest-path src-tauri/Cargo.toml -p app --lib`, and the mobile-vault bridge's Rust tests. `pnpm ai:eval` runs disposable-vault outcomes for precise edits, revisions, scope, restart recovery, relations, compaction and native continuation. `pnpm ai:eval:live` is opt-in: set `ZERUS_EVAL_ENDPOINT`, `ZERUS_EVAL_MODEL`, and `ZERUS_EVAL_API_KEY` for a compatible provider. This makes a paid provider request against a disposable fixture, never the user's vault; it skips when credentials are absent. See [implementation coverage](ai-harness-implementation.md) for verification limits.

## File context

Use Attach (Add files on mobile) or drop files anywhere inside the AI chat to include them as chat context. Drops over chat do not attach files to the open note. Documents are saved with the conversation, and can be removed from the composer before sending.

Supported inputs include images, PDFs with selectable text, and text-based files such as TXT, VTT, Markdown, CSV, JSON, HTML, and source code. Documents have a 50 MB per-file processing limit and a 100 MB combined upload/extracted-text budget per message, with no fixed document-count or 16,000-character limit. The existing four-image limit is separate. Unsupported binary formats and scanned PDFs without text show an error; export those documents as text or a searchable PDF first.

File context uses the selected model's reported context capacity where available, with documented capacities for recognized model IDs and a labelled 32,768-token fallback for unknown models. An o200k tokenizer estimates text tokens with additional headroom for other providers. The budget reserves space for conversation and note context, images, tools, and the answer; it is not an exact provider billing token count. The shared run budget also accounts for the selected document context.

When full documents exceed the available budget, a background worker selects query-matched excerpts with source filenames and character offsets. Chat shows **Using file excerpts** instead of **Full file context**, and the model is instructed not to claim exhaustive coverage. Follow-up questions search the original saved document text again. This is lexical retrieval, not an exhaustive multi-pass summary of every page. Browser previews remain subject to browser storage quotas; native vault history stores the extracted source text on disk.

Capacity references: [GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4), [GPT-5.4 mini](https://developers.openai.com/api/docs/models/gpt-5.4-mini), [GPT-4.1](https://developers.openai.com/api/docs/models/gpt-4.1), and [Claude context windows](https://platform.claude.com/docs/en/build-with-claude/context-windows). Provider-reported capacity takes precedence over these fallback entries.
