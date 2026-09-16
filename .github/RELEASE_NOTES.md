Requires the official CLIs and reads Claude Code usage as structured data.

- Meterlet no longer uses the CLI bundled with the ChatGPT/Codex desktop app or the Code runtime downloaded by Claude desktop, and no longer retries a second installation after a sign-in error. Install Codex CLI and Claude Code CLI separately, or choose the executable in Settings.
- Claude Code usage comes from the structured `usage_report` output of `claude -p "/usage"` instead of the interactive `/usage` screen. This fixes the Fable row going missing when the CLI redrew the screen. Claude Code 2.1.273 or later is required; older versions show an update prompt.

**Apple Silicon · macOS 14 or later.** The release ZIP is Developer ID-signed, notarized by Apple, and stapled. Its SHA-256 checksum and the signed Sparkle update feed are attached. CI development artifacts are not release downloads.

Meterlet 0.2.0 or later installs this release from Check for Updates. Earlier builds need the ZIP: quit Meterlet and move the new Meterlet.app to Applications.

The Claude Code flow is verified against Claude Code 2.1.273 with a signed-in Claude Max account, including the session, weekly, and Fable windows. The Codex flow is unchanged and covered by tests against a recorded `account/rateLimits/read` response.

See [README](https://github.com/moguone/meterlet#readme) for setup and limitations.
