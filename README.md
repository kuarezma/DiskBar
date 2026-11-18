<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="DiskBar Logo" />
</p>

<h1 align="center">DiskBar</h1>

<p align="center">
  <b>A sleek, ultra-lightweight, cross-platform status bar app that tracks your free disk space in real time.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12.0%2B-blue?logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows" alt="Windows" />
  <img src="https://img.shields.io/badge/Linux-amd64%20%7C%20arm64-FCC624?logo=linux&logoColor=black" alt="Linux" />
  <img src="https://img.shields.io/badge/CPU%20Usage-0.0%25-brightgreen" alt="0.0% CPU" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" />
  <a href="https://github.com/kuarezma/DiskBar/stargazers"><img src="https://img.shields.io/github/stars/kuarezma/DiskBar?style=social" alt="GitHub Stars" /></a>
</p>

<p align="center">
  <a href="https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar.dmg">
    <img src="https://img.shields.io/badge/macOS-Download%20DMG-2ea44f?style=for-the-badge&logo=apple&logoColor=white" alt="macOS DMG" />
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar-Windows-x64.zip">
    <img src="https://img.shields.io/badge/Windows-Download%20EXE-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows EXE" />
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/kuarezma/DiskBar/releases/latest/download/diskbar-linux-amd64.tar.gz">
    <img src="https://img.shields.io/badge/Linux-Download%20Binary-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux Binary" />
  </a>
</p>

---

## 📸 Screenshots

<p align="center">
  <b>Menu Bar Status Pill</b><br/>
  <img src="assets/diskbar_status_v2.png" width="220" alt="DiskBar Menu Bar Status" />
</p>

<p align="center">
  <b>Drop-Down Storage Card & Controls</b><br/>
  <img src="assets/diskbar_card_v2.png" width="340" alt="DiskBar Storage Card" />
</p>

---

## 📥 Downloads & Installation

| Platform | Download Link | Format | Description |
|---|---|---|---|
| 🍏 **macOS** | **[DiskBar.dmg](https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar.dmg)** | `.dmg` | Native Swift / AppKit menu bar app with multi-volume & APFS purgeable stats |
| 🪟 **Windows** | **[DiskBar-Windows-x64.zip](https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar-Windows-x64.zip)** / **[DiskBar.exe](https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar.exe)** | `.zip` / `.exe` | Pure Win32 System Tray executable (No install needed) |
| 🐧 **Linux (x64)** | **[diskbar-linux-amd64.tar.gz](https://github.com/kuarezma/DiskBar/releases/latest/download/diskbar-linux-amd64.tar.gz)** | `.tar.gz` | Statically linked Linux daemon & desktop notifier |
| 🐧 **Linux (ARM)** | **[diskbar-linux-arm64.tar.gz](https://github.com/kuarezma/DiskBar/releases/latest/download/diskbar-linux-arm64.tar.gz)** | `.tar.gz` | Raspberry Pi & ARM64 Linux |

### macOS Installation
- **DMG:** Download `DiskBar.dmg`, open it, and drag `DiskBar` into your `Applications` folder.
- **Terminal (One-Liner):**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/kuarezma/DiskBar/main/install.sh | bash
  ```

### Windows Installation
1. Download **[DiskBar-Windows-x64.zip](https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar-Windows-x64.zip)** or **[DiskBar.exe](https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar.exe)**.
2. Double-click `DiskBar.exe`. It runs silently in the bottom-right **System Tray** next to the clock.
3. Right-click the tray icon to view all connected drives, refresh, open Windows Storage Sense, or toggle **Run on Windows Startup**.

### Linux Installation
1. Download and extract the archive:
   ```bash
   tar -xzf diskbar-linux-amd64.tar.gz
   chmod +x diskbar-linux-amd64
   ```
2. Enable (or remove) autostart on login:
   ```bash
   ./diskbar-linux-amd64 --autostart
   ./diskbar-linux-amd64 --remove-autostart
   ```
3. Run as background service (default interval: 30s):
   ```bash
   ./diskbar-linux-amd64 --daemon --interval 30 &
   ```
4. Check version or self-update:
   ```bash
   ./diskbar-linux-amd64 --version
   ./diskbar-linux-amd64 --update
   ```

---

## ⚡ Key Features

- **🚀 Ultra-Low CPU Disk Monitoring:**
  - **macOS:** Configurable refresh timer (default 60s, plus instant refresh on menu open and drive mount/unmount), multi-volume selector, APFS purgeable space indicator, and smart low/critical space alerts.
  - **Windows:** Pure Win32 single-instance tray worker with multi-drive summary, low-space balloon alerts, and toggleable startup registry integration.
  - **Linux:** Fast kernel `statfs` watcher with low & critical `notify-send` desktop alerts and pure-Go self-updater.
- **🔔 Automatic Update Notifications (macOS, Windows, Linux):**
  Semantic version update checks against GitHub Releases with native notifications and one-click in-place updating (no compiler needed on macOS).
- **🍏🪟🐧 100% Native & Zero-Bloat:**
  No Electron, no Chromium, no heavyweight runtimes. Single compact binaries with **0.0% idle CPU** on all platforms.
- **🔒 Privacy & Transparency:**
  100% open-source, zero telemetry, zero analytics.

---

## 🛠️ Build All Platforms from Source

Run the unified cross-platform build script on macOS:

```bash
git clone https://github.com/kuarezma/DiskBar.git
cd DiskBar
./build_all.sh
```

---

## 🇹🇷 Türkçe Açıklama

**DiskBar**, **macOS**, **Windows** ve **Linux** işletim sistemlerinin tamamını destekleyen, menü çubuğunda / sistem tepsisinde (System Tray) diskinizde ne kadar boş alan kaldığını sıfıra yakın CPU tüketimiyle gösteren yerel bir uygulamadır.

- **macOS:** Menü çubuğunda canlı disk halkası/simgesi, çoklu disk seçimi, APFS temizlenebilir alan göstergesi ve düşük alan uyarıları (`DiskBar.dmg`).
- **Windows:** Sağ altta saat yanındaki sistem tepsisinde tüm sürücü özeti, aç/kapa otomatik başlatma ve düşük alan uyarıları (`DiskBar.exe`). Kurulum gerektirmez, taşınabilirdir.
- **Linux:** GNOME / KDE / XFCE bildirimleri, `--autostart` / `--remove-autostart` ve dahili `--update` desteği (`diskbar-linux`).
- **Otomatik Bildirim & Tek Tıkla Güncelleme:** GitHub'da yeni sürüm yayınlandığında tüm platformlarda bildirim ve tek tıkla güncelleme sunar.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
Feel free to star ⭐️ the project, open issues, or submit pull requests!
