#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/Claude Mac Guard.app"
CONTENTS_DIR="$APP_DIR/Contents"

if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
mkdir -p "$SWIFTPM_MODULECACHE_OVERRIDE"

cd "$PROJECT_DIR"
"$PROJECT_DIR/scripts/build-icon.sh"
swift build -c release
swift run -c release ClaudeMacGuardSelfTest
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/ClaudeMacGuard" "$CONTENTS_DIR/MacOS/ClaudeMacGuard"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
xattr -cr "$APP_DIR"
codesign --force --sign - \
  --identifier com.wangzhuo.ClaudeMacGuard \
  --timestamp=none \
  "$APP_DIR"
# Documents may be managed by macOS File Provider, which can re-add an empty
# FinderInfo xattr immediately after signing. It is not part of the app content
# and strict codesign verification rejects its presence.
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true

echo "$APP_DIR"
