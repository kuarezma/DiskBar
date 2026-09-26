#!/bin/bash
set -e

PROJECT_DIR="/Users/ugurmac/DiskBar"
APP_DIR="/Users/ugurmac/Applications/DiskBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 DiskBar derleniyor..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc -O "$PROJECT_DIR/Sources"/*.swift -o "$MACOS_DIR/DiskBar"

# İkon kopyala
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

echo "✅ DiskBar.app başarıyla hazırlandı: $APP_DIR"
