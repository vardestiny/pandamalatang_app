#!/usr/bin/env bash
#
# Browser smoke-test runner. Development only — never a shipping target.
#
# The app talks to pandamalatang.com from a page served on localhost, which the
# browser treats as cross-origin. The API is a machine-to-machine endpoint for a
# tablet, so it sends no Access-Control-Allow-Origin and never should: adding one
# would open the live order feed to every origin on the internet for the sake of
# a convenience the real clients (iOS, Android) do not need.
#
# So the bypass belongs in the browser, not in the server. This launches a
# throwaway Chrome profile with web security off. Nothing about production
# changes, and the flag dies with the process.
#
# Do not browse anything else in this window. With --disable-web-security any
# page it loads can read any other site you are signed in to.
#
# Usage:
#   tool/run-web-dev.sh                        # against https://pandamalatang.com
#   tool/run-web-dev.sh http://localhost:3000  # against a local pangdamalatang
set -euo pipefail

cd "$(dirname "$0")/.."

BASE_URL="${1:-https://pandamalatang.com}"
PORT="${PORT:-5555}"

FLUTTER=(flutter)
command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ] && FLUTTER=(fvm flutter)

if [ ! -d web ]; then
  echo "No web/ target — it is git-ignored on purpose. Creating it locally."
  "${FLUTTER[@]}" create --platforms=web . >/dev/null
  git checkout .metadata 2>/dev/null || true
  rm -f test/widget_test.dart
fi

echo "Backend : $BASE_URL"
echo "App     : http://localhost:$PORT"
echo

# --disable-web-security          skips CORS and the preflight entirely
# --disable-site-isolation-trials required alongside it since Chrome 117
# --dart-define                   pre-fills the pairing screen's URL field
exec "${FLUTTER[@]}" run -d chrome \
  --web-port="$PORT" \
  --web-browser-flag=--disable-web-security \
  --web-browser-flag=--disable-site-isolation-trials \
  --dart-define=BASE_URL="$BASE_URL"
