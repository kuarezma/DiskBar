#!/bin/bash
set -e

PROJECT_DIR="/Users/ugurmac/DiskBar"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="/Users/ugurmac/Applications/DiskBar.app"
DMG_STAGING="$DIST_DIR/dmg_staging"
DMG_OUTPUT="$DIST_DIR/DiskBar.dmg"
ZIP_OUTPUT="$DIST_DIR/DiskBar.zip"

echo "📦 DiskBar.dmg ve ZIP paketleri hazırlanıyor..."
rm -rf "$DIST_DIR"
mkdir -p "$DMG_STAGING"

# 1. En güncel uygulamayı derle
"$PROJECT_DIR/build.sh"

# 2. DMG hazırlık dizinine kopyala
cp -R "$APP_DIR" "$DMG_STAGING/DiskBar.app"

# 3. Applications kısayolu (Drag & Drop için)
ln -s /Applications "$DMG_STAGING/Applications"

# 4. ZIP paketi oluştur
cd "$DMG_STAGING"
zip -r "$ZIP_OUTPUT" "DiskBar.app"
cd "$PROJECT_DIR"

# 5. hdiutil ile sıkıştırılmış DMG oluştur
rm -f "$DMG_OUTPUT"
hdiutil create -volname "DiskBar" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

# Temizlik
rm -rf "$DMG_STAGING"

echo "✅ DMG hazır: $DMG_OUTPUT ($(du -h "$DMG_OUTPUT" | cut -f1))"
echo "✅ ZIP hazır: $ZIP_OUTPUT ($(du -h "$ZIP_OUTPUT" | cut -f1))"
