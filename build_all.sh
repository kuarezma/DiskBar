#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "============================================="
echo "  🚀 DiskBar - Çoklu Platform Derleme Aracı "
echo "============================================="

DIST_DIR="$DIR/dist"
mkdir -p "$DIST_DIR"

# 1. macOS (.app ve .dmg)
echo "🍏 1/3: macOS derleniyor..."
./create_dmg.sh

# 2. Windows (Win32 Tray .exe)
echo "🪟 2/3: Windows derleniyor (x86-64)..."
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags="-H windowsgui -s -w" -o "$DIST_DIR/DiskBar.exe" ./windows
cd "$DIST_DIR"
zip -j -q DiskBar-Windows-x64.zip DiskBar.exe
cd "$DIR"

# 3. Linux (amd64 ve arm64)
echo "🐧 3/3: Linux derleniyor (amd64 & arm64)..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o "$DIST_DIR/diskbar-linux-amd64" ./linux
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o "$DIST_DIR/diskbar-linux-arm64" ./linux
cd "$DIST_DIR"
tar -czf diskbar-linux-amd64.tar.gz diskbar-linux-amd64
tar -czf diskbar-linux-arm64.tar.gz diskbar-linux-arm64
cd "$DIR"

echo ""
echo "============================================="
echo "🎉 Tüm platformlar başarıyla hazırlandı!"
echo "📦 dist/ dizinindeki paketler:"
ls -lh "$DIST_DIR"
echo "============================================="
