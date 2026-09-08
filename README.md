# Clipboard Sync

[![CI](https://github.com/appfide/clipboard-sync/actions/workflows/ci.yml/badge.svg)](https://github.com/appfide/clipboard-sync/actions/workflows/ci.yml)
[![Release](https://github.com/appfide/clipboard-sync/actions/workflows/release.yml/badge.svg)](https://github.com/appfide/clipboard-sync/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Clipboard history that syncs across **macOS, Windows, Linux, Android and iOS** through a database **you** provide. There is no Appfide server in the loop: the app talks directly to your Supabase, PocketBase, CouchDB, Firestore or MongoDB with the credentials you enter in Settings.

- **Bring your own database** — each backend has its own schema and settings form; setup guides in [`docs/backends/`](docs/backends).
- **End-to-end encryption** (optional) — Argon2id-derived AES-256-GCM; the database only ever sees ciphertext.
- **Desktop-native** — runs in the tray, global hotkey, start at login.
- **Local-only mode** — works as a plain clipboard manager with no database at all.
- **Enterprise repo hygiene** — secret scanning on every commit and in CI, SHA-pinned Actions, reproducible release builds with checksums.

## Screenshots

| History (desktop) | Settings (dark) | About |
|---|---|---|
| ![History](docs/screenshots/history-desktop-light.png) | ![Settings](docs/screenshots/settings-desktop-dark.png) | ![About](docs/screenshots/about-desktop-light.png) |

| Onboarding (phone) | History (phone, dark) | Database picker |
|---|---|---|
| ![Onboarding](docs/screenshots/onboarding-phone-light.png) | ![History phone](docs/screenshots/history-phone-dark.png) | ![Backend](docs/screenshots/backend-desktop-light.png) |

## Install

Download the latest installer from [Releases](https://github.com/appfide/clipboard-sync/releases): `.dmg`, `.exe`, `.deb` / `.AppImage`, `.apk`, unsigned `.ipa`. Builds are currently unsigned — see [docs/release.md](docs/release.md#installing-unsigned-builds).

## Set up a database

Pick one and follow its guide:

| Backend | Realtime | Guide |
|---|---|---|
| Supabase | ✅ | [docs/backends/supabase.md](docs/backends/supabase.md) |
| PocketBase | ✅ | [docs/backends/pocketbase.md](docs/backends/pocketbase.md) |
| CouchDB / Cloudant | ✅ | [docs/backends/couchdb.md](docs/backends/couchdb.md) |
| Firebase Firestore | polling | [docs/backends/firestore.md](docs/backends/firestore.md) |
| MongoDB | polling | [docs/backends/mongodb.md](docs/backends/mongodb.md) |

Then open the app → *Settings → Database*, paste the values, **Test connection & schema**, save. Enable *End-to-end encryption* with the same passphrase on every device.

## Platform notes

| | Capture | Notes |
|---|---|---|
| macOS / Windows / Linux | Automatic, in background | Tray icon, `⌘⇧V` / `Ctrl+Shift+V` opens history. Linux runs under XWayland by default (native Wayland restricts clipboard access). |
| Android | When the app is open | Android 10+ blocks background clipboard access. Copy, then open the app or tap *Capture*. |
| iOS | When the app is open | iOS asks "Allow Paste?" unless you set *Settings → Clipboard Sync → Paste from Other Apps → Allow*. No background capture is possible. |

Details, prompts and data-protection notes: [docs/platforms.md](docs/platforms.md). Settings → *Permissions* has a live clipboard-access test.

## Development

```sh
git clone https://github.com/appfide/clipboard-sync.git && cd clipboard-sync
./scripts/bootstrap.sh                      # pre-commit hooks, deps
cd packages/clipsync_core && dart test      # core: models, crypto, sync engine, adapters
cd ../../apps/clipboard_sync && flutter run -d macos
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [docs/architecture.md](docs/architecture.md) and [SECURITY.md](SECURITY.md).

## License

MIT © Appfide
