# Releasing Meterlet

Public app downloads must be signed with **Developer ID Application**, notarized by Apple, and stapled. CI artifacts are for development and are ad-hoc signed. The tag workflow creates a **draft without app assets** so an unsigned build is never automatically published as the official release.

## One-time local setup

An Apple Developer Program membership and the appropriate certificate permissions are required. In Xcode, open Settings → Apple Accounts → your personal team → Manage Certificates. Create or import a **Developer ID Application** certificate with its private key. Apple Development is a different certificate and cannot be used for this distribution.

For command-line notarization, store credentials in Keychain using an interactive Terminal session:

```sh
xcrun notarytool store-credentials "meterlet-notary" \
  --apple-id "you@example.com" --team-id "YOUR_TEAM_ID"
```

Replace the example Apple Account and team ID with your own. The secure prompt asks only for your app-specific password; the characters are not echoed. Keep these credentials in Keychain; do not paste passwords into issues, chats, or the repository. If an existing suitable Keychain profile is available, use that profile instead.

## Update signing key

App updates use Sparkle 2.9.6. Resolve the package once, then generate an update signing key in your login Keychain:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account meterlet
```

The public key in `updates/public-key.txt` is embedded as `SUPublicEDKey`; the private key stays in Keychain. Reusing this account shows the existing public key instead of replacing it. Keep this key available for future releases. Do not export the private key into the repository or CI.

## Build and verify

Start from the clean, CI-tested commit intended for the release. Run tests, then package with your local signing identity and Keychain profile:

```sh
./scripts/test.sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="meterlet-notary" \
VERSION="0.2.0" ./scripts/package-app.sh
```

Use `OUTPUT_DIR=.build/candidate` to package a separate candidate while another build is running. The script refuses to replace a running app.

The script uses a secure timestamp and hardened runtime, verifies the signature, submits the ZIP for notarization, staples and validates the ticket, runs Gatekeeper assessment, and re-creates the ZIP and SHA-256 file. It also embeds and signs Sparkle’s arm64 framework and helpers, then creates a signed `appcast.xml` from `updates/<version>.md`. If any step fails, it stops. Resolve the error before publishing.

Inspect the final signature and archive:

```sh
codesign --display --verbose=4 dist/Meterlet.app
xcrun stapler validate dist/Meterlet.app
spctl --assess --type execute --verbose dist/Meterlet.app
(cd dist && shasum -a 256 -c Meterlet-0.2.0-macOS-arm64.zip.sha256)
```

## Test an update

The integration test compiles Sparkle’s official CLI and uses a random, separate bundle identifier. It does not launch or target an installed Meterlet app. It checks new/current/older versions, HTTP failure, rejected feed/archive signatures, and a complete installation into a temporary directory.

```sh
./scripts/test-updater.sh .build/candidate/Meterlet.app \
  --identity "Developer ID Application: Your Name (TEAMID)" \
  --notary-profile meterlet-notary
```

The normal test script also validates feed metadata and provider parsing. Complete manual UI checks on the candidate after the user has finished with the current app; a separate preview window is not a substitute for checking the actual menu bar.

## Publish

Push the reviewed version tag and wait for the Prepare release workflow to finish. Verify the draft points at the expected commit. Replace its draft notice with the actual signing and notarization result, preserve any unverified provider limitations, and attach the verified ZIP, checksum, and **appcast.xml**. Publish a **normal release**, clear the prerelease flag, and make it the latest release. GitHub’s `/releases/latest/download/appcast.xml` redirects to this asset; drafts and prereleases are not used for in-app updates. Publish the draft only after these checks and the user’s manual verification are complete. Upload all three assets before publishing; publishing without the feed makes update checks fail. Do not upload certificates, private keys, or notarization credentials to the repository or release.

Authenticated Claude/Fable verification remains outstanding. Keep this explicit even after app notarization succeeds; notarization does not validate provider integration behavior.

## References

- [Apple: Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## 日本語

配布用には **Developer ID Application** 証明書を使い、Apple の公証・チケット添付まで確認します。開発用の Apple Development 証明書とは別です。公証用の認証情報は `notarytool store-credentials` で Keychain に保存し、チャットや GitHub に書かないでください。タグからは下書きのみを作成し、署名・公証を検証した ZIP、チェックサム、署名付き `appcast.xml` を添付してから通常リリースとして公開します。
