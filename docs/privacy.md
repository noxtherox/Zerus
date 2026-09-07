# Zerus privacy policy

Last reviewed: 7 September 2026.

## Your files

The native app reads and writes notes and vault metadata in folders you choose.
The browser development preview stores its virtual vault in browser local
storage. Choosing a folder managed by a sync provider also makes that provider's
storage and privacy rules relevant.

Zerus does not require a Zerus account. The current application code does not
include an analytics or advertising service. Diagnostic output can be written
locally; it is not an automatic remote crash-report submission service.

## Cloud AI

AI chat is optional. When you connect a provider and use cloud AI, prompts,
conversation history, selected note context, and information read by tools during
that conversation may be sent to the configured provider. Do not include content
you do not want that provider to process. Provider credentials are used to
authenticate requests; native builds use platform credential storage.

Supported defaults include [OpenAI](https://openai.com/policies/privacy-policy/),
[Anthropic](https://www.anthropic.com/legal/privacy), and
[OpenRouter](https://openrouter.ai/privacy). A custom endpoint is governed by its
operator's policy. OpenRouter may route requests to additional model providers.
Provider connections and requests expose ordinary network metadata such as your
IP address to the receiving service.

## Updates, links, and installation

Production desktop builds check GitHub for release metadata on launch and
periodically while running. This requests the configured `latest.json` release
file; it does not upload vault contents. GitHub receives normal network request
metadata. Downloading and installing an offered update requires user action.
There is currently no in-app setting to disable the automatic metadata checks.
Windows updater artifact publication is currently disabled even though the
shared desktop code can make these checks.

Opening external links contacts the chosen website through your browser. Notes
that reference remote images may contact their image host when rendered.
The Windows installer can download Microsoft's WebView2 Runtime if needed.
See [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
and [Microsoft's privacy statement](https://privacy.microsoft.com/privacystatement).

SignPath is used by the release process, not by the running Zerus app. Using a
signed installer does not send your vault to SignPath.

## Control and questions

You control the vault files and may back them up, move them, or delete them using
your file manager. Disconnect unused AI providers in Settings. On Windows,
uninstall Zerus through Settings > Apps > Installed apps; your separately stored
vault remains under your control.

For privacy questions, open an issue in the
[Zerus repository](https://github.com/noxtherox/Zerus/issues). Do not post API
keys, private notes, or other sensitive information in a public issue.
