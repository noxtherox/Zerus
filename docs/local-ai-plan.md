# Local AI plan (native macOS + native iOS)

Status: agreed 2026-11-25. Phase 1 closed 2026-11-25; phase 2 (hide cloud AI UI) done; phase 3 (shared core) done.

## Decisions

- **Targets:** native SwiftUI macOS (`native-macos/`) and iOS (`native-ios/`)
  only, sharing one Swift harness in `packages/apple/`. The Tauri app keeps
  its existing cloud AI untouched and gets no local AI.
- **Purpose:** note search, text summarization, note updates.
- **Cloud AI in native apps:** removed from the UI (chat panel, provider
  settings, ChatGPT/Anthropic sign-in, menu items). `MacAgent*`,
  `NativeAgent*`, `ChatGPTCore`, Keychain tokens and `.zerus/chats` stay in
  the tree until a later cleanup.
- **Runtime:** MLX Swift (`mlx-swift-lm`) with a downloaded model of **at most
  2B parameters**. The same model on every device.
- **Models (chosen 2026-11-25 from the phase 1 benchmark):** LLM
  `mlx-community/Qwen3.5-2B-4bit` (Apache-2.0); embeddings
  `mlx-community/embeddinggemma-300m-4bit` (Gemma Terms of Use), used
  unmodified. Pin both to a fixed Hugging Face revision.
- **Languages:** fully multilingual (LLM and embedding model).
- **Hardware floor:** LLM features need iPhones with ≥6 GB RAM or
  Apple-silicon Macs (M1/8 GB). Semantic search (embedding model only) is
  offered on 4 GB iPhones when MLX works there. When AI is enabled, a short
  MLX self-test (a tiny matrix multiply plus one embedding) runs once per app
  and OS version. Devices that fail it, such as the A13 iPhone 11
  (ml-explore/mlx-swift#526), keep keyword search and show "On-device AI isn't
  supported on this iPhone". Revisit when #526 is fixed. Apple's
  `NLContextualEmbedding` is a possible later fallback for those devices.
- **Delivery:** opt-in download in Settings from pinned Hugging Face revisions
  with checksum verification, Wi-Fi only by default, stored in Application
  Support (never in the vault), with "Delete models".
- **Search:** embeddings rank the results (rank fusion with BM25 lowered
  recall in phase 1). Keyword search is the fallback while the index builds
  and an exact-match boost for quoted phrases and distinctive codes or
  numbers. The LLM only answers over retrieved chunks, with citations.
- **Index:** per-device SQLite in Application Support, never synced,
  incremental by content hash. iOS heavy indexing runs while the app is open or
  in a `BGProcessingTask` while charging. Lexical-only until the index is ready.
- **Harness:** fixed pipelines (Ask, Summarize, Edit) with grammar-constrained
  JSON outputs, plus one router call that classifies free-text Ask requests.
  No agent loop.
- **Edits:** rewrite/format selection, append, instruction edit, create note,
  properties. One note per request. Every change shows a diff preview, then
  saves with undo. Edits requested from global Ask require confirming the
  target note from the top 3 candidates.
- **UI:** inline actions on a selection or note, plus "Ask" in global search
  with a few follow-ups. Chat history is not persisted.
- **Privacy:** no network calls apart from the model download, enforced by a
  test. `docs/PRIVACY.md` and `README.md` must state that AI is fully
  on-device, models come from Hugging Face, and indexes never leave the device.

## Phases (one PR each)

1. Model shortlist, evaluation suite (`evals/local-ai/`), benchmarks on Mac
   and a 6 GB iPhone. **Gate: user picks the models.**
2. Hide the cloud AI UI in the native apps. One switch,
   `CloudAIFeature.enabled` in `native-ios/Sources/NativeSearch.swift`
   (shared with macOS), gates every entry point.
3. Shared core in `packages/apple/`: download/lifecycle, MLX runtime,
   chunking + embedding index, hybrid search, pipelines.
4. macOS UI.
5. iOS UI and 6 GB iPhone device verification.

If no ≤2B model passes phase 1, revisit the Mac model size and device floor.

## Phase 1 pass bar

- Edits: correct result and no change outside the targeted region.
- Search: expected note in the top 5.
- Summaries: no invented facts; key facts present.
- Under 2 s to first token and at least 15 tokens/s on the 6 GB iPhone; no
  memory kills.

## History

On-device MLX/LiteRT models were tried in August 2026 (Qwen3-1.7B on macOS,
Gemma-4-E4B elsewhere, Qwen3.5-2B on iOS) and removed in `572775a`. The
cloud harness that followed (`src/lib/ai-harness*.ts`) relied on multi-step
tool loops, which small models handle poorly; hence the pipeline design.

## Phase 1 results (2026-11-25, M4 Mac, mlx-swift-lm 3.33.0)

Runner and fixtures: `evals/local-ai/` (40 synthetic notes in 9 languages,
186 tasks). All LLM outputs use grammar-constrained JSON
(`MLXGuidedGeneration`) except summaries.

### Harness changes that mattered (Qwen3.5-2B, answerable Ask 2/24 → 21/24)

- `sources` constrained to an enum of the provided note ids (models invented
  URL-style ids).
- Evidence-first Ask schema (`evidence` quotes → `answer` → `found` →
  `sources`); quotes are checkable against the notes.
- Explicit answer/summary language in the user message.
- Edits as `find`/`replace` pairs, where `find` must occur exactly once,
  instead of line numbers (models miscounted lines). Properties as an `ops`
  list.

### LLMs (126 tasks each; v4 harness for the top three, v3 for the rest)

| Model | Overall | Route | Ask | Unanswerable | Summ. | Edits (40) | TTFT | tok/s | Peak MB | License |
|---|---|---|---|---|---|---|---|---|---|---|
| Qwen3.5-2B 4-bit | 103 | 36/40 | 21/24 | 5/6 | 9/16 | 32 | 0.39 s | 76 | 2052 | Apache-2.0 |
| LFM3-1.7B 4-bit | 101 | 32/40 | 23/24 | 6/6 | 9/16 | 31 | 0.36 s | 63 | 1917 | LFM 1.0 (<$10M revenue) |
| Qwen3-1.7B 4-bit | 94 | 36/40 | 21/24 | 1/6 | 10/16 | 26 | 0.38 s | 81 | 1727 | Apache-2.0 |
| Qwen3.5-0.8B 4-bit | 72 | 35/40 | 20/24 | 1/6 | 3/16 | 13 | 0.17 s | 155 | 1322 | Apache-2.0 |
| LFM2.5-1.2B 4-bit | 68 | 33/40 | 16/24 | 0/6 | 0/16 | 19 | 0.23 s | 123 | 1253 | LFM 1.0 |
| MiniCPM5-1B 4-bit | 56 | 19/40 | 16/24 | 3/6 | 4/16 | 14 | 0.18 s | 114 | 1616 | Apache-2.0 |

Excluded: Gemma-4-E2B (≈5B raw parameters, 2.4–3.6 GB) and MiniCPM5-2B
(2.5B) exceed the 2B cap. Evidence quotes verified in the notes: LFM3 46/50,
Qwen3.5-2B 55/74, Qwen3-1.7B 19/41.

### Embeddings (60 queries, 17 cross-lingual; 40 fixtures + 635-note vault copy as distractors, 1,574 chunks)

| Model | Vector recall@5 | Top-1 | Index chunks/s | Download |
|---|---|---|---|---|
| EmbeddingGemma 2 (4-bit, incl. vision/audio) | 1.00 | 0.98 | 24 | 1.1 GB |
| EmbeddingGemma 300M (4-bit) | 1.00 | 0.98 | 34 | 0.17 GB |
| Qwen3-Embedding-0.6B (4-bit DWQ) | 0.97 | 0.93 | 12 | 0.34 GB |
| LFM2.5-Embedding-350M (4-bit; 11 languages, no Chinese) | 0.97 | 0.88 | 18 | 0.2 GB |
| BM25 alone | 0.73 | — | — | — |

Reciprocal-rank fusion with BM25 lowered recall@5 at every weight tried
(1.0 → 0.78, 0.5 → 0.82, 0.25 → 0.95 for EmbeddingGemma 2).

### iPhone probe (`evals/local-ai/probe-ios/`, 2026-11-25, iOS 27.2.1)

- **iPhone 18 Pro Max (12 GB):** EmbeddingGemma 300M indexed 148 chunks/s,
  5 ms per query, recall@5 1.00, 631 MB peak footprint. Qwen3.5-2B loaded in
  36 s (download included) at 1.2 GB; 24-task subset 19/24; median TTFT
  0.21 s (max 3.2 s); ~87 tok/s; 1.75 GB peak footprint.
- **iPhone 11 (A13, 4 GB):** MLX cannot run here. GPU kernel compilation
  fails (`XPC_ERROR_CONNECTION_INTERRUPTED`, open upstream issue
  ml-explore/mlx-swift#526); the CPU device rejects compiled kernels, and
  with compilation disabled it had not indexed 151 chunks after 30 minutes.
  Decision: the self-test gate above decides per device; the iPhone 11 is the
  test device for the fallback path.

Phase 1 closed 2026-11-25. Moved to later phases: the 6 GB iPhone check
(phase 5) and the real-vault question set (a pre-release check, not a gate).

## Phase 3 results (2026-11-25, `packages/apple/LocalAI`)

The eval runner now runs the production package (pipelines, verified model
store and loader, SQLite search index).

- **LLM (Qwen3.5-2B, production pipelines):** 104/126. Route 36/40, Ask
  21/24, unanswerable 5/6, summaries 9/16, edits 33/40 (find/replace 7/8 with
  one retry). Median TTFT 0.39 s, 78 tok/s, 2,052 MB peak.
- **Search (EmbeddingGemma 300M, 40 fixtures + 635-note vault copy, 1.5k
  chunks):** semantic recall@5 1.00; keyword fallback 0.75 (with the
  exact-match boost); about 52 ms per query including the query embedding.
- **Downloader:** a real download of EmbeddingGemma (210 MB) installed and
  verified in 7 s.
- **iPhone 11:** `LocalAISelfTest` reports *failed* in 1.8 s without a crash,
  so the device keeps keyword search.
- **iPhone 18 Pro Max (production probe):** the self-test passed in 1.1 s. The
  app's downloader fetched and verified both models over Wi-Fi in about 55 s.
  Search: semantic recall@5 1.00, keyword 0.75, 146 chunks/s, 16 ms per
  query, 690 MB peak. Qwen3.5-2B: 19/24 on the 24-task subset, median TTFT
  0.19 s (max 0.97 s), 87 tok/s, 1,733 MB peak footprint.

Still open for phases 4 and 5: Settings UI (download, delete, capability
message), wiring the index to vault changes, `BGProcessingTask` indexing on
iOS, and the 6 GB iPhone run.
