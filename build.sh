#!/bin/bash
# Builds IDEPlus.app into ./build (needs only the Xcode Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/IDEPlus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/IDEPlus "$APP/Contents/MacOS/IDEPlus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The version (1.2.0) is set by hand in Resources/Info.plist; the build number is the commit count, so every build differs.
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
# Languages (.ipsyntax), autocomplete (.ipsnip) and clip libraries (.ipclip).
cp -R Resources/Syntax Resources/Snippets Resources/Clips "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature so macOS will launch it locally.
codesign --force --sign - "$APP" >/dev/null

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "Built $APP (version $VERSION, build $BUILD)"
