#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "🚀 DiskBar Kurulumu Başlatılıyor..."
echo "1. Uygulama derleniyor..."
./build.sh

echo "2. Servis başlatılıyor ve otomatik başlatma ayarlanıyor..."
./setup_service.sh

echo ""
echo "🎉 Kurulum tamamlandı! DiskBar menü çubuğunuzda aktif olarak çalışıyor."
