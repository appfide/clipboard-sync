# Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ apps/clipboard_sync (Flutter)                               │
│  platform/   clipboard capture · tray · hotkeys · autostart │
│  data/local  drift (SQLite): items + outbox + cursor        │
│  features/   history · settings · devices (pair / manage)  │
└───────────────┬─────────────────────────────────────────────┘
                │ LocalStore, SyncBackend, ClipCipher
┌───────────────▼─────────────────────────────────────────────┐
│ packages/clipsync_core (pure Dart)                          │
│  model/      ClipItem · Device (status/role/expiry)         │
│  sync/       SyncEngine (push · pull · membership check)    │
│  crypto/     ClipCipher (Argon2id → AES-256-GCM, AAD = id)  │
│  pairing/    PairingPayload · PairingCodec (PIN-sealed)     │
│  backend/    SyncBackend · BackendDescriptor · ConfigField  │
│  backends/   supabase · pocketbase · couchdb · firestore ·  │
│              mongodb · memory                               │
└───────────────┬─────────────────────────────────────────────┘
                │ direct client connection (user's credentials)
        ┌───────▼────────┐
        │ user's database│  ← no Appfide server anywhere
        └────────────────┘
```

## Data flow

1. **Capture** — platform clipboard watcher (desktop: polling change-count;
   mobile: on app resume / share sheet) produces a `ClipItem` with a SHA-256
   `content_hash`. It is written to the local drift table with `synced = false`.
2. **Push** — `SyncEngine` drains unsynced rows in batches, optionally sealing
   `content` with `ClipCipher`, and calls `backend.upsert`.
3. **Pull** — `backend.pullSince(cursor)` returns rows from *other* devices
   ordered by `updated_at`; items are decrypted, echo-suppressed by hash, and
   applied last-writer-wins. The cursor advances to the max `updated_at`.
4. **Realtime** — where the backend supports it (Supabase, PocketBase,
   CouchDB, memory), `watch()` events simply trigger step 3. Polling backends
   (Firestore, MongoDB) run step 3 on a timer.
5. **Delete** — tombstone (`deleted_at`, content blanked). Rows are physically
   removed only by retention (`purgeBefore`).
6. **Membership** — every minute (and before a sync older than that) the
   engine lists `devices`, refreshes its own presence row, adopts its role,
   ignores clips from blocked / expired devices and items addressed to
   another device (`target_device_id`). If its own row says blocked, removed
   or expired, it stops with `SyncPhase.revoked` and the app wipes the
   credentials. Details and limits: [devices.md](devices.md).

## Adding a backend

Implement `SyncBackend`, declare a `BackendDescriptor` (the settings form is
rendered from `configSchema`), register in `BackendRegistry.builtIn()`, run
`runBackendContractTests`, write `docs/backends/<id>.md`, and add credential
patterns to `.gitleaks.toml`.

## Security model

- Pairing codes carry the database settings encrypted under an 8-digit PIN
  (Argon2id 64 MiB → AES-256-GCM), valid for 5 minutes, never recorded in
  history. Access decisions (role, expiry) are written by the host before the
  code is shown.
- Device access control is cooperative — enforced by the app, not by the
  database — because every device holds the same credentials. See
  [devices.md](devices.md#enforcement-model--read-this).
- Capture filters: OS "concealed" clipboard hints (password managers) are
  checked *before* reading; credential-looking text can be skipped; capture
  can be paused.

- Credentials live only in the OS credential store (`flutter_secure_storage`).
- Every log line passes through `redactSecrets`.
- E2E encryption keeps the database blind to content; the key scope binds the
  passphrase to one backend + URL.
- The repository refuses secrets at commit time (gitleaks + pre-commit) and in
  CI (full-history scan). All Actions are SHA-pinned.
