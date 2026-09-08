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
| macOS / Windows / Linux | Automatic, in background | Tray icon, `⌘⇧V` / `Ctrl+Shift+V` opens history |
| Android | When the app is open | Android 10+ blocks background clipboard access. Copy, then open the app or tap *Capture*. |
| iOS | When the app is open | iOS asks permission on first paste access. No background capture is possible. |

## Development

```sh
git clone https://github.com/appfide/clipboard-sync.git && cd clipboard-sync
./scripts/bootstrap.sh                      # pre-commit hooks, melos, deps
cd packages/clipsync_core && dart test      # core: models, crypto, sync engine, adapters
cd ../../apps/clipboard_sync && flutter run -d macos
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [docs/architecture.md](docs/architecture.md) and [SECURITY.md](SECURITY.md).

## License

MIT © Appfide
