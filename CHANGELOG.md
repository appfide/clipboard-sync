# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-09-09

### Added
- Cross-platform clipboard sync for macOS, Windows, Linux, Android and iOS.
- Pluggable backends with their own schemas and settings forms: Supabase, PocketBase, CouchDB / Cloudant, Firebase Firestore (REST), MongoDB (driver), plus a local-only mode.
- Optional end-to-end encryption (Argon2id-derived AES-256-GCM); the database only ever stores ciphertext.
- Desktop: tray icon, global hotkey (`⌘⇧V` / `Ctrl+Shift+V`), start at login, background capture.
- Mobile: capture on resume and via the Capture action; guidance for the OS clipboard restrictions.
- Settings → Permissions with a live clipboard access test and per-platform instructions.
- Appearance setting (System / Light / Dark) and a `--theme=` launch flag.
- About page with project links and Appfide company details.
- Diagnostics screen with redacted, copyable logs.
- Automated release builds: dmg, exe + zip, deb + AppImage, apk + aab, unsigned ipa, with `SHA256SUMS.txt`.

### Security
- Credentials live in the OS credential store with a bounded, non-blocking fallback; secrets are never logged (all log lines are redacted).
- Android app data excluded from cloud backup and device transfer.
- Repository gates: gitleaks + pre-commit locally, full-history secret scan in CI, SHA-pinned actions, branch and tag rulesets.

[Unreleased]: https://github.com/appfide/clipboard-sync/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/appfide/clipboard-sync/releases/tag/v0.1.0
