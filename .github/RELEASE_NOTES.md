Native macOS menu bar viewer for Codex and Claude Code subscription usage.

- Compact, fixed-width two-line menu bar display.
- Usage windows, model-specific limits (including Fable when reported), reset dates, countdowns, and fetch timestamps.
- English and Japanese, with automatic system-language selection.
- Official CLI authentication; no token extraction, analytics, or application backend.
- Periodic short-lived probes, sleep handling, Low Power Mode support, and error backoff.

**Preview build:** Apple Silicon, macOS 14 or later. This archive is ad-hoc signed and is **not notarized with an Apple Developer ID**. macOS may block it. For a locally built version, follow the source build instructions in the README. Do not disable Gatekeeper globally.

Install the official Codex and/or Claude Code CLI and complete its setup separately. CLI binaries and credentials are not included. Claude's CLI text format can change; missing values are shown as unavailable rather than zero. Fable parsing is covered by synthetic fixtures; live Fable quota validation has not yet been performed for this first preview.

The `.sha256` file accompanies the downloadable ZIP. See [README](https://github.com/moguone/token_viewer#readme) for setup and limitations.
