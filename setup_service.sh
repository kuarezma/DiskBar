#!/bin/bash
set -e

PLIST_PATH="$HOME/Library/LaunchAgents/com.ugur.diskbar.plist"
APP_PATH="${APP_PATH:-$HOME/Applications/DiskBar.app}"
BIN_PATH="$APP_PATH/Contents/MacOS/DiskBar"
USER_UID="$(id -u)"

if [ ! -x "$BIN_PATH" ]; then
    echo "❌ Hata: DiskBar ikili dosyası bulunamadı: $BIN_PATH"
    exit 1
fi

echo "⚙️ DiskBar LaunchAgent yapılandırılıyor..."
mkdir -p "$HOME/Library/LaunchAgents"

cat << EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ugur.diskbar</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

# Varsa eski süreçleri ve launchd kaydını temizle
launchctl bootout "gui/$USER_UID/com.ugur.diskbar" 2>/dev/null || launchctl unload "$PLIST_PATH" 2>/dev/null || true
pkill -x DiskBar 2>/dev/null || true
sleep 0.5

# launchctl etkinleştir ve yükle
launchctl enable "gui/$USER_UID/com.ugur.diskbar" 2>/dev/null || true
launchctl bootstrap "gui/$USER_UID" "$PLIST_PATH" 2>/dev/null || launchctl load "$PLIST_PATH" 2>/dev/null || true

# Uygulama henüz başlamadıysa başlat
sleep 0.5
if ! pgrep -x DiskBar >/dev/null; then
    open "$APP_PATH"
fi

sleep 1
PID=$(pgrep -x DiskBar | head -n 1 || true)
if [ -n "$PID" ]; then
    echo "✅ DiskBar başarıyla çalışıyor! (PID: $PID)"
    ps -o pid,%cpu,%mem,rss,command -p "$PID"
else
    echo "⚠️ DiskBar başlatılamadı."
    exit 1
fi
