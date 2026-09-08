# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/).

## [Unreleased]

### Added
- Professional UI: Inter typeface, explicit light/dark design tokens (`lib/ui/app_theme.dart`), adaptive shell (navigation rail on desktop, bottom bar on phones), card-based history grouped by day with hover/press states, database picker grid, redesigned settings and diagnostics.
- About page with app info and Appfide company details.
- Appearance setting (System / Light / Dark) and `--theme=` launch flag.
- Golden screenshot suite (`apps/clipboard_sync/test_screenshots`) that renders every screen to `docs/screenshots/`.

## [0.1.0] - 2026-09-08

### Added
- Initial cross-platform clipboard sync (macOS, Windows, Linux, Android, iOS).
- Pluggable backends: Supabase, PocketBase, CouchDB, Firestore (REST), MongoDB.
- Optional end-to-end encryption (AES-256-GCM, Argon2id).
- Automated release builds: dmg, exe, AppImage, deb, apk, aab, unsigned ipa.
