#!/usr/bin/env bash
# Verifies the installers a release is about to publish.
#
#   scripts/verify_artifacts.sh <platform> <version> <dist-dir>
#
# Every check answers one of two questions: is this file the app we think it
# is (identity and version), and is it signed the way this release claims to
# be. A release that ships someone else's bundle id, last version's number or
# an unsigned binary where a signature was promised fails here rather than on
# a user's machine.
#
# Signing expectations come from the environment, so an unsigned build is only
# a failure when the workflow said it would sign:
#   MACOS_SIGNING=true    the dmg must carry a Developer ID and be stapled
#   ANDROID_SIGNING=true  the apk must verify against its signing certificate
set -euo pipefail

platform="${1:?platform required}"
version="${2:?version required}"
dist="${3:?dist dir required}"

BUNDLE_ID="com.appfide.nija"
APP_NAME="Nija"

fail() { echo "::error::$*" >&2; exit 1; }
ok() { echo "  ok: $*"; }

# Finds exactly one file matching a glob; a release that produced two dmgs or
# none is broken in a way the later steps would paper over.
only() {
  local pattern="$1" matches=()
  while IFS= read -r line; do matches+=("$line"); done < <(find "$dist" -type f -name "$pattern" | sort)
  [ "${#matches[@]}" -eq 1 ] || fail "expected exactly one $pattern in $dist, found ${#matches[@]}"
  printf '%s\n' "${matches[0]}"
}

# Guards against a packaging step that "succeeds" and writes a stub.
min_size() {
  local file="$1" mb="$2" bytes
  bytes=$(wc -c < "$file" | tr -d ' ')
  [ "$bytes" -ge $((mb * 1024 * 1024)) ] || fail "$(basename "$file") is ${bytes}B, under the ${mb}MB floor"
}

echo "verifying $platform artifacts for $version in $dist"

case "$platform" in
  macos)
    dmg=$(only "*-macos.dmg")
    min_size "$dmg" 10
    mount=$(mktemp -d)
    hdiutil attach "$dmg" -nobrowse -quiet -mountpoint "$mount"
    trap 'hdiutil detach "$mount" -quiet -force || true' EXIT
    app="$mount/$APP_NAME.app"
    [ -d "$app" ] || fail "$APP_NAME.app is not in the dmg (found: $(ls "$mount"))"
    plist="$app/Contents/Info.plist"
    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
    short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
    [ "$id" = "$BUNDLE_ID" ] || fail "dmg carries bundle id $id, expected $BUNDLE_ID"
    [ "$short" = "$version" ] || fail "dmg carries version $short, expected $version"
    ok "$BUNDLE_ID $short"
    codesign --verify --strict --deep "$app" || fail "the app bundle fails codesign --verify"
    if [ "${MACOS_SIGNING:-false}" = "true" ]; then
      codesign --display --verbose=4 "$app" 2>&1 | grep -q 'Authority=Developer ID Application' \
        || fail "release claims Developer ID signing but the app is not signed with one"
      xcrun stapler validate "$dmg" || fail "the dmg is not stapled, so Gatekeeper will call home or refuse"
      ok "Developer ID signed and stapled"
    else
      ok "ad-hoc signed (no Developer ID secrets configured)"
    fi
    ;;

  ios)
    ipa=$(only "*-ios-unsigned.ipa")
    min_size "$ipa" 5
    work=$(mktemp -d)
    unzip -q "$ipa" -d "$work"
    plist="$work/Payload/Runner.app/Info.plist"
    [ -f "$plist" ] || fail "the ipa has no Payload/Runner.app/Info.plist"
    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
    short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
    [ "$id" = "$BUNDLE_ID" ] || fail "ipa carries bundle id $id, expected $BUNDLE_ID"
    [ "$short" = "$version" ] || fail "ipa carries version $short, expected $version"
    # The ipa is deliberately unsigned; users re-sign it themselves.
    [ -d "$work/Payload/Runner.app/_CodeSignature" ] \
      && fail "the ipa is signed, but this release publishes it as unsigned"
    ok "$BUNDLE_ID $short, unsigned as intended"
    ;;

  windows)
    exe=$(only "*-windows.exe")
    zip=$(only "*-windows.zip")
    min_size "$exe" 5
    min_size "$zip" 5
    unzip -l "$zip" | grep -qi "$APP_NAME.exe" || fail "the portable zip has no $APP_NAME.exe"
    ok "installer and portable zip present"
    ;;

  linux)
    deb=$(only "*-linux.deb")
    img=$(only "*-linux.AppImage")
    min_size "$deb" 5
    min_size "$img" 10
    pkg=$(dpkg-deb -f "$deb" Package)
    ver=$(dpkg-deb -f "$deb" Version)
    [ "$pkg" = "nija" ] || fail "the deb declares package $pkg, expected nija"
    [ "${ver%%-*}" = "$version" ] || fail "the deb declares version $ver, expected $version"
    dpkg-deb -c "$deb" | grep -q "/nija" || fail "the deb ships no nija binary"
    ok "deb $pkg $ver"
    head -c 4 "$img" | grep -q ELF || fail "the AppImage is not an ELF binary"
    ok "AppImage is an ELF image"
    ;;

  android)
    apk=$(only "*-android.apk")
    aab=$(only "*-android.aab")
    min_size "$apk" 10
    min_size "$aab" 10
    aapt=$(find "${ANDROID_HOME:-/usr/local/lib/android/sdk}/build-tools" -name aapt2 2>/dev/null | sort -r | head -1)
    [ -n "$aapt" ] || fail "no aapt2 in the Android SDK, so the apk cannot be identified"
    badging=$("$aapt" dump badging "$apk")
    echo "$badging" | grep -q "package: name='$BUNDLE_ID'" \
      || fail "apk package is $(echo "$badging" | sed -nE "s/^package: name='([^']+)'.*/\1/p"), expected $BUNDLE_ID"
    echo "$badging" | grep -q "versionName='$version'" \
      || fail "apk versionName is $(echo "$badging" | sed -nE "s/.*versionName='([^']+)'.*/\1/p"), expected $version"
    ok "$BUNDLE_ID $version"
    if [ "${ANDROID_SIGNING:-false}" = "true" ]; then
      signer=$(find "${ANDROID_HOME:-/usr/local/lib/android/sdk}/build-tools" -name apksigner | sort -r | head -1)
      [ -n "$signer" ] || fail "no apksigner in the Android SDK"
      "$signer" verify --print-certs "$apk" \
        || fail "release claims an upload key but the apk fails signature verification"
      ok "apk signature verifies"
    else
      ok "debug-signed (no upload keystore configured)"
    fi
    ;;

  *)
    fail "unknown platform $platform"
    ;;
esac

echo "$platform artifacts verified"
