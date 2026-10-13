#!/usr/bin/env bash
# Release gate 03 — macOS RELEASE build must succeed and produce the app bundle.
set -u
cd "$(dirname "$0")/../.." || exit 1

if command -v flutter >/dev/null 2>&1; then
  FLUTTER=flutter
elif [ -x "$HOME/dev/flutter_sdk/bin/flutter" ]; then
  FLUTTER="$HOME/dev/flutter_sdk/bin/flutter"
else
  echo "FAIL: 03_build_macos — flutter SDK not found on PATH"
  exit 1
fi

echo "== 03_build_macos: flutter build macos --release =="
OUT="$("$FLUTTER" build macos --release 2>&1)"
CODE=$?
echo "$OUT"

APP="build/macos/Build/Products/Release/Classic Code Editor.app"
EXE="$APP/Contents/MacOS/Classic Code Editor"

if [ "$CODE" -eq 0 ] && [ -d "$APP" ] && [ -x "$EXE" ]; then
  echo "PASS: 03_build_macos ($APP)"
  exit 0
fi
echo "FAIL: 03_build_macos"
exit 1
