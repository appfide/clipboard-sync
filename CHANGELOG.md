# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/).

## [Unreleased]

### Added
- **Device pairing**: Settings → Devices → *Add a device* shows a QR code (or a copyable code) plus an 8-digit PIN; the other device scans or pastes it under *Join another group* (also offered on the welcome screen). The code carries the database settings encrypted with the PIN (Argon2id → AES-256-GCM), is valid for 5 minutes and is never recorded in clipboard history. The host chooses the new device's role and access duration and can include the E2E passphrase (off by default).
- **Device management**: list every device with presence, block / unblock, remove, forget, change role (*Send & receive*, *Send only*, *Receive only*) and set temporary access. A blocked, removed or expired device stops itself, deletes its credentials and passphrase, and tells the user. Enforcement is cooperative — see `docs/devices.md`.
- **Send to…** in the history menu pushes a clip to one device only (`target_device_id`).
- **Capture filters**: *Pause capture* (also in the tray menu), *Skip password-manager content* (macOS concealed/transient pasteboard types, Windows `ExcludeClipboardContentFromMonitorProcessing`, Android 13+ `EXTRA_IS_SENSITIVE`; on by default) and *Skip keys and tokens* (credential-pattern heuristic).
- **Signed groups**: every device has an Ed25519 / X25519 identity; every clip is signed and verified against the sender's admin-signed key; membership changes (status, role, expiry, keys, admin flag, key envelope) are signed by a group admin key with rollback protection. Holding the database credentials is no longer enough to pose as a device, lift a block, or take over the group. *Settings → Devices → Secure this group* upgrades existing groups; members confirm the admin fingerprint once.
- **Encryption key rotation**: the admin issues a fresh random passphrase sealed to each verified device (X25519 + AES-GCM envelope covered by the admin signature). Removed or blocked devices cannot read clips sealed after the rotation; older history stays readable through a local keyring. Pairing delivers the passphrase the same way — it never travels inside the QR code.
- Device rows carry `status`, `role`, `expires_at`, `paired_by`, `app_version`, `sign_pub`, `box_pub`, `admin`, `admin_pub`, `membership_version`, `membership_sig`, `key_version`, `key_envelope`; clips carry `target_device_id`, `key_version`, `sig`. Supabase and PocketBase need the upgrade snippet in their guide; other backends need nothing.

### Changed
- Heartbeats write only presence fields, so a block set by another device is never overwritten.
- Local database schema v2 (adds `target_device_id`); migrates automatically.

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
- Threat model for multi-device groups documented in `docs/devices.md`, with an attacker test suite in `packages/clipsync_core/test/security`.
- Credentials live in the OS credential store with a bounded, non-blocking fallback; secrets are never logged (all log lines are redacted).
- Android app data excluded from cloud backup and device transfer.
- Repository gates: gitleaks + pre-commit locally, full-history secret scan in CI, SHA-pinned actions, branch and tag rulesets.

[Unreleased]: https://github.com/appfide/clipboard-sync/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/appfide/clipboard-sync/releases/tag/v0.1.0
