#!/usr/bin/env bash
# One-shot developer setup: hooks, workspace tooling, dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v pre-commit >/dev/null || { echo "pre-commit missing: brew install pre-commit (or pipx install pre-commit)"; exit 1; }
command -v gitleaks  >/dev/null || { echo "gitleaks missing: brew install gitleaks"; exit 1; }
command -v flutter   >/dev/null || { echo "flutter missing: https://docs.flutter.dev/get-started/install"; exit 1; }

pre-commit install --install-hooks
dart pub global activate melos >/dev/null
export PATH="$PATH:$HOME/.pub-cache/bin"
melos bootstrap
echo "Ready. Run: pre-commit run --all-files"
