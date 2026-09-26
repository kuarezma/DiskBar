#!/bin/bash
set -e

PLIST_PATH="$HOME/Library/LaunchAgents/com.ugur.diskbar.plist"
APP_PATH="/Users/ugurmac/Applications/DiskBar.app"
BIN_PATH="$APP_PATH/Contents/MacOS/DiskBar"

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

# Varsa eski süreçleri temizle
pkill -x DiskBar 2>/dev/null || true
sleep 0.5

# launchctl yükle (açılışta otomatik çalışması için)
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH" 2>/dev/null || true

# Uygulama henüz başlamadıysa başlat
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
fi
