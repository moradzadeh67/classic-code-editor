#!/usr/bin/env bash
# Release gate 04 — the built release app must launch and stay alive ~8s (no crash).
set -u
cd "$(dirname "$0")/../.." || exit 1

APP="build/macos/Build/Products/Release/Classic Code Editor.app"
EXE="$APP/Contents/MacOS/Classic Code Editor"

if [ ! -d "$APP" ] || [ ! -x "$EXE" ]; then
  echo "FAIL: 04_launch_smoke — $APP not found; run 03_build_macos.sh first"
  exit 1
fi

echo "== 04_launch_smoke: launching $EXE for 8s =="
"$EXE" >/tmp/borland_launch_smoke.log 2>&1 &
PID=$!

sleep 8

if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL: 04_launch_smoke — app died during startup. Log tail:"
  tail -40 /tmp/borland_launch_smoke.log
  exit 1
fi

echo "== app alive after 8s; last log lines =="
tail -10 /tmp/borland_launch_smoke.log 2>/dev/null || true

kill "$PID" 2>/dev/null
sleep 1
kill -9 "$PID" 2>/dev/null || true

echo "PASS: 04_launch_smoke"
exit 0
