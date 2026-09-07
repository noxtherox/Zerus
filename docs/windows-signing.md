# Windows signing with SignPath

## Enrollment status

Repository preparation only. No SignPath account, approved application,
certificate, or successful signed build is implied by these files.

The first phase signs the NSIS installer only; see the
[code signing policy](code-signing-policy.md) for the exact coverage.
Windows Authenticode signing is separate from Tauri updater signatures and Apple
notarization. It identifies the publisher but does not guarantee immediate
SmartScreen reputation.

## Application draft

Apply at <https://signpath.org/apply>. Use these reviewed project facts:

| Field | Value |
| --- | --- |
| Project name | Zerus |
| Repository / homepage | https://github.com/noxtherox/Zerus |
| Download page | https://github.com/noxtherox/Zerus/releases |
| Privacy policy | https://github.com/noxtherox/Zerus/blob/main/docs/privacy.md |
| Tagline | A local-first Markdown notes app built around folders, links, and files you own. |
| Maintainer | Individual: Tiago Pereira (@noxtherox), Portugal |
| Build system | GitHub Actions, GitHub-hosted Windows runners |
| License | MIT |
| Discovery | ChatGPT / Codex; Microsoft Windows code-signing documentation |

Description:

> Zerus is an open-source notes application that turns a folder of Markdown
> files into a structured knowledge base. It supports linked notes, properties,
> search, and file organization while keeping the user's content in ordinary
> files. Optional AI features use a provider selected by the user. Windows
> installers are built from the public source repository using GitHub Actions.

Reputation (be candid; acceptance is discretionary):

> Zerus is an early-stage project with a public MIT-licensed repository, active
> development, and downloadable Windows releases. The repository was created
> on 11 August 2026. At preparation on 7 September 2026 it had no GitHub stars or
> forks; no independent media coverage or broad adoption is claimed. Build history:
> https://github.com/noxtherox/Zerus/actions/workflows/windows.yml . Downloads:
> https://github.com/noxtherox/Zerus/releases .

Before submitting:

1. Publish the policy and privacy links, and add a code-signing-policy link to
   the current download/release page without claiming existing signatures.
2. Review the proposed roles and MFA requirements with the maintainer.
3. Confirm SignPath accepts the installer-only scope and current network
   behavior. In particular, automatic update checks have no opt-out today;
   privacy notice during installation / an opt-out may be required under the
   Foundation's data-transfer conditions. Do not attest that all requirements
   are satisfied without resolving this with SignPath.
4. Enter the maintainer's chosen email address. A Microsoft account is not
   required: SignPath supports Google, Microsoft, and email/password login.
5. The maintainer must review the terms and personal-data consent before the
   application is submitted. Marketing consent is optional.

## Configure after acceptance

1. Install the SignPath GitHub App for `noxtherox/Zerus` and connect GitHub.com
   as the project's trusted build system.
2. Create the project and an artifact configuration with slug
   `windows-installer`, using [the XML](../.signpath/windows-installer.xml).
   It accepts exactly one version-specific x64 installer with product name
   `Zerus` and matching product version. Validate it in SignPath's XML editor.
3. Create the production signing policy using the Foundation certificate. Require
   manual approval by the maintainer, trusted build verification, and origin
   restrictions to this repository and approved refs (`v*` release tags;
   explicitly approved `main` builds for the first manual verification).
4. Create a CI submitter token scoped to this project/policy and save it as the
   GitHub Actions secret `SIGNPATH_API_TOKEN`. Never commit it or paste it into
   an issue or application draft.
5. Set repository Actions variables `SIGNPATH_ORGANIZATION_ID`,
   `SIGNPATH_PROJECT_SLUG`, and `SIGNPATH_SIGNING_POLICY_SLUG` to the actual
   assigned values. Do not invent an organization ID or assume a policy name.

## First signed build and activation

Run **Windows release installer** (`windows-signpath.yml`) manually from the
approved ref. Manual runs always require signing and fail early if configuration
is missing. Approve the request in SignPath within the workflow's one-hour
approval wait. This workflow creates an artifact; it does not publish a release.

The Windows runner checks Authenticode trust, the exact publisher name
`SignPath Foundation`, a timestamp, and the installer name/product/version.
Download `zerus-windows-nsis` and test installation and uninstallation on Windows.
The similarly named `zerus-windows-nsis-unsigned` artifact is the unsigned input
for provenance verification and must not be distributed as the signed result.

Only after this succeeds, set repository variable `SIGNPATH_ENABLED` to `true`.
Tagged releases then use the same signing workflow, and publication depends on
its success. Missing credentials, approval denial, timeouts, or failed signature
verification stop publication. There is no unsigned fallback when enabled.
Before activation, tagged releases preserve the unsigned Windows build and say
so explicitly in their release notes. Pull-request builds stay unsigned.

Update the public policy's status and attribution after acceptance and the first
successful production signature. No private signing key belongs on this Mac or
in GitHub; SignPath manages the signing key.

## References

- [Foundation terms](https://signpath.org/terms)
- [GitHub integration](https://docs.signpath.io/trusted-build-systems/github)
- [Artifact configuration](https://docs.signpath.io/artifact-configuration/syntax)
- [Microsoft code-signing guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)
