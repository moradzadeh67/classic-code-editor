#!/usr/bin/env bash
# Release gate 01 — flutter analyze must be clean (0 issues).
set -u
cd "$(dirname "$0")/../.." || exit 1

if command -v flutter >/dev/null 2>&1; then
  FLUTTER=flutter
elif [ -x "$HOME/dev/flutter_sdk/bin/flutter" ]; then
  FLUTTER="$HOME/dev/flutter_sdk/bin/flutter"
else
  echo "FAIL: 01_analyze — flutter SDK not found on PATH"
  exit 1
fi

echo "== 01_analyze: flutter analyze =="
OUT="$("$FLUTTER" analyze 2>&1)"
CODE=$?
echo "$OUT"

if [ "$CODE" -eq 0 ] && echo "$OUT" | grep -q "No issues found"; then
  echo "PASS: 01_analyze"
  exit 0
fi
echo "FAIL: 01_analyze"
exit 1
