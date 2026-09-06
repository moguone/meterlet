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

## Build and verify

Start from the clean, CI-tested commit intended for the release. Run tests, then package with your local signing identity and Keychain profile:

```sh
./scripts/test.sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="meterlet-notary" \
VERSION="0.1.0" ./scripts/package-app.sh
```

The script uses a secure timestamp and hardened runtime, verifies the signature, submits the ZIP for notarization, staples and validates the ticket, runs Gatekeeper assessment, and re-creates the ZIP and SHA-256 file. If any step fails, it stops. Resolve the error before publishing.

Inspect the final signature and archive:

```sh
codesign --display --verbose=4 dist/Meterlet.app
xcrun stapler validate dist/Meterlet.app
spctl --assess --type execute --verbose dist/Meterlet.app
(cd dist && shasum -a 256 -c Meterlet-0.1.0-macOS-arm64.zip.sha256)
```

## Publish

Push the reviewed version tag and wait for the Prepare release workflow to finish. Verify the draft points at the expected commit. Replace its draft notice with the actual signing and notarization result, preserve any unverified provider limitations, and attach the verified ZIP and checksum. Publish the draft only after these checks. Do not upload certificates, private keys, or notarization credentials to the repository or release.

For this first version, authenticated Claude/Fable verification remains outstanding. Keep this explicit even after app notarization succeeds; notarization does not validate provider integration behavior.

## References

- [Apple: Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## 日本語

配布用には **Developer ID Application** 証明書を使い、Apple の公証・チケット添付まで確認します。開発用の Apple Development 証明書とは別です。公証用の認証情報は `notarytool store-credentials` で Keychain に保存し、チャットや GitHub に書かないでください。タグからは下書きのみを作成し、署名・公証を検証した ZIP とチェックサムを添付してから公開します。
