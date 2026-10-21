#!/bin/zsh
# Builds LocalServer.app. Usage: ./build.sh [run|install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LocalServer"

APP="build/LocalServer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LocalServer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

case "${1:-}" in
  run)     pkill -x LocalServer 2>/dev/null || true; open "$APP" ;;
  install) pkill -x LocalServer 2>/dev/null || true
           rm -rf /Applications/LocalServer.app; cp -R "$APP" /Applications/; open /Applications/LocalServer.app
           echo "Installed to /Applications" ;;
esac
