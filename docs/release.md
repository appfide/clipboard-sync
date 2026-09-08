# Releases

## How a release happens

1. Bump `version:` in `apps/clipboard_sync/pubspec.yaml` (SemVer) and add a
   `CHANGELOG.md` entry in the same PR.
2. Merge to `main`. The **Release** workflow sees the new version, tags
   `v<version>`, builds every installer with `flutter_distributor`, and
   publishes a GitHub Release with `SHA256SUMS.txt`.
3. Pushing a `v*` tag by hand triggers the same pipeline.

| Platform | Artifact | Signed? |
|---|---|---|
| macOS | `ClipboardSync-<v>-macos.dmg` (arm64; Intel Macs run it via Rosetta) | No |
| Windows | `…-windows.exe` (Inno Setup) + `.zip` portable | No |
| Linux | `…-linux.deb`, `…-linux.AppImage` (x86_64) | n/a |
| Android | `…-android.apk`, `.aab` | Debug key unless secrets set |
| iOS | `ClipboardSync-<v>-ios-unsigned.ipa` | No — sideload with AltStore/Sideloadly or re-sign |

## Installing unsigned builds

- **macOS**: right-click the app → *Open* → *Open*; or
  `xattr -dr com.apple.quarantine "/Applications/Clipboard Sync.app"`.
- **Windows**: SmartScreen → *More info* → *Run anyway*.
- **iOS**: unsigned `.ipa` requires a sideloading tool with your own Apple ID.

## Adding signing (repository secrets)

| Secret | Purpose |
|---|---|
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Release-sign APK/AAB. Generate: `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`, then `base64 -i upload-keystore.jks`. Without these, CI signs with the debug key — installable, but users cannot upgrade in place across releases. |
| `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Developer ID signing + notarization (not wired yet; see TODO in `release.yml`). |
| `WINDOWS_CERT_PFX_BASE64`, `WINDOWS_CERT_PASSWORD` | Authenticode signing (not wired yet). |

Never commit any of these files. `.gitignore`, gitleaks and `scripts/verify_secrets.sh` all reject them.

## Local packaging

```sh
dart pub global activate flutter_distributor
cd apps/clipboard_sync
flutter_distributor release --name local-macos      # dmg (needs `npm i -g appdmg`)
flutter_distributor release --name local-linux      # deb + AppImage (needs appimagetool)
flutter_distributor release --name local-windows    # exe (needs Inno Setup) + zip
flutter_distributor release --name local-android    # apk + aab
```
