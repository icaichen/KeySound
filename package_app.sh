#!/bin/bash

APP_NAME="KeyboardSoundSimulator"
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
    <key>LSUIElement</key>
    <true/> <!-- Menu Bar App: Hide from Dock -->
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Done! App created at $APP_BUNDLE"
