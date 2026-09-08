# CouchDB / IBM Cloudant

Plain HTTP API; the app talks straight to the database. Works with Apache
CouchDB ≥ 3.0 and Cloudant.

## 1. Create the database and index

```sh
export COUCH=https://couch.example.com:5984
export AUTH=admin:YOUR_PASSWORD          # admin only for setup

curl -u $AUTH -X PUT $COUCH/clipboard_sync

curl -u $AUTH -X POST $COUCH/clipboard_sync/_index \
  -H 'Content-Type: application/json' \
  -d '{"index":{"fields":["kind","updated_at"]},"name":"kind-updated_at","type":"json"}'
```

Document layout (one database, discriminated by `kind`):

| `_id` | `kind` | fields |
|---|---|---|
| `clip:<uuid>` | `clip` | `device_id, device_name, content_type, content, blob_ref, content_hash, size_bytes, encrypted, nonce, created_at, updated_at, deleted_at` |
| `device:<uuid>` | `device` | `name, platform, last_seen` |

Large binaries are stored as CouchDB attachments on the clip document.

## 2. Create a per-user account (do not use admin in the app)

```sh
curl -u $AUTH -X PUT $COUCH/_users/org.couchdb.user:alice \
  -H 'Content-Type: application/json' \
  -d '{"name":"alice","password":"YOUR_PASSWORD","roles":[],"type":"user"}'

curl -u $AUTH -X PUT $COUCH/clipboard_sync/_security \
  -H 'Content-Type: application/json' \
  -d '{"admins":{"names":[],"roles":[]},"members":{"names":["alice"],"roles":[]}}'
```

For Cloudant use *Manage → Permissions* to grant `_reader`/`_writer` to an
API key and enter the key/password in the app.

## 3. App settings

| Field | Value |
|---|---|
| Server URL | `https://couch.example.com:5984` |
| Database name | `clipboard_sync` |
| Username / Password | `alice` / … |

Enable CORS if you also use the web build: `curl -u $AUTH -X PUT $COUCH/_node/_local/_config/httpd/enable_cors -d '"true"'`.

## Retention

The app's purge deletes old docs via `_bulk_docs`. Run periodic compaction:
`curl -u $AUTH -X POST $COUCH/clipboard_sync/_compact`.
