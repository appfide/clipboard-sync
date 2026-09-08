#!/usr/bin/env bash
# Runs the analyzer for one workspace package. Uses `flutter analyze` when the
# package depends on Flutter, `dart analyze` otherwise. Skips silently if the
# package does not exist yet (early scaffold stages).
set -euo pipefail
pkg="${1:?package dir required}"
[ -f "$pkg/pubspec.yaml" ] || exit 0
cd "$pkg"
if grep -qE '^\s+sdk:\s+flutter' pubspec.yaml; then
  flutter pub get --offline >/dev/null 2>&1 || flutter pub get >/dev/null
  flutter analyze --fatal-infos --fatal-warnings
else
  dart pub get --offline >/dev/null 2>&1 || dart pub get >/dev/null
  dart analyze --fatal-infos --fatal-warnings
fi
