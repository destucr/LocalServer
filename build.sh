#!/bin/zsh
# Builds LocalServer.app. Usage: ./build.sh [run|install|release]
# Version comes from the VERSION file; build number is the git commit count.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LocalServer"

APP="build/LocalServer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LocalServer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
# App icon, drawn by the app itself so there is no binary asset to keep in sync.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
"$BIN" --icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP (v$VERSION, build $BUILD)"

case "${1:-}" in
  run)     pkill -x LocalServer 2>/dev/null || true; open "$APP" ;;
  release) (cd build && rm -f LocalServer-$VERSION.zip && ditto -c -k --keepParent LocalServer.app LocalServer-$VERSION.zip)
           echo "Zipped build/LocalServer-$VERSION.zip" ;;
  install) pkill -x LocalServer 2>/dev/null || true
           rm -rf /Applications/LocalServer.app; cp -R "$APP" /Applications/; open /Applications/LocalServer.app
           echo "Installed to /Applications" ;;
esac
