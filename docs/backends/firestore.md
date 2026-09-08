# Firebase Firestore

The app uses the Firestore **REST API** with Firebase Authentication tokens,
so it works on every platform (the official plugin has no Linux support).
Polling only — no realtime.

## 1. Create the project

1. [console.firebase.google.com](https://console.firebase.google.com) → Add project.
2. Build → Firestore Database → Create database (production mode).
3. Build → Authentication → Sign-in method → enable **Email/Password**
   (and optionally **Anonymous**).
4. Authentication → Users → Add user.

Collections are created lazily; no schema to import. Documents:

- `clip_items/{uuid}` — canonical fields, timestamps as `timestamp` values
- `devices/{uuid}` — `name`, `platform`, `last_seen`

## 2. Security rules

Firestore → Rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() { return request.auth != null; }
    function ownsDoc()  { return resource.data.owner_id == request.auth.uid; }
    function ownsNew()  { return request.resource.data.owner_id == request.auth.uid; }

    match /clip_items/{id} {
      allow read:   if signedIn() && ownsDoc();
      allow create: if signedIn() && ownsNew();
      allow update: if signedIn() && ownsDoc() && ownsNew();
      allow delete: if signedIn() && ownsDoc();
    }
    match /devices/{id} {
      allow read:   if signedIn() && ownsDoc();
      allow write:  if signedIn() && ownsNew();
    }
  }
}
```

The app writes `owner_id = <uid>` on every document it creates.

If you rely on **anonymous** sign-in (no email/password in settings), every
anonymous user gets a fresh uid, so rules above would isolate each device.
Use email/password so all your devices share one uid.

## 3. Index

Queries order by `updated_at` only; the automatic single-field index is enough.

## 4. App settings

| Field | Where to find it |
|---|---|
| Project ID | Project settings → General |
| Web API key | Project settings → General → Web API Key |
| Email / Password | The Auth user you created |
| Items / Devices collection | `clip_items` / `devices` |

The Web API key is not a secret in Firebase's model, but the app still stores
it in the OS keychain and the repo's secret scanner rejects it in source.

## Retention

Enable a TTL policy: Firestore → *Time-to-live* → collection `clip_items`,
field `updated_at`… no — TTL requires a dedicated field. Use the app's purge
setting, or set a Cloud Function on a schedule (outside this project's scope).
