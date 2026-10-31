#!/bin/bash
# Makes build/IDEPlus-<version>.dmg to install IDEPlus on another Mac (Apple Silicon):
# the app, an Applications shortcut to drag it onto, and a note on opening it the first time.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
APP="build/IDEPlus.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/IDEPlus-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
# Only the languages in the repo: files kept on this Mac only (see .gitignore) stay out of the package.
for f in "$STAGE/IDEPlus.app/Contents/Resources/Syntax/"*; do
	git ls-files --error-unmatch "Resources/Syntax/$(basename "$f")" >/dev/null 2>&1 || rm -f "$f"
done
codesign --force --sign - "$STAGE/IDEPlus.app" >/dev/null
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open IDEPlus.txt" <<'EOF'
Installing IDEPlus

1. Drag IDEPlus onto the Applications folder in this window.
2. Open IDEPlus from Applications.

The first time, macOS may say it can't check IDEPlus for malicious software,
because it isn't from the App Store or a registered Apple developer.
To open it anyway:

  - Open System Settings > Privacy & Security.
  - Scroll down to the message about IDEPlus and click Open Anyway.
  - Confirm with your Mac password, then click Open.

You only need to do this once.

Your FTP sites, favorites and settings are not copied from another Mac:
add your sites again in IDEPlus (the site menu > Add or Edit Sites…).
EOF

rm -f "$DMG"
hdiutil create -volname "IDEPlus $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet "$DMG"
echo "Packaged $DMG"
