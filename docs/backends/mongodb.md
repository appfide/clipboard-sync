# MongoDB (Atlas or self-hosted)

The app connects with the MongoDB wire protocol over TLS using `mongo_dart`.
MongoDB Atlas retired the serverless *Data API* in September 2025, so a direct
driver connection is the only serverless option. Polling only.

> The connection string contains a password. The app keeps it in the OS
> credential store and never logs it, but treat it like any database
> credential: create a dedicated user with access to one database only.

## 1. Create database user and collections

Atlas → Database Access → Add user → *Built-in role: Read and write to any
database* is too broad; choose **Specific privileges → readWrite on
`clipboard_sync`**. Then Network Access → allow your devices' IPs (or
`0.0.0.0/0` if they roam — then E2E encryption is mandatory).

In `mongosh`:

```js
use clipboard_sync
db.createCollection("clip_items")
db.createCollection("devices")
db.clip_items.createIndex({ updated_at: 1 })
db.clip_items.createIndex({ device_id: 1, updated_at: 1 })
// Optional server-side retention (30 days):
db.clip_items.createIndex({ updated_at: 1 }, { expireAfterSeconds: 2592000, name: "ttl_updated_at" })
```

Documents use `_id = <uuid string>` and native `Date` values for
`created_at` / `updated_at` / `deleted_at`.

## 2. App settings

| Field | Value |
|---|---|
| Connection string | `mongodb+srv://USER:PASSWORD@cluster0.xxxx.mongodb.net/clipboard_sync` |
| Items / Devices collection | `clip_items` / `devices` |

Self-hosted: `mongodb://USER:PASSWORD@host:27017/clipboard_sync?tls=true`.
Plain `mongodb://` without `tls=true` sends credentials unencrypted — only on
a trusted LAN.
