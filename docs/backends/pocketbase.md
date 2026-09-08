# PocketBase

Self-hosted single binary (`./pocketbase serve`). SSE realtime. Direct client
access; no extra server.

## 1. Import collections

Admin UI → Settings → Import collections → paste:

```json
[
  {
    "name": "clip_items",
    "type": "base",
    "fields": [
      { "name": "clip_id",      "type": "text",   "required": true, "max": 64 },
      { "name": "device_id",    "type": "text",   "required": true },
      { "name": "device_name",  "type": "text" },
      { "name": "content_type", "type": "text",   "required": true },
      { "name": "content",      "type": "text",   "max": 2000000 },
      { "name": "blob_ref",     "type": "text" },
      { "name": "blob",         "type": "file",   "maxSelect": 1, "maxSize": 26214400 },
      { "name": "content_hash", "type": "text",   "required": true },
      { "name": "size_bytes",   "type": "number" },
      { "name": "encrypted",    "type": "bool" },
      { "name": "nonce",        "type": "text" },
      { "name": "created_at",   "type": "date",   "required": true },
      { "name": "updated_at",   "type": "date",   "required": true },
      { "name": "deleted_at",   "type": "date" },
      { "name": "owner",        "type": "relation", "collectionId": "_pb_users_auth_", "maxSelect": 1 }
    ],
    "indexes": [
      "CREATE UNIQUE INDEX idx_clip_items_clip_id ON clip_items (clip_id)",
      "CREATE INDEX idx_clip_items_updated_at ON clip_items (updated_at)"
    ],
    "listRule":   "@request.auth.id != '' && owner = @request.auth.id",
    "viewRule":   "@request.auth.id != '' && owner = @request.auth.id",
    "createRule": "@request.auth.id != '' && owner = @request.auth.id",
    "updateRule": "@request.auth.id != '' && owner = @request.auth.id",
    "deleteRule": "@request.auth.id != '' && owner = @request.auth.id"
  },
  {
    "name": "devices",
    "type": "base",
    "fields": [
      { "name": "device_id", "type": "text", "required": true },
      { "name": "name",      "type": "text" },
      { "name": "platform",  "type": "text" },
      { "name": "last_seen", "type": "date", "required": true },
      { "name": "owner",     "type": "relation", "collectionId": "_pb_users_auth_", "maxSelect": 1 }
    ],
    "indexes": [ "CREATE UNIQUE INDEX idx_devices_device_id ON devices (device_id)" ],
    "listRule":   "@request.auth.id != '' && owner = @request.auth.id",
    "viewRule":   "@request.auth.id != '' && owner = @request.auth.id",
    "createRule": "@request.auth.id != '' && owner = @request.auth.id",
    "updateRule": "@request.auth.id != '' && owner = @request.auth.id",
    "deleteRule": "@request.auth.id != '' && owner = @request.auth.id"
  }
]
```

The app sets `owner` to the signed-in user automatically when the `owner`
field exists. Set every rule to `""` (empty = public) only for a private LAN
instance, and enable E2E encryption regardless.

## 2. Create a user

Collections → `users` → New record (email + password). Enter these in the app.
To use a superuser instead, set *Auth collection* to `_superusers`.

## 3. App settings

| Field | Value |
|---|---|
| Server URL | `https://pb.example.com` (or `http://192.168.1.10:8090` on LAN) |
| Auth collection | `users` |
| Email / Password | The user above |
| Items / Devices collection | `clip_items` / `devices` |

## Retention

Settings → Backups is separate. To auto-purge, add a cron in `pb_hooks/purge.pb.js`:

```js
cronAdd("purge-clips", "0 3 * * *", () => {
  const cutoff = new Date(Date.now() - 30 * 864e5).toISOString().replace("T", " ");
  $app.db().newQuery("DELETE FROM clip_items WHERE updated_at < {:c}").bind({ c: cutoff }).execute();
});
```
