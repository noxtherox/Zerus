# Code signing policy

## Status

Zerus is preparing to apply to the SignPath Foundation. Acceptance and production
signing have not been confirmed. Existing Windows downloads must not be assumed
to have a SignPath signature. Release notes identify whether a Windows installer
was signed or produced while enrollment was pending.

If the application is approved and signing is activated, the attribution will be:

Free code signing provided by [SignPath.io](https://signpath.io), certificate by
[SignPath Foundation](https://signpath.org).

This is planned attribution, not a claim of an existing sponsorship.

## Scope and origin

The initial integration signs the Windows x64 NSIS installer
`Zerus_<version>_x64-setup.exe` built from this public repository on GitHub-hosted
Actions runners. It verifies the returned installer's signature, publisher,
timestamp, product name, and version before making it a release artifact.

This is an **installer signature only**. The embedded application, CLI executable,
and generated NSIS uninstaller do not receive individual Authenticode signatures
in this integration. Signing the outer installer does not sign these embedded
executables. Broader coverage requires a separate build/sign/package sequence.
Third-party binaries are not signed as Zerus-owned software.

Production signing requires an authorized maintainer to review and approve every
request in SignPath. The signing policy must restrict origin to
`noxtherox/Zerus`, GitHub-hosted builds, and approved release refs. Pull-request
builds remain unsigned. Failed or denied signing requests must not fall back to
unsigned publication once signing is enabled.

## Responsibilities

Proposed roles for this single-maintainer project:

| Role | Maintainer |
| --- | --- |
| Author / committer | [Tiago Pereira (@noxtherox)](https://github.com/noxtherox) |
| Reviewer of external contributions | [Tiago Pereira (@noxtherox)](https://github.com/noxtherox) |
| Release signing approver | [Tiago Pereira (@noxtherox)](https://github.com/noxtherox) |

These roles do not imply independent review by multiple people. Before enabling
signing, the maintainer must enable MFA for GitHub and SignPath, configure manual
release approval, and confirm the Foundation's requirements. A CI token may
submit requests; it must not be able to approve them.

## Privacy

See the [privacy policy](privacy.md) for local storage, cloud AI, update checks,
and third-party services. The policy describes current behavior; it does not
claim all network access is opt-in.

See [Windows signing setup](windows-signing.md) for activation and verification.
