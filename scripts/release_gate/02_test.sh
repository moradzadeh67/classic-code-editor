#!/usr/bin/env bash
# Release gate 02 — full unit/widget test suite must be green.
set -u
cd "$(dirname "$0")/../.." || exit 1

if command -v flutter >/dev/null 2>&1; then
  FLUTTER=flutter
elif [ -x "$HOME/dev/flutter_sdk/bin/flutter" ]; then
  FLUTTER="$HOME/dev/flutter_sdk/bin/flutter"
else
  echo "FAIL: 02_test — flutter SDK not found on PATH"
  exit 1
fi

echo "== 02_test: flutter test =="
OUT="$("$FLUTTER" test 2>&1)"
CODE=$?
echo "$OUT"

if [ "$CODE" -eq 0 ] && echo "$OUT" | grep -q "All tests passed"; then
  echo "PASS: 02_test"
  exit 0
fi
echo "FAIL: 02_test"
exit 1
