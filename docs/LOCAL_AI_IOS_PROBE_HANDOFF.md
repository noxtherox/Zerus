# Zerus Local AI iOS Probe — Session Handoff

Status: ready for a separate implementation session
Prepared: 2026-08-03
Purpose: prove or reject local-model inference on the physical iPhone before integrating anything into Zerus

## Handoff prompt

Create a standalone SwiftUI iOS feasibility app named `ZerusLocalAIProbe`. Do not modify the Zerus application or its vault. The probe must download and run small MLX language models on-device, stream responses, select relevant notes from a fixed synthetic fixture set, produce a constrained proposed note action, and record performance on the physical `iPhone 15 Nox`.

The result is an engineering experiment, not a production feature. Finish with measured evidence and a clear recommendation about whether Zerus should proceed with MLX Swift, try `llama.cpp`, or stop.

## Non-negotiable boundaries

- Work in a separate sibling directory: `/Users/noxtherox/dyad-apps/Zerus-LocalAI-iOS-Probe`.
- Do not add the probe beneath the Zerus repository.
- Do not modify, clean, reset, stage, commit, or otherwise disturb `/Users/noxtherox/dyad-apps/Zerus`.
- Do not open, index, copy, or write to the real Zerus vault.
- Use only synthetic Markdown fixtures bundled with the probe.
- Do not add a backend, API key, analytics SDK, telemetry service, login, ChatGPT integration, or Claude integration.
- Model traffic is allowed only to download model assets after the user explicitly taps a download control showing the model size.
- Once downloaded, inference must work in Airplane Mode.
- The model may propose an edit, but the probe must never edit a file.
- Keep model weights out of iCloud backup and provide visible unload/delete controls.
- Preserve exact source revisions in the README or dependency lockfile so the result can be reproduced.

## Current local environment

Verified on 2026-08-03:

- Xcode: `26.6` (`17F113`)
- macOS: `27.0` (`26A5388g`)
- Physical test device: `iPhone 15 Nox`
- Device model: base iPhone 15 (`iPhone15,4`), not iPhone 15 Pro
- CoreDevice identifier: `FF4D5160-DA79-5DFA-9277-3A77B49A23FF`
- Device was paired but unavailable during handoff preparation; reconnect, unlock, and verify Developer Mode before the physical run.
- Zerus currently targets iOS 16. Current MLX Swift packages require iOS 17, so the standalone probe should target iOS 17 or later. Do not change Zerus's deployment target during this experiment.

The base iPhone 15 does not qualify for Apple Intelligence according to Apple's current compatibility list. Do not use Apple's system Foundation Model as the main probe runtime.

## Project shape

Create a normal Xcode SwiftUI application rather than a Tauri application:

- Product name: `ZerusLocalAIProbe`
- Suggested bundle identifier: `com.zerus.local-ai-probe`
- Platform: iOS
- Minimum deployment target: iOS 17
- Interface: SwiftUI
- Language: Swift
- Tests: unit tests required; UI tests optional
- Signing: use the user's existing development team; do not alter unrelated certificates or profiles

Suggested internal boundaries:

```text
ZerusLocalAIProbe/
  App/
  Models/
    LocalModelDescriptor.swift
    LocalModelManager.swift
    GenerationMetrics.swift
  Inference/
    LocalInferenceSession.swift
    StructuredResponse.swift
  Fixtures/
    FixtureNote.swift
    FixtureNotes.json
    EvaluationCases.json
  Features/
    Models/
    Chat/
    Evaluation/
  Tests/
  README.md
  RESULTS.md
```

Names may change if the selected MLX APIs make another boundary more natural, but model management, inference, fixtures, evaluation, and UI should remain separated.

## Runtime and dependency choice

Start with MLX Swift rather than `llama.cpp`.

Use tagged package releases, not floating `main` branches:

- `https://github.com/ml-explore/mlx-swift-lm`
- Start from the current documented `3.31.3` release line, or the newest compatible stable tag only if the next session verifies that it supersedes this version.
- Add the Hugging Face downloader and tokenizer packages required by that tagged MLX Swift LM version.
- Record the resolved versions in `Package.resolved` and the probe README.

The current MLX packages provide Swift LLM APIs, Hugging Face loading, token streaming, tool-call support, embeddings, and guided JSON/grammar generation. Use the smallest dependency surface that can complete the probe.

If Qwen3 fails to load because of a real compatibility issue, document the exact error and try the preconfigured `gemma3_1B_qat_4bit` registry model as one bounded fallback. Do not silently switch models.

## Models to test

Test in this order:

1. `mlx-community/Qwen3-0.6B-4bit`
   - Current repository size: approximately 351 MB
   - Purpose: establish that download, load, streaming, cancellation, structured output, and offline execution work
2. `mlx-community/Qwen3-1.7B-4bit`
   - Current repository size: approximately 984 MB
   - Purpose: compare instruction following, note selection, action validity, latency, memory, and heat against 0.6B

Do not download either model automatically. Present its approximate size and require a user tap. Download 0.6B first; only download 1.7B after the first model has completed a physical-device run.

Store downloaded assets in an application-owned model directory. Mark the directory or model files as excluded from backup. The UI must show:

- Not downloaded
- Downloading with progress
- Downloaded
- Loading
- Ready
- Generating
- Failed with a useful error
- Unload from memory
- Delete downloaded model

Do not log tokens, note bodies, generated answers, file paths containing user information, or model credentials. Synthetic fixture IDs and aggregate timings are safe to record.

## Synthetic note fixtures

Bundle 10–15 small Markdown notes covering deliberately overlapping subjects. Include at least:

- Project Aurora launch plan
- Project Aurora meeting notes
- Project Borealis launch plan
- Lisbon travel checklist
- Porto travel ideas
- Local AI research notes
- Mobile release checklist
- Grocery list
- Book notes
- Weekly review

Each fixture requires:

- Stable ID, such as `note-aurora-launch`
- Title
- Type
- Two or three properties
- Markdown body
- Revision number

Keep the complete fixture set small enough to fit directly in a prompt for this first probe. This intentionally tests model selection and structured behavior before adding an embedding index.

## Required evaluation cases

Provide at least 12 repeatable cases with expected note IDs. Include ambiguous and negative requests:

1. “Which notes should I use to prepare the Aurora launch?”
2. “Summarize the decisions from the latest Aurora meeting.”
3. “Compare Aurora and Borealis launch risks.”
4. “What do I still need to pack for Lisbon?”
5. “Turn my local AI research into three next actions.”
6. “Update the mobile release checklist with an offline inference check.”
7. “Find my notes about travel.”
8. “Find the project launch note, but not Aurora.”
9. “Draft a new note from the weekly review.”
10. “Delete all my notes.”
11. “Work on a note that does not exist.”
12. A Portuguese query targeting one of the travel fixtures.

The destructive request must be refused or represented as requiring confirmation. The nonexistent-note request must not invent an ID.

## Structured response contract

Do not parse arbitrary prose to discover tool actions. Require guided or schema-constrained output matching a small contract similar to:

```json
{
  "answer": "Short user-facing response",
  "selectedNoteIds": ["note-aurora-launch"],
  "actions": [
    {
      "type": "propose_patch",
      "noteId": "note-mobile-release",
      "expectedRevision": 3,
      "replacementMarkdown": "# Mobile release checklist\n..."
    }
  ]
}
```

Allowed action types for the probe:

- `none`
- `propose_patch`
- `propose_create`
- `needs_confirmation`

Reject the result if:

- JSON/schema validation fails
- A selected or action note ID is not in the fixture set
- A revision is missing for a patch
- More than five notes are selected without an explicit comparison request
- An action attempts deletion
- The response tries to execute a command or access a path

Display invalid output as an evaluation failure. Do not repair it invisibly when measuring model reliability.

## Required UI

Keep the UI utilitarian. It only needs three tabs or screens.

### Models

- Device and OS summary
- Model cards with sizes and status
- Download, cancel, load, unload, and delete controls
- Current memory-pressure warning if exposed by iOS

### Chat

- Fixed-model picker
- Prompt field
- Synthetic note chips showing the model's selected notes
- Streaming answer
- Parsed proposed action in a readable preview
- Raw structured result behind a disclosure control
- Stop-generation control
- Clear-session control

### Evaluation

- Run one case
- Run the complete fixed suite
- Expected versus selected note IDs
- Valid/invalid structured result
- Timing metrics
- Export a redacted `RESULTS.md`-friendly summary through the share sheet or copy control

## Metrics to capture

Measure both models on the physical device, not only the simulator:

- Model download size
- Cold model-load time
- Warm model-load time if meaningfully different
- Prompt token count
- Time to first generated token
- Total generation time
- Generated token count
- Generation tokens per second
- Peak memory or the best available process-memory approximation
- Cancellation latency
- Whether the app receives a memory warning
- Whether the device becomes noticeably warm during five consecutive cases
- Battery percentage before and after the fixed evaluation run
- Structured-response validity rate
- Exact note-selection precision and recall across the fixed cases
- Whether the same downloaded model works in Airplane Mode after relaunch

Label measured values, estimates, and unavailable metrics distinctly. Do not manufacture a metric that iOS does not expose reliably.

## Target decision thresholds

These are product targets, not claims about expected performance:

- 100% valid JSON/schema output for the fixed suite after no more than one documented prompt revision
- No invented note IDs
- No unconfirmed destructive action
- At least 80% exact note-set accuracy across the fixed suite
- Median time to first token under 3 seconds
- Sustained generation of at least 8 tokens/second
- Stop button takes effect within 1 second
- No termination from memory pressure during five consecutive cases
- Successful offline generation after force-quitting and reopening the app

Record the results even if the probe misses every target. Do not tune the evaluation fixtures after seeing failures merely to improve the score.

## Build and validation sequence

1. Confirm the Zerus worktree remains untouched and record its initial `git status --short` only for comparison.
2. Create the standalone project in the sibling directory.
3. Add pinned Swift package dependencies.
4. Build the project for an iOS simulator before downloading a model.
5. Add synthetic fixtures, schema validation, and unit tests.
6. Implement explicit model download and deletion.
7. Run Qwen3 0.6B in the simulator only as a smoke test; simulator speed is not product evidence.
8. Reconnect and unlock `iPhone 15 Nox`; confirm it appears as available.
9. Build, install, and launch on the physical iPhone.
10. Download and evaluate Qwen3 0.6B through the app UI.
11. Verify a relaunch and Airplane Mode run.
12. Show the user the measured 0.6B result and the approximately 984 MB size before downloading 1.7B.
13. If authorized, download and evaluate Qwen3 1.7B.
14. Run unit tests and the full fixed evaluation suite.
15. Produce `RESULTS.md` with commands, package versions, device/OS, metrics, failures, screenshots if useful, and the final recommendation.
16. Compare the original and final Zerus `git status --short`; they must be identical.

Do not claim physical-device validation from a simulator run. Do not claim offline behavior unless network access was actually disabled after a clean relaunch.

## Required tests

At minimum, add deterministic tests for:

- Fixture IDs are unique.
- Evaluation cases reference existing fixture IDs.
- Valid structured responses decode correctly.
- Unknown note IDs are rejected.
- Missing revisions are rejected for patches.
- Delete actions are rejected.
- Too many selected notes are rejected unless explicitly allowed.
- Downloaded-model metadata survives relaunch.
- Deleting a model removes its local assets and leaves fixtures untouched.

Model-quality evaluation itself belongs in the on-device evaluation runner, not a brittle unit test.

## Stop conditions

Stop and report rather than expanding scope if:

- The tagged MLX packages cannot build with Xcode 26.6.
- Resolving MLX requires changing Zerus.
- Qwen3 requires an unreviewed fork or patch to MLX.
- The 0.6B model cannot load on the physical iPhone.
- The app is repeatedly killed for memory pressure.
- Model downloading requires credentials, a custom backend, or accepting unexpected terms.
- The physical device remains unavailable after ordinary pairing, unlock, trust, and Developer Mode checks.

A failure is a valid probe result. Do not switch frameworks, add a server, or integrate with Zerus inside the same session unless the user explicitly expands the task.

## Final deliverables from the implementation session

- Standalone project at `/Users/noxtherox/dyad-apps/Zerus-LocalAI-iOS-Probe`
- Buildable Xcode project
- `README.md` with exact setup and reproduction steps
- `RESULTS.md` with measured simulator and physical-device evidence kept separate
- Unit tests and their actual result
- Physical-device screenshot or short recording if the run succeeds
- Clear recommendation:
  - proceed with MLX Swift;
  - run a separate `llama.cpp` comparison;
  - use only embeddings/local search;
  - or stop pursuing local generation on the base iPhone 15
- Confirmation that the Zerus worktree was not changed

## Sources to re-check before implementation

- [MLX Swift](https://github.com/ml-explore/mlx-swift)
- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm)
- [MLX Swift examples](https://github.com/ml-explore/mlx-swift-examples)
- [Qwen3 0.6B MLX 4-bit](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit)
- [Qwen3 1.7B MLX 4-bit](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit)
- [Qwen3 1.7B base model card](https://huggingface.co/Qwen/Qwen3-1.7B)
- [llama.cpp iOS SwiftUI example](https://github.com/ggml-org/llama.cpp/blob/master/examples/llama.swiftui/README.md)
- [Apple Foundation Models availability](https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models)
- [Apple Intelligence device requirements](https://support.apple.com/en-us/121115)

These dependencies and model repositories change. The implementation session should verify current stable versions and sizes before downloading, while preserving the experiment's stated model identities and scope.
