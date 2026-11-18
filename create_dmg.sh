#!/bin/bash
set -e

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="${APP_DIR:-$HOME/Applications/DiskBar.app}"
DMG_STAGING="$DIST_DIR/dmg_staging"
DMG_OUTPUT="$DIST_DIR/DiskBar.dmg"
ZIP_OUTPUT="$DIST_DIR/DiskBar.zip"

echo "📦 DiskBar.dmg ve ZIP paketleri hazırlanıyor..."
mkdir -p "$DIST_DIR"
rm -rf "$DMG_STAGING" "$DMG_OUTPUT" "$ZIP_OUTPUT"
mkdir -p "$DMG_STAGING"

# 1. En güncel uygulamayı derle
APP_DIR="$APP_DIR" "$PROJECT_DIR/build.sh"

# 2. DMG hazırlık dizinine kopyala
cp -R "$APP_DIR" "$DMG_STAGING/DiskBar.app"

# 3. Applications kısayolu (Drag & Drop için)
ln -s /Applications "$DMG_STAGING/Applications"

# 4. ZIP paketi oluştur (ditto ile macOS özniteliklerini koruyarak)
ditto -c -k --sequesterRsrc --keepParent "$DMG_STAGING/DiskBar.app" "$ZIP_OUTPUT"

# 5. hdiutil ile sıkıştırılmış DMG oluştur
hdiutil create -volname "DiskBar" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

# Temizlik
rm -rf "$DMG_STAGING"

echo "✅ DMG hazır: $DMG_OUTPUT ($(du -h "$DMG_OUTPUT" | cut -f1))"
echo "✅ ZIP hazır: $ZIP_OUTPUT ($(du -h "$ZIP_OUTPUT" | cut -f1))"
