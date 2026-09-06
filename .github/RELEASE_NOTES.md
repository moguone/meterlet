Adds app updates from GitHub using Sparkle.

- Check for Updates from the right-click menu or Settings.
- Optional daily checks; downloading and installation require the user’s choice.
- Signed feed and archive verification before installation.
- Finds the CLI in the Codex/ChatGPT desktop app, including renamed or relocated installations.
- Reuses Claude desktop’s downloaded native Code runtime without a separate CLI install. Claude Code sign-in and initial setup may still be required.
- Retries with the desktop runtime after CLI authentication failure; other errors and manually selected executables do not trigger a switch.

Fixes a menu bar popover that could grow beyond the top of the screen.

- Sets a bounded popover size before positioning and opens below the menu bar item.
- Keeps the header and footer visible while long usage details scroll.
- Adds a labeled Quit button, a right-click menu, and keyboard shortcuts: ⌘1 for Usage, ⌘, for Settings, and ⌘Q to quit.
- Prevents multiple copies of Meterlet from staying running.
- Displays the packaged app version in Settings.

**Apple Silicon · macOS 14 or later.** The release ZIP is Developer ID-signed, notarized by Apple, and stapled. Its SHA-256 checksum and the signed Sparkle update feed are attached. CI development artifacts are not release downloads.

This is the first release with in-app updates. Download the ZIP, quit the existing Meterlet app, and move the new Meterlet.app to Applications. Future releases can be installed from Check for Updates. Local preview builds already numbered 0.2.0 also need this manual replacement.

Codex fetching and Claude's logged-out behavior are verified against the installed official CLIs. Claude's authenticated flow and Fable parsing are covered by simulated CLI processes and fixtures; live authenticated Claude/Fable verification remains outstanding.

See [README](https://github.com/moguone/meterlet#readme) for setup and limitations.
