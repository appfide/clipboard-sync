#!/usr/bin/env bash
# Turns a downloaded Developer ID certificate into the five repository secrets
# the release workflow needs, without any of them passing through a terminal.
#
#   scripts/setup_macos_signing.sh ~/Downloads/developerID_application.cer
#
# Expects the private key the CSR was made with at ~/nija-developer-id.key.
# That key is the half Apple never sees and cannot reissue: losing it means
# revoking the certificate and starting again, so it stays out of the repo and
# off any share.
#
# Nothing here is echoed. The .p12 password is generated, used, and stored as a
# secret; it is never needed again by a human.
set -euo pipefail

cer="${1:?path to the .cer downloaded from developer.apple.com required}"
key="${NIJA_SIGNING_KEY:-$HOME/nija-developer-id.key}"
team_id="P4UH33447Z"

die() { echo "error: $*" >&2; exit 1; }

[ -f "$cer" ] || die "no certificate at $cer"
[ -f "$key" ] || die "no private key at $key (set NIJA_SIGNING_KEY if it lives elsewhere)"
command -v gh >/dev/null || die "the GitHub CLI is not installed"
gh auth status >/dev/null 2>&1 || die "run: gh auth login"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077

# Apple hands out DER; everything downstream wants PEM.
openssl x509 -inform DER -in "$cer" -out "$work/cert.pem" 2>/dev/null \
  || cp "$cer" "$work/cert.pem"

subject=$(openssl x509 -in "$work/cert.pem" -noout -subject)
case "$subject" in
  *"Developer ID Application"*) ;;
  *) die "that certificate is not a Developer ID Application certificate:
       $subject
     A Mac App Distribution or Apple Development certificate cannot sign
     software distributed outside the App Store." ;;
esac

expiry=$(openssl x509 -in "$work/cert.pem" -noout -enddate | cut -d= -f2)
echo "certificate: ${subject#subject=}"
echo "expires:     $expiry"

# Confirm the certificate actually matches the key before anything is uploaded;
# a mismatch here becomes an unexplained signing failure in CI months later.
cert_mod=$(openssl x509 -in "$work/cert.pem" -noout -modulus | openssl md5)
key_mod=$(openssl rsa -in "$key" -noout -modulus 2>/dev/null | openssl md5)
[ "$cert_mod" = "$key_mod" ] || die "this certificate was not issued for $key"
echo "key match:   ok"

password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40)
openssl pkcs12 -export \
  -inkey "$key" -in "$work/cert.pem" \
  -out "$work/cert.p12" -passout "pass:$password" \
  -name "Developer ID Application"

printf '%s' "$(base64 < "$work/cert.p12" | tr -d '\n')" | gh secret set MACOS_CERT_P12_BASE64
printf '%s' "$password" | gh secret set MACOS_CERT_PASSWORD
printf '%s' "$team_id" | gh secret set APPLE_TEAM_ID

read -r -p "Apple ID email: " apple_id
[ -n "$apple_id" ] || die "an Apple ID is required for notarization"
printf '%s' "$apple_id" | gh secret set APPLE_ID

echo
echo "An app-specific password is not your Apple ID password. Create one at"
echo "https://appleid.apple.com → Sign-In and Security → App-Specific Passwords."
read -r -s -p "App-specific password: " app_password
echo
[ -n "$app_password" ] || die "an app-specific password is required for notarization"
printf '%s' "$app_password" | gh secret set APPLE_APP_PASSWORD

echo
echo "All five secrets are set. The next release signs and notarizes the dmg,"
echo "and the verification step fails it if the signature or staple is missing."
gh secret list | grep -E 'MACOS_|APPLE_' || true
