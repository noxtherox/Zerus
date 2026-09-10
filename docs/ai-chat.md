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

Supported inputs include images, PDFs with selectable text, and text-based files such as TXT, Markdown, CSV, JSON, HTML, and source code. Each message supports up to four documents, with 16,000 extracted characters in total and a 20 MB per-document limit. Unsupported binary formats and scanned PDFs without text show an error; export those documents as text or a searchable PDF first.
