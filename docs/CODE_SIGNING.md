# Code signing policy and SignPath activation

**Status: SignPath integration is prepared but NOT enabled.** WMT does not yet
claim SignPath Foundation approval or Authenticode signing for published releases.

If approved, free code signing is provided by
[SignPath.io](https://about.signpath.io/), with a certificate from
[SignPath Foundation](https://signpath.org/).

## Release roles and process

- **Authors/committers:** Maintainers with write access to
  [Chaython/Windows-Maintenance-Tool](https://github.com/Chaython/Windows-Maintenance-Tool).
- **Reviewers:** Maintainers reviewing proposed changes and outside pull requests
  before merging; the repository owner is responsible for ensuring reviews.
- **Release approver:** The repository owner, [@Chaython](https://github.com/Chaython),
  or explicitly designated trusted maintainers, must review and approve each
  release signing request in SignPath. GitHub permissions do not replace
  SignPath's signing approval.

Use multi-factor authentication on GitHub and SignPath. Changes to the
build workflow, signing configuration, and release scripts require review.
Never use the SignPath Foundation certificate to sign third-party binaries.
All signed WMT artifacts must originate from the official GitHub-hosted build.

## Privacy and networking

WMT includes operations that can contact Microsoft and third-party package,
game, and tool provider services to search for, download, install, and update
software. Some tasks may run automatically when users enable scheduling.
System diagnostics and activity logs may contain sensitive local paths or
configuration details. Review settings and logs before sharing them. The
[README](../README.md) describes these features and user controls.

This is a source/build integrity policy, not a substitute for a full
application privacy review or an assertion that no network connections occur.

## Activation (only after SignPath approval)

1. In SignPath, link the trusted build system **GitHub.com** and the project
   for this repository. Complete any required SignPath GitHub App setup.
2. Add `[.signpath/artifact-configurations/default.xml](../.signpath/artifact-configurations/default.xml)`
   as the project's **default artifact configuration**. It expects a ZIP
   archive containing only `WindowsMaintenanceTool.exe` and a
   `wmtVersion` parameter. Compare its metadata restrictions with the
   actual built PE's FileVersionInfo; adjust the build or template if needed.
3. Configure a **release-signing** policy in SignPath with trusted origin
   verification and manual approvers. Copy its actual slug.
4. In GitHub repository **Settings → Secrets and variables → Actions**,
   configure:

   | Type | Name | Value |
   | --- | --- | --- |
   | Secret | `SIGNPATH_API_TOKEN` | API token authorized for signing submissions |
   | Variable | `SIGNPATH_ORGANIZATION_ID` | Organization ID supplied by SignPath |
   | Variable | `SIGNPATH_PROJECT_SLUG` | Actual configured SignPath project slug |
   | Variable | `SIGNPATH_SIGNING_POLICY_SLUG` | Actual approved release policy slug |
   | Variable | `WMT_SIGNPATH_ENABLED` | Set to `true` **last** (unset/false = disabled) |

   Never commit SignPath tokens or certificates to the repository.

5. **Bump `$AppVersion` in `WMT-GUI.ps1` and publish a new version**.
   Do not rebuild or overwrite a previously published winget-linked release.
6. Trigger the **Build PS2EXE Release** workflow on `Main`. Review and
   approve its SignPath request promptly: the workflow currently waits up to
   60 minutes for SignPath and the job has a 90-minute limit. A missed
   approval causes the release job to fail; nothing should be published.
7. The workflow replaces the unsigned build with the returned signed EXE
   **only after a valid Authenticode signature is verified**, computes the
   final SHA-256, generates and verifies a Sigstore/GitHub attestation for
   that exact final executable, then publishes release assets and optionally
   submits winget/Chocolatey updates.

## Verification

On Windows, download the executable from the official [Releases](https://github.com/Chaython/Windows-Maintenance-Tool/releases)
page and inspect its Authenticode signature:

```powershell
Get-AuthenticodeSignature -LiteralPath .\WindowsMaintenanceTool.exe |
  Format-List Status,SignerCertificate,TimeStamperCertificate
```

A successful SignPath release should return `Status: Valid`. To verify
the independent GitHub build provenance, see
[README: Verify release provenance](../README.md#verify-release-provenance-sigstore--github-attestations).

**Security note:** neither Authenticode signing nor Sigstore provenance
guarantees that Windows Defender will accept a binary. Treat any detection
seriously, investigate it, and report legitimate false positives through the
vendor's review process.

## Foundation review

SignPath Foundation must approve WMT's functionality and project governance
under its [open-source signing conditions](https://signpath.org/terms.html).
WMT includes administrative and security-related operations: describe these
accurately in the application, do not remove safeguards to evade detection,
and let SignPath determine eligibility. This document is a preparation
checklist, not approval.
