Native macOS menu bar viewer for Codex and Claude Code subscription usage.

- Compact, fixed-width two-line menu bar display.
- Usage windows, model-specific limits (including Fable when reported), reset dates, countdowns, and fetch timestamps.
- English and Japanese, with automatic system-language selection.
- Official CLI authentication; no token extraction, analytics, or application backend.
- Periodic short-lived probes, sleep handling, Low Power Mode support, and error backoff.

**Draft — distribution verification pending.** Apple Silicon, macOS 14 or later. Before publishing, attach only the Developer ID-signed, notarized, and stapled ZIP and its matching SHA-256 file, then replace this draft notice with the verification result. CI development artifacts are not release downloads.

Install the official Codex and/or Claude Code CLI and complete its setup separately. CLI binaries and credentials are not included. Claude's CLI text format can change; missing values are shown as unavailable rather than zero. Fable parsing is covered by synthetic fixtures; live Fable quota validation has not yet been performed for this first preview.

The `.sha256` file accompanies the downloadable ZIP. See [README](https://github.com/moguone/meterlet#readme) for setup and limitations.
