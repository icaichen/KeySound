#!/bin/bash
set -e

APP_NAME="KeySound"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"
SOURCES_DIR="Sources/Sounds"

echo "Cleaning previous build..."
swift package clean

echo "Building for release..."
swift build -c release

echo "Creating App Bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Copying executable..."
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

echo "Copying resources..."
# Copy the Sounds folder directly to Resources
cp -r "$SOURCES_DIR" "$APP_BUNDLE/Contents/Resources/"
# Copy sound recipes (Sound Lab presets)
cp -r "Sources/Recipes" "$APP_BUNDLE/Contents/Resources/"

echo "Creating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.keysound.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/> <!-- Menu Bar App: Hide from Dock -->
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Create a temporary icon using sips if possible, or just create the entry
# Since we don't have a physical icon file yet, we can't copy it.
# However, for a real app, you'd have an .icns file.
# I will create a placeholder instruction in the script to look for it.
if [ -f "KeySound.icns" ]; then
    cp "KeySound.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

SIGN_IDENTITY="Developer ID Application: chen cai (G8C56JYBN5)"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    SIGN_IDENTITY="-"
fi

echo "Signing $APP_BUNDLE with: $SIGN_IDENTITY"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP_BUNDLE"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

NOTARY_PROFILE="${NOTARY_PROFILE:-justdictate-notary}"
NOTARY_ZIP="/tmp/${APP_NAME}-notarize.zip"
rm -f "$NOTARY_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Submitting $APP_BUNDLE to Apple Notary Service (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"
    echo "Verifying Gatekeeper assessment..."
    spctl -a -vvv -t exec "$APP_BUNDLE"
else
    echo "⚠️  Notarization skipped: keychain profile '$NOTARY_PROFILE' not found."
    echo "    Run once: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <EMAIL> --team-id G8C56JYBN5 --password <APP_SPECIFIC_PASSWORD>"
fi
rm -f "$NOTARY_ZIP"

echo "Creating distributable KeySound.zip..."
rm -f KeySound.zip
ditto -c -k --keepParent "$APP_BUNDLE" KeySound.zip
if [ -d "../website" ]; then
    cp KeySound.zip ../website/KeySound.zip
    echo "Updated ../website/KeySound.zip"
fi

echo "Installing to /Applications/$APP_BUNDLE..."
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_BUNDLE"
ditto "$APP_BUNDLE" "/Applications/$APP_BUNDLE"

echo "Done! App created, signed, and installed at /Applications/$APP_BUNDLE"
