# Security Policy

## Supported versions

Only the latest release on the `main` branch receives security fixes.

## Reporting a vulnerability

**Do not open a public issue.** Report privately through
[GitHub Security Advisories](https://github.com/appfide/clipboard-sync/security/advisories/new).

You will receive an acknowledgement within 72 hours and a fix or mitigation plan within 14 days for confirmed issues.

## Threat model summary

- Clipboard Sync talks **directly** to a database the user provisions. There is no Appfide server; Appfide never sees your data.
- Database credentials are stored only in the OS credential store (Keychain / Keystore / DPAPI / libsecret) via `flutter_secure_storage`.
- Optional end-to-end encryption (AES-256-GCM, Argon2id-derived key) means the database only ever holds ciphertext. Enable it for any shared or hosted database.
- The credentials you enter are "client" credentials (Supabase anon key, PocketBase user, CouchDB user, Firebase web API key, MongoDB user). Scope them with the row-level / collection rules in `docs/backends/` — anyone with those credentials can read what the rules allow.

## Repository safeguards

- `gitleaks` + `pre-commit` block secrets locally; CI rescans full history on every push.
- All GitHub Actions are pinned to commit SHAs; `dependabot` updates them weekly.
- Releases are built only by GitHub Actions from tagged commits on `main`; `SHA256SUMS.txt` accompanies every release.
