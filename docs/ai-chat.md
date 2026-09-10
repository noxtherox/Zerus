# AI chat

Desktop and mobile share the vault's `.zerus/chats` event history. Open **History** on desktop or **Conversation history** on mobile to search titles and messages, rename, archive, delete, restore, or continue on another device. **New chat** preserves the previous conversation. Recently deleted chats follow the same 30-day retention policy on both platforms. Existing desktop conversations are migrated into the shared history.

Use **Context** to select notes, add notes outside the active folder, or return to the active scope. The selection is saved with the conversation and used by retrieval and note tools. Desktop **Preview context** shows the excerpts selected for the draft question; **Context used** on an answer preserves the excerpts as they were when that answer was generated. A later note edit does not rewrite those snapshots.

Answers support Markdown, note links, Copy, Save as note, Append to note, and Regenerate. Regeneration adds a fresh turn and does not repeat note mutations. AI edits retain before/after snapshots; **Undo changes** refuses to overwrite subsequent edits. Desktop streams answer text, supports cancellation, preserves interrupted output, and provides retry or regeneration. Scrolling up stops automatic following until **Jump to latest** is selected.

Desktop selects sibling excerpts by question relevance. Long requests use a 24,000-character recent-history budget, retaining complete turns and the current question. Older messages stay in history; available mobile conversation memory is also included, capped at 8,000 characters. The interface indicates when older history was omitted. This is a character budget, not a model-specific token estimate.

## Development preview

Run `pnpm dev` and open `/app`, then **Chat preview**. This development-only entry uses local note excerpts, clearly labelled as a preview; it does not call a provider. It exercises history, context selection, streaming controls, and answer actions in the browser's own vault. Real provider streaming and cancellation use the native desktop commands and require running the updated desktop app.

Validation: `pnpm typecheck`, `pnpm test`, `pnpm build`, targeted ESLint, and `cargo test --manifest-path src-tauri/Cargo.toml -p app --lib`.

## File context

Use Attach (Add files on mobile) or drop files anywhere inside the AI chat to include them as chat context. Drops over chat do not attach files to the open note. Documents are saved with the conversation, and can be removed from the composer before sending.

Supported inputs include images, PDFs with selectable text, and text-based files such as TXT, VTT, Markdown, CSV, JSON, HTML, and source code. Documents have a 50 MB per-file processing limit and a 100 MB combined upload/extracted-text budget per message, with no fixed document-count or 16,000-character limit. The existing four-image limit is separate. Unsupported binary formats and scanned PDFs without text show an error; export those documents as text or a searchable PDF first.

File context uses the selected model's reported context capacity where available, with documented capacities for recognized model IDs and a labelled 32,768-token fallback for unknown models. An o200k tokenizer estimates text tokens with additional headroom for other providers. The budget reserves space for conversation and note context, images, tools, and the answer; it is not an exact provider billing token count. The existing recent-conversation budget applies to message prose, not full uploaded documents.

When full documents exceed the available budget, a background worker selects query-matched excerpts with source filenames and character offsets. Chat shows **Using file excerpts** instead of **Full file context**, and the model is instructed not to claim exhaustive coverage. Follow-up questions search the original saved document text again. This is lexical retrieval, not an exhaustive multi-pass summary of every page. Browser previews remain subject to browser storage quotas; native vault history stores the extracted source text on disk.

Capacity references: [GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4), [GPT-5.4 mini](https://developers.openai.com/api/docs/models/gpt-5.4-mini), [GPT-4.1](https://developers.openai.com/api/docs/models/gpt-4.1), and [Claude context windows](https://platform.claude.com/docs/en/build-with-claude/context-windows). Provider-reported capacity takes precedence over these fallback entries.
