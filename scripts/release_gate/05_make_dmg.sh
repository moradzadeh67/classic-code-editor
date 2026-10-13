#!/usr/bin/env bash
# 05 - Package the release .app into a DMG installer (uses built-in hdiutil).
# Prerequisite: run 03_build_macos.sh first.
set -euo pipefail
cd "$(dirname "$0")/../.."

APP="build/macos/Build/Products/Release/Classic Code Editor.app"
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
OUT_DIR="build/distributions"
DMG="$OUT_DIR/Classic Code Editor-$VERSION.dmg"
STAGE="$OUT_DIR/dmg-stage"

if [[ ! -d "$APP" ]]; then
  echo "BLOCKED: $APP not found - run 03_build_macos.sh first"
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Classic Code Editor" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGE"
echo "PASS: $DMG"
