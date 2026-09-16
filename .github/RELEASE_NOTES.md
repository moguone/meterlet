Refines what the menu bar and the usage panel show.

- The menu bar shows weekly usage by default. Settings gains a per-provider "Menu bar shows" picker, and the tooltip names the selected window.
- Claude Code shows the current session, this week, and this week's Fable limit, each with its reset time. The probe no longer sets `DISABLE_TELEMETRY`, which hid the model-specific row in `/usage`, and it waits for the row the CLI renders after its refresh.
- Codex Spark limits are no longer shown; Codex reports its weekly window only.

**Apple Silicon · macOS 14 or later.** The release ZIP is Developer ID-signed, notarized by Apple, and stapled. Its SHA-256 checksum and the signed Sparkle update feed are attached. CI development artifacts are not release downloads.

Meterlet 0.2.0 or later installs this release from Check for Updates. Earlier builds need the ZIP: quit Meterlet and move the new Meterlet.app to Applications.

The Claude Code flow is verified against Claude Code 2.1.273 with a signed-in Claude Max account, including the session, weekly, and Fable windows. The Codex changes are covered by tests against a recorded `account/rateLimits/read` response.

See [README](https://github.com/moguone/meterlet#readme) for setup and limitations.
