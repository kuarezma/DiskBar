#!/bin/bash
set -e

echo "============================================="
echo "  🚀 DiskBar for macOS - Otomatik Kurulum   "
echo "============================================="

# Eğer betik curl | bash şeklinde uzak sunucudan çalıştırılıyorsa:
if [ ! -f "build.sh" ]; then
    TMP_DIR=$(mktemp -d)
    echo "⬇️ DiskBar kaynak kodu indiriliyor..."
    git clone --depth 1 https://github.com/kuarezma/DiskBar.git "$TMP_DIR"
    cd "$TMP_DIR"
    echo "🔨 Uygulama derleniyor..."
    ./build.sh
    echo "⚙️ Servis ve otomatik başlatma ayarlanıyor..."
    ./setup_service.sh
    rm -rf "$TMP_DIR"
else
    # Yerel klon içerisinden çalıştırılıyorsa:
    echo "🔨 Uygulama derleniyor..."
    ./build.sh
    echo "⚙️ Servis ve otomatik başlatma ayarlanıyor..."
    ./setup_service.sh
fi

echo ""
echo "============================================="
echo "  🎉 Kurulum başarıyla tamamlandı!"
echo "  DiskBar ekranınızın sağ üst menü çubuğunda"
echo "  canlı olarak çalışmaya başladı."
echo "============================================="
