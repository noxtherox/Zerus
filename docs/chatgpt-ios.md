# ChatGPT on iOS

Open **Chat → Chat model → ChatGPT**, then **Continue with ChatGPT**. Authorize
ChatGPT plan usage with an eligible Plus or Pro account and select a model from
that account's live catalog using the model dropdown, then **Save ChatGPT model**.
**Refresh ChatGPT models** reloads the catalog. Zerus sends your question and selected note context
to OpenAI. Eligible requests use your shared ChatGPT allowance; **Manage usage**
opens ChatGPT's controls. This connection does not provide access to your
ChatGPT conversations or memories.

Saved accounts appear in settings with distinct labels. **Add another account**
registers another account/workspace; selecting a saved account reuses its issued
client registration. Each account keeps its own credentials and selected model.
**Reconnect ChatGPT** repeats validated authorization for the active account.
**Cancel sign-in** closes an outstanding authorization attempt.

**Sign out** stops requests, attempts to revoke the renewable session, and clears
that account's local tokens. Zerus retains its registration and this device's
host ID for a later sign-in. If remote revocation cannot be confirmed, settings
say so and direct you to disconnect Zerus through ChatGPT settings.

## Notes and budgets

ChatGPT uses the same notes agent as other providers: selected context, scoped
read tools, Ask/Review/Edit modes, concrete proposals, approval checks, durable
receipts, and Stop. Native function tools run through the existing scope and
permission checks. ChatGPT credentials and account selection remain local to
the device and are never written to `.zerus/ai-settings.json`.

The iOS connection uses the public Responses API directly. The desktop ChatGPT
option continues to use the installed Codex app-server. Both share the existing
ChatGPT provider profile type; the mobile connection uses native function tools
instead of the desktop transport's text fallback.

The ChatGPT HTTP flow requires `store: false`, `stream: true`, explicit history,
and namespaced tools. It rejects a hard `max_output_tokens` ceiling and
`temperature`; Zerus omits those fields. The output setting is advisory for
ChatGPT. Step, context, elapsed-time and total-token checks still apply between
calls, using reported usage when available and estimates otherwise. One call
may exceed the requested output allowance. Images are supported when the
selected model accepts them; existing document extraction supplies text context.
This integration does not add hosted file search, image generation or audio APIs.

## Native implementation

The mobile-vault plugin owns authorization and HTTPS inference. Its authentication
browser returns to an ephemeral `http://127.0.0.1:<port>/auth/callback` listener
bound only to loopback. State, nonce, PKCE, the exact callback URI, issued client
ID, ID-token signature, issuer, audience, expiry and inference scopes are verified
before credentials become active.

The native Keychain record stores accounts independently, including access,
refresh and ID tokens, issued registrations, selected models and a stable host
ID. It uses device-only Keychain protection. Refreshes are serialized per account
and replacement credentials are saved atomically. Tokens never reach JavaScript,
the vault, inference URLs or logs. A retained ID-token hint is sent only to
OpenAI's official reauthorization URL.

Model discovery calls the public `/v1/models` endpoint with the selected account's
token and `client_version=0.159.2`. This is the catalog compatibility level verified
with the native Responses transport, independent of Zerus's app version. Keep it
explicit: the unversioned endpoint returned an older catalog on the test account,
even with HTTP cache bypass. The request bypasses local HTTP caching; the picker
preserves server order, names and slugs and includes only `visibility: "list"`.
Models and account eligibility remain server-controlled. Do not replace discovery
with a static list or advertise a maximal/future client version.

The byte-based SSE decoder preserves blank event boundaries and requires
`response.completed`. Completed output items are collected from item events
when the final event omits its output array. Native continuation retains exact
reasoning and tool-call output, then pairs it with the existing agent's actual
tool result and call ID. Encrypted reasoning stays in a bounded native memory
cache and is cleared on account changes and sign-out.

## Verification

```sh
swift test --package-path src-tauri/plugins/mobile-vault/ios/ChatGPTCore
pnpm test
pnpm typecheck
pnpm build
cargo test --manifest-path src-tauri/Cargo.toml -p tauri-plugin-mobile-vault
```

The core tests cover real loopback HTTP delivery, signed RSA/EC identities,
callback rejection, interrupted streams, blank SSE boundaries, empty terminal
output, notes-agent tool/usage continuation, and restoring the native ChatGPT
connection without falling back to an API-key provider. The shared agent regression
checks that a native ChatGPT connection advertises tools and executes a tool
round trip. The Rust permission regression uses Tauri's actual ACL resolver to
verify that the main iOS webview can register and remove native stream listeners
under the plugin's default permissions. The main app's signed development build was installed and launched
on iPhone 15 Nox with iOS 27.0 on 2026-10-02. Its actual scene manifest and
signature passed verification, and launch produced no new Zerus crash or Jetsam
report. Main-app sign-in, the model dropdown and chat after the stream-listener
permission fix were confirmed on that device. A native catalog comparison found
that adding the compatibility parameter exposed GPT-6.1 Sol, GPT-6 Sol and GPT-6
Luna for the same account; cache bypass alone did not change its five visible
choices. The corrected native bridge returned eight visible choices, and GPT-6.1
Sol, GPT-6 Sol and GPT-6 Luna each completed a streamed greeting with the account's
native connection. The temporary inspection code and device report were removed
after verification. The native catalog regression failed without the parameter, then passed
after the discovery repair. Note editing still requires separate physical-device
verification.
App Store build numbers and TestFlight uploads are handled separately by the
repository's release commands.

The former companion prototype has been removed. Its renewable session was
revoked, its Keychain records cleared, and its iPhone app uninstalled. The OAuth
and streaming checks now belong to the production native core package.

Official references: [registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
[accounts and refresh](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
[models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference),
[current preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
