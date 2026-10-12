# ChatGPT desktop compatibility, 12 October 2026

Baseline: repository commit `64c256a`, 18 September 2026. Local installation:
ChatGPT 26.1007.21159, bundled codex-cli 0.162.0-alpha.17.2, codex-auth 0.2.10.

## Published changes reviewed

The [official changelog](https://learn.chatgpt.com/docs/changelog) records
GPT-6 Sol/Luna availability (22 September), a macOS security fix in
26.924.20706 (25 September), GPT-6.1 Sol (29 September), and Ultrafast
availability (8 October). These release notes do not document the internal CLI
bundle relocation. Model availability changes do not establish a login failure.

## Locally verified compatibility break

`Contents/Resources/codex` and `Contents/Resources/node` no longer exist.
The CLI is now at `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`.
The old application PATH reproduces codex-auth's executable-not-found error.
An isolated login dispatch probe reaches the installed CLI with the corrected
PATH and deliberately exits before authentication. No account tokens are used.

One executable resolver now supports both layouts, supplies login's PATH and
CODEX_CLI_PATH, and supplies bundled/reference marketplace reconciliation.
Node installations under nvm are discovered instead of assuming v20.11.0.
The installed CLI still supports plugin add/remove and marketplace commands.

The missing CLI also prevented reference-plugin restoration after a successful
account switch. This is a confirmed defect, but the user's original alert text
was unavailable, so it cannot establish that every reported alert had this cause.

## Verification and remaining checks

Infrastructure suite: 980 assertions pass. Build, reset-logic self-test, and
install-script restart test pass. The AppKit interaction suite fails its
confirmation-row hit-test assertion on both unchanged HEAD and the modified
code in the current environment. No UI implementation was changed.

Installation into `/Applications/Codex Account Switcher.app` was verified: signature,
lifecycle monitor, running process, and byte-for-byte executable match all pass.

Completing browser authentication and switching a real account remain manual
end-to-end checks; restarting ChatGPT would interrupt the active repair chat.
