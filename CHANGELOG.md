# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/).

## [Unreleased]

### Added
- Settings → Permissions: per-platform clipboard/hotkey/autostart guidance with a live clipboard access test.
- Professional UI: Inter typeface, explicit light/dark design tokens (`lib/ui/app_theme.dart`), adaptive shell (navigation rail on desktop, bottom bar on phones), card-based history grouped by day with hover/press states, database picker grid, redesigned settings and diagnostics.
- About page with app info and Appfide company details.
- Appearance setting (System / Light / Dark) and `--theme=` launch flag.
- Golden screenshot suite (`apps/clipboard_sync/test_screenshots`) that renders every screen to `docs/screenshots/`.

### Changed
- macOS: App Sandbox disabled (not App Store distributed) so start-at-login and tray capture work; keychain access is non-blocking with a 10 s timeout and preferences fallback.
- Android: app data excluded from cloud backup and device transfer; clipboard read after resume is delayed and retried to match focus timing.
- iOS: `hasStrings` gate avoids needless paste prompts; Local Network usage description added.
- Linux: defaults to XWayland so background clipboard watching and the global hotkey work on Wayland desktops.

## [0.1.0] - 2026-09-08

### Added
- Initial cross-platform clipboard sync (macOS, Windows, Linux, Android, iOS).
- Pluggable backends: Supabase, PocketBase, CouchDB, Firestore (REST), MongoDB.
- Optional end-to-end encryption (AES-256-GCM, Argon2id).
- Automated release builds: dmg, exe, AppImage, deb, apk, aab, unsigned ipa.
