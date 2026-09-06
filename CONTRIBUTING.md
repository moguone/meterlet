# Contributing

Bug reports, translations, and small, focused pull requests are welcome. Keep Meterlet a lightweight, local usage viewer.

## Development

Use Apple Silicon, macOS 14+, and Xcode 16+ / Swift 6.

```sh
./scripts/test.sh
swift run Meterlet --demo --show-window --language en
./scripts/package-app.sh
```

`MeterletCore` contains quota models, CLI adapters, parsers, localization, and a restricted-permission cache. `Meterlet` contains the SwiftUI views and a small AppKit bridge for the fixed-width status item and popover. Tests include synthetic data and fake subprocesses; they do not authenticate or contact providers.

When changing an adapter, cover the actual protocol boundary and missing/error data. Do not convert absent data to 0%, infer model quotas, submit model prompts, read credential files, or leave subprocesses running. Never attach auth files or full conversation logs to issues. Report the app version, macOS version, CLI version, error label, and a carefully redacted usage-only example when necessary.

The `--probe codex` and `--probe claude` options perform a real local fetch and print normalized usage. Run them only when intending to use the signed-in CLI. They do not print raw CLI output or credentials.

## Translations

English and Japanese string catalogs are in `Sources/MeterletCore/Resources/{en,ja}.lproj/Localizable.strings`. To add a language:

1. Copy the English catalog to a new `<language>.lproj` directory and translate every value, preserving `%@` and `%d` format arguments.
2. Extend `AppLanguage`, `L10n.identifier`, and the Settings language picker. Retain English as the fallback.
3. Add the language to the packaging script's `CFBundleLocalizations` list and test language selection, long labels, dates, and countdowns.
4. Run tests and inspect the real preview with `--language <language>`.

Screenshots must use demo data. They can be regenerated from a packaged app:

```sh
"dist/Meterlet.app/Contents/MacOS/Meterlet" \
  --demo --language en --light --render-preview "$PWD/docs/images/en"
```

## Releases

The `main` workflow runs tests, creates an Apple Silicon app, and uploads a build artifact. A `v*` tag invokes the release workflow and creates a draft release without public app assets. Development build artifacts remain in Actions. A maintainer signs and notarizes the app locally before attaching verified assets and publishing the release; see [RELEASING.md](docs/RELEASING.md). Live Claude/Fable validation is still outstanding; preserve that limitation in release notes until verified with an eligible account.

Do not describe builds as notarized unless the archive has actually passed notarization and stapling. The packaging script supports optional `CODE_SIGN_IDENTITY` and `NOTARY_PROFILE` values for a developer-managed signing environment.

## 日本語での参加

Issue・Pull Request は日本語でも歓迎します。翻訳は上記の `.lproj/Localizable.strings`、言語の選択処理、設定画面、配布スクリプトの対応言語を一緒に更新してください。スクリーンショットには必ずデモデータを使い、認証情報や会話ログを添付しないでください。
