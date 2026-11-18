#!/bin/bash
set -e

echo "============================================="
echo "  🚀 DiskBar for macOS - Otomatik Kurulum   "
echo "============================================="

if ! command -v swiftc >/dev/null 2>&1; then
    echo "❌ Hata: Swift derleyicisi (swiftc) bulunamadı."
    echo "   Kurulum için çalıştırın: xcode-select --install"
    exit 1
fi

TMP_DIR=""
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# Eğer betik curl | bash şeklinde uzak sunucudan çalıştırılıyorsa:
if [ ! -f "build.sh" ]; then
    if ! command -v git >/dev/null 2>&1; then
        echo "❌ Hata: git bulunamadı. Lütfen 'xcode-select --install' çalıştırın."
        exit 1
    fi
    TMP_DIR=$(mktemp -d)
    echo "⬇️ DiskBar kaynak kodu indiriliyor..."
    git clone --depth 1 https://github.com/kuarezma/DiskBar.git "$TMP_DIR"
    cd "$TMP_DIR"
fi

echo "🔨 Uygulama derleniyor..."
./build.sh
echo "⚙️ Servis ve otomatik başlatma ayarlanıyor..."
./setup_service.sh

echo ""
echo "============================================="
echo "  🎉 Kurulum başarıyla tamamlandı!"
echo "  DiskBar ekranınızın sağ üst menü çubuğunda"
echo "  canlı olarak çalışmaya başladı."
echo "============================================="
