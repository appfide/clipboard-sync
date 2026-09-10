# Devices, pairing and access control

Clipboard Sync has no server: every device talks to *your* database with the
credentials you gave it. This page explains how devices join a sync group,
what "block", "remove", roles and expiry actually do, and where the limits
of that model are.

## Pairing a new device

1. On a device that already syncs: **Settings → Devices → Add a device**.
   Choose the role and access duration for the new device, then
   **Show pairing code**.
2. On the new device: **Settings → Devices → Join another group** (or
   *Already set up? Join with a code* on the welcome screen). Scan the QR
   code (phones) or paste the copied code (desktops), then type the
   8-digit PIN shown next to the code.
3. Review what the code grants and tap **Join**. If the group uses
   end-to-end encryption and the host did not include the passphrase, type
   it now.

What travels inside the code: the database type and settings (including the
secret fields), a device id chosen by the host, the role and expiry, the
host's name, and optionally the passphrase.

### How the code is protected

The code is the settings JSON encrypted with AES-256-GCM under a key derived
from the PIN with Argon2id (64 MiB, 3 iterations), salted per code. The wire
form is `CSYNC1.` + base64url. Without the PIN a photo of the QR is an
offline brute-force of 10⁸ PINs at roughly a second each. The host keeps a
code valid for 5 minutes; the joining device refuses stale codes.

Rules the app follows around codes:

- The pairing code is copied to the clipboard **without** being recorded in
  history, and a pairing code that appears on any device's clipboard is never
  captured — so credentials cannot leak into the shared history.
- The E2E passphrase is **not** included unless you switch it on. Typing it
  on the new device is the safer default.
- Treat the code like the database password it contains: show it only to the
  device you are adding, never share screenshots.

### What the host does when you generate a code

It writes a *pending* row to the `devices` table with the new device id,
role, expiry and `paired_by`. The list shows it as **Invited · waiting**.
When the joining device first checks in, it adopts that id and inherits the
row — the host decided the access, not the joiner. If the code is never used,
**Cancel invitation** (on the code screen) or **Forget** (in the list)
deletes the row.

## Managing devices

**Settings → Devices → Manage devices** lists every device row, with
presence (online / last seen, platform, app version) and its membership.

| Action | Effect |
|---|---|
| **Block** | Other devices ignore its clips. The device stops syncing on its next check-in (about a minute), deletes its copy of the credentials and passphrase, and shows a notice. Can be undone with **Unblock**. |
| **Change role** | *Send & receive* (default), *Send only* (pushes its clips, never pulls history — a guest laptop), *Receive only* (pulls, never pushes — a display machine). Applied on the device's next check-in. |
| **Access duration** | Sets `expires_at`. When it passes, the device disconnects itself the same way as a block, and other devices stop applying its clips. |
| **Remove** | Like block, but permanent: the row stays as a tombstone so the device learns it was removed. |
| **Forget** | Deletes the row. Use after the device has disconnected (or for unused invitations). A device that is still running notices the missing row and disconnects with "removed". |

A device cannot manage itself; rename it under **This device**.

### Send to one device

From the history menu, **Send to…** pushes a copy of a clip addressed to a
single device (`target_device_id`). Every other device skips it on pull. The
copy is hidden in the sender's history; the receiver sees it with a
"sent only to this device" mark.

## Enforcement model — read this

All devices in a group hold the **same** database credentials. Block,
remove, roles and expiry are stored in the `devices` table and honoured by
the app on each device:

- every device re-reads the device list on a one-minute heartbeat (and
  before any sync older than that), refreshes its own presence, adopts its
  role, and ignores clips from blocked / expired devices;
- a device whose own row says blocked, removed or expired — or whose row is
  gone after it had registered — stops itself, wipes the credentials and the
  passphrase, and falls back to local-only mode.

This is **cooperative**: a modified client, or an app version older than
0.2.0 (which never reads `status`), keeps its credentials and can still read
and write the database. It is the right model for one person's own devices.
If you need the database itself to enforce access, use per-user rules on the
backend (Supabase RLS, PocketBase rules, Firestore rules) — see the backend
guides — or wait for per-device credentials, which is planned.

Practical consequences:

- Blocking a lost phone stops the *app* on it; it does not stop someone who
  extracts the credentials. Rotate the database password / auth user as well.
- E2E encryption limits what a rogue device can read to what it already had
  the passphrase for; change the passphrase after removing an untrusted
  device.

## Upgrading a database created with 0.1.0

The `devices` table gained `status`, `role`, `expires_at`, `paired_by` and
`app_version`; `clip_items` gained `target_device_id`. Schema-less backends
(CouchDB, Firestore, MongoDB) need nothing. Supabase and PocketBase need the
upgrade snippet in their guide; **Test connection & schema** reports what is
missing. Until the columns exist, device management reports an error rather
than silently doing nothing.

## Schema reference

`devices` row:

| field | type | written by |
|---|---|---|
| `id` | text | the device (heartbeat) or the host (invitation) |
| `name`, `platform`, `last_seen`, `app_version` | presence | the device, every heartbeat |
| `status` | `active` / `blocked` / `removed` | managing device |
| `role` | `full` / `send_only` / `receive_only` | managing device |
| `expires_at` | timestamp or null | managing device |
| `paired_by` | device id or null | host, at invitation |

A heartbeat writes only the presence fields, so it never undoes a block.
