Fixes keyboard focus on macOS 27.

- On macOS 27, Meterlet did not become the active app when you opened the usage panel or Settings. ⌘1, ⌘, and ⌘Q went to the app you were using before, typing in Settings did not reach its fields, and the panel could close on its own. Meterlet now becomes active when you open its windows.

**Apple Silicon · macOS 14 or later.** The release ZIP is Developer ID-signed, notarized by Apple, and stapled. Its SHA-256 checksum and the signed Sparkle update feed are attached. CI development artifacts are not release downloads.

Meterlet 0.2.0 or later installs this release from Check for Updates. Earlier builds need the ZIP: quit Meterlet and move the new Meterlet.app to Applications.

Verified on macOS 27.0.1 with Claude Code 2.1.302 on a signed-in Claude Max account (session, weekly, and Fable windows) and Codex CLI 0.163.0.

See [README](https://github.com/moguone/meterlet#readme) for setup and limitations.
