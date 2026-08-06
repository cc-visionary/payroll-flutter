#!/usr/bin/env bash
# Deterministic verification. Exit non-zero on any failure.
# This is rung 1 of the conflict ladder: it outranks every model opinion.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> dart format (check only)"
dart format --output=none --set-exit-if-changed .

echo "==> flutter analyze"
# Errors and warnings are fatal; info-level lints are reported but do not block.
#
# `flutter analyze` defaults to --fatal-infos, which this repo cannot satisfy:
# 90 of its infos are constant_identifier_names on _SortOrder in
# payslip_generator.dart, a SCREAMING_CASE catalog deliberately kept in sync
# with the payrollos TypeScript original. Making infos fatal would force a
# rename that the catalog decision explicitly rejects.
#
# Warnings stay fatal, so genuine defects (dead code, redundant null checks,
# bad casts) still fail the gate — that class of issue was fixed to zero, and
# this gate keeps it there.
flutter analyze --no-fatal-infos

echo "==> flutter test"
flutter test

echo "==> all checks passed"
