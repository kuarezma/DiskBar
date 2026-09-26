<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="DiskBar Logo" />
</p>

<h1 align="center">DiskBar for macOS</h1>

<p align="center">
  <b>A sleek, ultra-lightweight, native macOS menu bar app that tracks your free disk space in real time using Apple's kernel FSEvents.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2012.0%2B-blue?logo=apple" alt="macOS 12+" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-purple" alt="Universal" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/CPU%20Usage-0.0%25-brightgreen" alt="0.0% CPU" />
  <img src="https://img.shields.io/badge/Updates-1--Click%20Auto--Notify-blueviolet" alt="Auto Updates" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" />
  <a href="https://github.com/kuarezma/DiskBar/stargazers"><img src="https://img.shields.io/github/stars/kuarezma/DiskBar?style=social" alt="GitHub Stars" /></a>
</p>

<p align="center">
  <a href="https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar.dmg">
    <img src="https://img.shields.io/badge/Download-DiskBar.dmg-2ea44f?style=for-the-badge&logo=apple&logoColor=white" alt="Download DMG" />
  </a>
</p>

---

## 📸 Screenshots

<p align="center">
  <b>Menu Bar Real-Time Status Pill</b><br/>
  <img src="assets/diskbar_status_v2.png" width="220" alt="DiskBar Menu Bar Status" />
</p>

<p align="center">
  <b>Drop-Down Storage Card & Controls</b><br/>
  <img src="assets/diskbar_card_v2.png" width="340" alt="DiskBar Storage Card" />
</p>

---

## 📥 Installation

Choose whichever method you prefer:

### Option 1: Direct Download (`.dmg`) — Recommended for Most Users
1. Download **[DiskBar.dmg](https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar.dmg)** from the [Releases](https://github.com/kuarezma/DiskBar/releases) page.
2. Open `DiskBar.dmg` and drag **DiskBar** into your **Applications** folder.
3. Open **DiskBar** from Applications. It will appear on your top-right menu bar.

### Option 2: One-Line Terminal Install (No Clone Needed)
Open Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/kuarezma/DiskBar/main/install.sh | bash
```

> **Security Note:** Does **not** require `sudo` or administrator privileges. It compiles the open-source code directly on your machine and places the binary into `~/Applications/DiskBar.app`.

---

## ⚡ Key Features

- **🚀 Real-Time Disk Monitoring via Kernel `FSEvents`:**  
  Unlike standard apps that merely poll on timers, DiskBar hooks directly into macOS `CoreServices.FSEventStream`. When you download a file, build an Xcode project, or empty the Trash, your free space updates instantly (< 0.8s) with smart event coalescing.
- **🔔 Automatic Update Notifications & 1-Click Update:**  
  When a new release is published on GitHub, DiskBar automatically sends a native macOS notification. Users can update in-place with a single click right from the menu without touching Terminal or downloading files manually.
- **🍏 100% Pure Native & Lightweight:**  
  Zero Electron, zero heavy third-party dependencies. Pure Swift and AppKit. Uses **0.0% CPU** at idle and consumes minimal memory (~55 MB runtime).
- **🎨 Dynamic Circular Gauge & SF Symbols:**  
  Includes a custom-drawn circular progress ring that smoothly tracks space usage. When storage drops below critical levels (< 10 GB or < 10%), it automatically turns red/orange to alert you.
- **🎛️ Elegant Dropdown Card:**  
  Left-click or right-click to reveal a native glass card showing volume details (`Macintosh HD`), usage progress bar, free/used/total capacities, and cache status.
- **⚙️ Deep macOS Integration:**  
  Quick one-click shortcuts to **macOS Storage Settings** (`x-apple.systempreferences:com.apple.settings.Storage`) and **Disk Utility**.
- **🔄 Auto-Start with LaunchAgent:**  
  Seamlessly launches on system login without taking up Dock space (`LSUIElement = true`). Can be toggled on/off with a single click in the menu.
- **❌ Quick Quit Anytime:**  
  Right-click or click to exit cleanly via `DiskBar'ı Kapat (⌘Q)`.
- **🔒 Privacy & Trust:**  
  100% offline. Zero tracking, zero telemetry, zero analytics.

---

## 🎨 Display Formats & Customization

You can customize the appearance directly from the **`🎨 Görünüm & Ayarlar`** menu:

| Mode | Format Preview |
|---|---|
| **İkon + Boş Alan** (Default) | `⭕ 6.1 GB Boş` |
| **Sadece Boş Alan** | `6.1 GB Boş` |
| **Boş / Toplam Alan** | `6.1 / 245.1 GB` |
| **Doluluk Oranı** | `%97.5 Dolu` |
| **Kompakt** | `⭕` *(Yalnızca Canlı Halka / İkon)* |

---

## 🇹🇷 Türkçe Açıklama

**DiskBar**, MacBook kullanıcıları için özel olarak geliştirilmiş, menü çubuğunda (sağ üstte) diskinizde ne kadar boş alan kaldığını anlık ve canlı olarak gösteren yerel bir macOS uygulamasıdır.

- **Otomatik Bildirim & Tek Tıkla Güncelleme:** GitHub'da yeni bir sürüm yayınladığınızda, kullanıcılar macOS yerel bildirimi alır ve menüden tek tıkla uygulamayı anında en son sürüme güncelleyebilir.
- **Güvenli ve Şeffaf:** %100 açık kaynaklıdır; hiçbir internet bağlantısı veya veri toplama içermez. `sudo` yetkisi gerektirmez.
- **Anlık Takip:** Dosya indirdiğinizde, sildiğinizde veya önbellek temizlendiğinde macOS çekirdeğinin `FSEvents` mekanizması ile anında güncellenir.
- **Sıfır Yük:** Saf Swift/Cocoa ile yazılmıştır; arka planda işlemcinizi yormaz (boşta %0.0 CPU).
- **İndirme & Kurulum:** İster `.dmg` dosyasını indirip Uygulamalar klasörüne sürükleyin, ister Terminal'den `curl -fsSL https://raw.githubusercontent.com/kuarezma/DiskBar/main/install.sh | bash` ile kurun.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).  
Feel free to star ⭐️ the project, open issues, or submit pull requests!
