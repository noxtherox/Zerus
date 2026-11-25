# Zerus local-AI evaluation corpus

A small synthetic, multilingual corpus for benchmarking on-device LLMs (≤2B
parameters) and embedding models on Zerus note workflows: hybrid retrieval,
grounded Q&A with citations, summarization, single-note edits and request
routing.

**All content is fictional.** People, companies, venues, books, amounts and
dates are invented; any resemblance to real persons or organisations is
coincidental. Real cities and landmarks appear only as travel settings.

## Layout

| Path | Contents |
|---|---|
| `fixtures/notes/<note-id>.md` | 40 Zerus Markdown notes (YAML frontmatter + body) |
| `fixtures/manifest.json` | `{note-id: {lang: [codes], type}}` — language(s) and kind of each note |
| `tasks/retrieval.jsonl` | 60 retrieval queries |
| `tasks/ask.jsonl` | 30 grounded Q&A items (6 unanswerable) |
| `tasks/summarize.jsonl` | 16 summarization items |
| `tasks/edit.jsonl` | 40 edit items, 8 per kind |
| `tasks/route.jsonl` | 40 routing items |
| `validate_fixtures.py` | Consistency checks; run `python3 -I evals/local-ai/validate_fixtures.py` |
| `runner/` | Swift harness that runs models against these files |

Notes: 10 English, 7 Portuguese, 4 Spanish, 4 French, 4 German, 3 Japanese,
3 Simplified Chinese, 2 Italian, 3 mixed (English + Portuguese/German
sections). They include a ~1,600-word research note, short notes under 80
words, and deliberate distractors: three Lisbon notes (2022 trip, 2025 trip,
2026 offsite), two "Atlas" projects, and recipes/shopping lists that share
ingredients.

## Schemas

All task files are JSON Lines; `id` is unique within each file. Language codes
are ISO 639-1 (`en`, `pt`, `es`, `fr`, `de`, `ja`, `zh`, `it`).

**Matching.** Text checks are case-, accent- and width-insensitive substring
matches. A `contains`/`must_include` element is either a string (must appear)
or a list of alternatives (any one must appear). `must_not`/`not_contains`
strings must not appear.

- **retrieval** — `{"id","lang","query","expected":["note-id",...]}`. Every
  `expected` note must be in the top 5. Includes keyword and paraphrased
  queries; 17 are cross-lingual (query language ≠ note language).
- **ask** — `{"id","lang","query","notes":[...],"answerable","must_include":[[alts]...],"must_not":[...]}`.
  `notes` is the context passed to the model (the first id holds the answer;
  others are distractors). Answers are expected in the query language.
  Unanswerable items have empty `must_include` and list tempting fabrications
  in `must_not`.
- **summarize** — `{"id","lang","note","max_words","must_include","must_not"}`.
  `lang` is the language the summary must be written in (4 items differ from
  the note's language). For Japanese/Chinese, count about two characters per
  word.
- **edit** — `{"id","kind","note","selection","instruction","lang","expect"}`;
  `lang` is the instruction's language.
  - `rewrite_selection`: `selection` is an exact, unique substring of the note
    body. `expect.contains`/`not_contains` apply to the rewritten selection.
  - `append`: `expect.contains` applies to the appended text.
  - `instruction`: targeted in-place edit, `selection` null.
    `expect.contains`/`not_contains` apply to the edited note;
    `expect.preserve` strings must remain byte-identical.
  - `create`: `note` null. `expect.title_contains` and `expect.contains`
    apply to the new note's title and body.
  - `properties`: frontmatter change. `expect.properties` gives expected final
    values (lists compared as sets), `removed_properties` must be gone and
    `preserve_body: true` means the body must not change.
- **route** — `{"id","lang","request","expected":"ask"|"summarize"|"edit"}`.
  `edit` covers create, append and property changes.

## Validation

`validate_fixtures.py` (stdlib only) checks that JSON parses, ids are unique,
counts and kinds match the spec, every referenced note exists, selections and
`preserve` strings occur exactly once, instruction checks are not already
satisfied by the unedited note, and `must_include` groups for answerable,
same-language ask/summarize items occur in the source notes. It also prints
per-file language counts.

## Runner

`runner/` runs the **production** code from `packages/apple/LocalAI`: the
pipelines (prompts, schemas, retries), the verified model store and loader,
and the search index. Changing a prompt in `ZerusLocalAICore/Prompts.swift`
therefore needs an eval run.

```sh
cd evals/local-ai
xcodebuild -scheme ZerusAIEval -destination 'platform=macOS' \
  -derivedDataPath runner/.build/xcode -skipMacroValidation \
  -skipPackagePluginValidation -configuration Release build   # from runner/
./runner/.build/xcode/Build/Products/Release/zerus-ai-eval retrieval [--extra-notes local/vault-copy]
./runner/.build/xcode/Build/Products/Release/zerus-ai-eval llm --models qwen3.5-2b
./runner/.build/xcode/Build/Products/Release/zerus-ai-eval download-test
```

Production models live in `local/models` (gitignored) as a
`LocalAIModelStore`: seeded from the Hugging Face cache when the pinned
snapshot is there, otherwise downloaded with `LocalAIModelDownloader`; every
file is checksum-verified either way. Other `--models` candidates load from
the Hugging Face cache for comparison only. `probe-ios/` runs the same code on
an iPhone, including the MLX self-test that gates on-device AI.
