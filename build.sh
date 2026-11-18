#!/bin/bash
set -e

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
APP_DIR="${APP_DIR:-$HOME/Applications/DiskBar.app}"
VERSION="${VERSION:-1.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"

CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "❌ Hata: swiftc bulunamadı. Lütfen 'xcode-select --install' ile Command Line Tools kurun."
    exit 1
fi

echo "🔨 DiskBar v$VERSION derleniyor..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc -O "$PROJECT_DIR/Sources"/*.swift -o "$MACOS_DIR/DiskBar"

# İkon kopyala
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat << EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DiskBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.ugur.diskbar</string>
    <key>CFBundleName</key>
    <string>DiskBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Kod imzalama (Ad-hoc)
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "✅ DiskBar.app v$VERSION başarıyla hazırlandı: $APP_DIR"
