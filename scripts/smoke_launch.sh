#!/usr/bin/env bash
# Launches the packaged app and checks it is still running a moment later.
#
#   scripts/smoke_launch.sh <platform> <dist-dir>
#
# `verify_artifacts.sh` proves an installer contains the app it claims to;
# this proves the app starts. The two fail differently: a build that cannot
# find a library, crashes in `main()`, or dies initialising its database exits
# within a second, and nothing else in the pipeline would notice.
#
# The check is deliberately shallow. It does not drive the UI or sync anything;
# it starts the binary, waits, and asks whether it is alive. Staying up for
# several seconds is the difference between a broken build and a working one.
#
# Android and iOS are not covered: running them needs an emulator or simulator,
# and the actions that provide one are not on this repository's allowlist.
set -euo pipefail

platform="${1:?platform required}"
dist="${2:?dist dir required}"

APP_NAME="Nija"
ALIVE_SECONDS="${SMOKE_ALIVE_SECONDS:-8}"

fail() { echo "::error::$*" >&2; exit 1; }
ok() { echo "  ok: $*"; }

only() {
  local pattern="$1" matches=()
  while IFS= read -r line; do matches+=("$line"); done < <(find "$dist" -type f -name "$pattern" | sort)
  [ "${#matches[@]}" -eq 1 ] || fail "expected exactly one $pattern in $dist, found ${#matches[@]}"
  printf '%s\n' "${matches[0]}"
}

# Runs a command in the background and reports whether it survived the wait.
# A process that exits early takes its output with it, so the log is kept and
# printed on failure: "it died" is not a diagnosis.
watch_start() {
  local log="$1"; shift
  "$@" > "$log" 2>&1 &
  local pid=$!
  local waited=0
  while [ "$waited" -lt "$ALIVE_SECONDS" ]; do
    sleep 1
    waited=$((waited + 1))
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null && status=0 || status=$?
      echo "--- output before exit ---"
      cat "$log" || true
      echo "--------------------------"
      fail "$APP_NAME exited after ${waited}s with status $status instead of staying up"
    fi
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  ok "stayed up ${ALIVE_SECONDS}s, then exited on request"
  if [ -s "$log" ]; then
    echo "  startup output:"
    sed 's/^/    /' "$log" | head -20
  fi
}

echo "smoke-launching $platform from $dist"

case "$platform" in
  macos)
    dmg=$(only "*-macos.dmg")
    mount=$(mktemp -d)
    hdiutil attach "$dmg" -nobrowse -quiet -mountpoint "$mount"
    trap 'hdiutil detach "$mount" -quiet -force || true' EXIT
    # Run from a copy: the dmg is read-only, and the app writes on first launch.
    staged=$(mktemp -d)
    cp -R "$mount/$APP_NAME.app" "$staged/"
    binary="$staged/$APP_NAME.app/Contents/MacOS/$APP_NAME"
    [ -x "$binary" ] || fail "no executable at $APP_NAME.app/Contents/MacOS/$APP_NAME"
    watch_start "$staged/launch.log" "$binary" --hidden
    ;;

  linux)
    deb=$(only "*-linux.deb")
    staged=$(mktemp -d)
    dpkg-deb -x "$deb" "$staged"
    binary=$(find "$staged" -type f -name nija -perm -u+x | head -1)
    [ -n "$binary" ] || fail "no executable nija in the deb"
    # A GTK app needs a display even to reach its first frame.
    command -v xvfb-run >/dev/null || fail "xvfb-run is missing; install xvfb before this step"
    watch_start "$staged/launch.log" xvfb-run -a "$binary" --hidden
    ;;

  windows)
    zip=$(only "*-windows.zip")
    staged=$(mktemp -d)
    unzip -q "$zip" -d "$staged"
    binary=$(find "$staged" -type f -name "$APP_NAME.exe" | head -1)
    [ -n "$binary" ] || fail "no $APP_NAME.exe in the portable zip"
    watch_start "$staged/launch.log" "$binary" --hidden
    # Git Bash's kill does not always reach a native process tree.
    taskkill //F //IM "$APP_NAME.exe" >/dev/null 2>&1 || true
    ;;

  android|ios)
    echo "  skipped: $platform needs an emulator or simulator to launch"
    exit 0
    ;;

  *)
    fail "unknown platform $platform"
    ;;
esac

echo "$platform smoke launch passed"
