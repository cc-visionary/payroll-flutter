#!/usr/bin/env bash
# Deterministic verification. Exit non-zero on any failure.
# This is rung 1 of the conflict ladder: it outranks every model opinion.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> dart format (check only)"
dart format --output=none --set-exit-if-changed .

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test"
flutter test

echo "==> all checks passed"
