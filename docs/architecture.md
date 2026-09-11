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
│  crypto/     ClipCipher · DeviceKeys · ClipSigning ·        │
│              KeyEnvelope · CipherRing                        │
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
   engine lists `devices`, refreshes its own presence row, verifies each
   row's admin signature and version, adopts its role and any key envelope
   addressed to it, and ignores clips from untrusted / blocked / expired
   devices and items addressed to another device. If its own signed row
   says blocked, removed or expired, it stops with `SyncPhase.revoked` and
   the app wipes credentials, passphrases and trust state.
7. **Signing** — every pushed item is sealed (newest `CipherRing` key) and
   then signed with the device's Ed25519 key; every pulled item is verified
   against the sender's admin-signed public key before decryption. Threat
   model and limits: [devices.md](devices.md#how-access-is-enforced--read-this).

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
- Device access control is cryptographic: per-device Ed25519 identities,
  admin-signed membership rows with rollback protection, passphrase
  envelopes and rotation. The database is treated as an untrusted store.
  Legacy (unsigned) groups fall back to cooperative enforcement. See
  [devices.md](devices.md#how-access-is-enforced--read-this).
- Capture filters: OS "concealed" clipboard hints (password managers) are
  checked *before* reading; credential-looking text can be skipped; capture
  can be paused.

- Credentials live only in the OS credential store (`flutter_secure_storage`).
- Every log line passes through `redactSecrets`.
- E2E encryption keeps the database blind to content; the key scope binds the
  passphrase to one backend + URL.
- The repository refuses secrets at commit time (gitleaks + pre-commit) and in
  CI (full-history scan). All Actions are SHA-pinned.
