Fixes Claude Code usage collection with recent CLI releases.

- Works with Claude Code 2.1.273. The probe no longer passes `--settings`, which made the CLI show its first-run setup screen and left Meterlet reporting "complete the CLI setup" for signed-in users.
- Loads plan usage again. The previous `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` restriction also blocked the `/usage` data; telemetry, error reporting, the bug command, and the auto-updater stay disabled individually.
- Answers the CLI's folder trust prompt with `y` for Meterlet's own empty probe folder, waits for startup output to settle before sending `/usage`, and resends it once if a late prompt consumed it.

**Apple Silicon · macOS 14 or later.** The release ZIP is Developer ID-signed, notarized by Apple, and stapled. Its SHA-256 checksum and the signed Sparkle update feed are attached. CI development artifacts are not release downloads.

Meterlet 0.2.0 installs this release from Check for Updates. Earlier builds need the ZIP: quit Meterlet and move the new Meterlet.app to Applications.

Claude's authenticated `/usage` flow is verified against Claude Code 2.1.273 with a signed-in Claude Max account. Codex fetching and Claude's logged-out behavior remain verified against the installed official CLIs. Fable parsing is covered by fixtures and appears when the CLI includes the model-specific row in its `/usage` output.

See [README](https://github.com/moguone/meterlet#readme) for setup and limitations.
