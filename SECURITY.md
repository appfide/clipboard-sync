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

Local
- `.gitignore` excludes every credential file class (keystores, certificates, provisioning profiles, `.env*`, Firebase/Google config, service accounts, local databases).
- `gitleaks` (default rules + per-database patterns in `.gitleaks.toml`) and `scripts/verify_secrets.sh` run in the pre-commit hook.

Server-side (GitHub)
- Secret scanning with push protection rejects known credential formats at push time.
- `main protection` ruleset: pull requests only, required status checks (secret scan, lint, core tests, app tests), linear history, no force-push or deletion.
- `release tags` ruleset: `v*` tags cannot be deleted or moved.
- GitHub Actions restricted to GitHub-owned actions plus an explicit allowlist, all pinned to commit SHAs; workflow token defaults to read-only.
- Dependabot alerts and security updates enabled; private vulnerability reporting enabled.
- Push rulesets (path/extension blocking) are not available on public source repositories, so the pre-commit hook and CI gitleaks scan are the file-level gate.

Release integrity
- Releases are built only by GitHub Actions from tagged commits on `main`; `SHA256SUMS.txt` accompanies every release.
