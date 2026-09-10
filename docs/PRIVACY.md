# Zerus privacy policy

Effective date: 10 September 2026

This policy describes Zerus for Windows, published by noxtherox, including the optional AI features in version 0.3.18.

## Your files and local data

Zerus is a local-first Markdown application. Notes, attachments, task information, vault metadata, and conversation history are stored on your device in the folders you choose or in local application storage. Ordinary note editing does not require a Zerus account or upload your vault to a Zerus-operated server.

If you put your vault in a folder managed by OneDrive, another sync service, or a shared drive, that service may process your files according to its own settings and privacy policy. Zerus does not control those services.

## Optional AI features

AI chat is optional. When you use it, Zerus sends your prompt, relevant conversation history, selected note excerpts, folder context, and documents or images you include to the AI provider you select. Depending on the feature, AI requests may also include information needed to list models or operate on the notes you authorize. Do not include information you do not want that provider to receive.

Supported configurations include OpenAI, Anthropic, OpenRouter, and compatible API endpoints. The ChatGPT through Codex option uses the installed Codex app-server and its sign-in flow. Those services process requests under their own terms and privacy policies. Provider retention and use of submitted content depend on the provider, your account, and your settings; Zerus does not set a universal retention period for provider-held data. Providers also receive connection information such as your IP address.

API credentials are kept using the operating system's secure credential storage when supported, rather than in vault files. Conversation content and attached context are saved locally with the vault so you can resume conversations. Removing an item locally does not delete copies already processed by an AI provider.

## Network connections, updates, and diagnostics

Zerus does not include advertising or a third-party behavioral analytics SDK in this Windows release. Its publisher does not receive your notes through a Zerus-hosted synchronization service. Optional AI features and external links connect to the services you choose.

Microsoft Store handles acquisition and updates for the Store version. Microsoft may collect Store, device, installation, and diagnostic information under Microsoft's privacy statement, and may make app-level reports available to the publisher. The Store version disables Zerus's separate in-app update checks. WebView2, Windows, and any third-party software you use may collect their own diagnostic information according to their settings and policies.

Local application settings, logs, or recovery data may remain on your device. If you voluntarily share a log, screenshot, support report, or file with the project, the information you include is processed by the support platform and can be viewed by the publisher. Public GitHub issues are visible to everyone.

## Your choices and retention

You can use note editing without enabling AI, choose the context included in AI requests, remove saved credentials through the app's provider settings, and manage your vault files using the app or your file manager. Deleted items may remain in local trash or recovery history; recently deleted chats have a 30-day recovery policy. Backups and sync services may retain additional copies.

Uninstalling Zerus does not necessarily remove vaults, exported files, backups, or data retained by providers. To remove that information, delete the relevant local files and use the controls offered by your sync or AI provider. Keep backups of files you wish to retain.

## Contact and changes

For privacy questions, open a request at https://github.com/noxtherox/Zerus/issues without including private notes, credentials, government identifiers, or other sensitive information. You may request a private contact channel there before sharing personal details.

This policy may be updated as the application changes. The effective date above identifies the current revision.
