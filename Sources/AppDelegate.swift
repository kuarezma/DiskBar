import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var currentStats: DiskStats = DiskStats.current()
    private var headerCardView: HeaderCardView?
    private let config = DiskBarConfig.shared
    private let watcher = DiskWatcher()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Menü çubuğu öğesini oluştur (değişken genişlikli)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // İlk veriyi al ve arayüzü çiz
        refreshData()
        
        // Menüyü oluştur ve bağla
        rebuildMenu()
        
        // Anlık disk izleyiciyi başlat (FSEvents ile diskteki her dosya değişiminde anında tetiklenir)
        watcher.start { [weak self] newStats in
            self?.applyStats(newStats)
        }
        
        // APFS arka plan temizlikleri için güvenlik zamanlayıcısı (5 saniyede bir kontrol)
        startTimer()
        
        // Sürücü takılma/çıkarılma bildirimlerini dinle
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(diskDidChange), name: NSWorkspace.didMountNotification, object: nil)
        ws.addObserver(self, selector: #selector(diskDidChange), name: NSWorkspace.didUnmountNotification, object: nil)
        
        // Otomatik güncelleme kontrolcüsünü bağla
        UpdateManager.shared.onUpdateStatusChanged = { [weak self] in
            self?.rebuildMenu()
        }
        UpdateManager.shared.startPeriodicChecks()
    }
    
    // MARK: - Zamanlayıcı & Güncelleme
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refreshData()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    @objc private func diskDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshData()
        }
    }
    
    @objc public func refreshData() {
        let stats = DiskStats.current()
        applyStats(stats)
    }
    
    public func applyStats(_ stats: DiskStats) {
        currentStats = stats
        updateStatusButton()
        headerCardView?.update(stats: stats)
    }
    
    // MARK: - Menü Çubuğu Butonu Güncelleme
    
    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        
        // İkon Stili
        switch config.iconStyle {
        case .dynamicGauge:
            button.image = createGaugeIcon(stats: currentStats)
            button.imagePosition = config.displayMode == .compactIconOnly ? .imageOnly : .imageLeading
        case .sfSymbolDrive:
            button.image = createSymbolIcon(stats: currentStats)
            button.imagePosition = config.displayMode == .compactIconOnly ? .imageOnly : .imageLeading
        }
        
        // Başlık Metni
        switch config.displayMode {
        case .iconAndFreeSpace:
            button.title = " \(currentStats.freeFormatted) Boş"
        case .freeSpaceOnly:
            button.image = nil
            button.title = "\(currentStats.freeFormatted) Boş"
        case .freeAndTotal:
            button.title = " \(currentStats.freeFormatted) / \(currentStats.totalFormatted)"
        case .percentUsed:
            button.title = " \(currentStats.percentUsedFormatted) Dolu"
        case .percentFree:
            button.title = " \(currentStats.percentFreeFormatted) Boş"
        case .compactIconOnly:
            button.title = ""
        }
        
        // Tooltip (Fare ile üzerine gelindiğinde detaylı bilgi)
        button.toolTip = """
        DiskBar: \(currentStats.volumeName)
        • Boş Alan: \(currentStats.freeFormatted) (\(currentStats.percentFreeFormatted))
        • Kullanılan: \(currentStats.usedFormatted) (\(currentStats.percentUsedFormatted))
        • Toplam Boyut: \(currentStats.totalFormatted)
        • Sağ/Sol tık: Detaylı menü ve kapatma seçenekleri
        """
    }
    
    // MARK: - İkon Çizimleri
    
    private func createGaugeIcon(stats: DiskStats) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.2
            let lineWidth: CGFloat = 2.2
            
            // Arka plan çemberi
            let bgPath = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            bgPath.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            bgPath.stroke()
            
            // Doluluk yayı
            let startAngle: CGFloat = 90.0
            let fraction = CGFloat(stats.usedFraction)
            let endAngle = startAngle - (fraction * 360.0)
            
            let arcPath = NSBezierPath()
            arcPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            arcPath.lineWidth = lineWidth
            arcPath.lineCapStyle = .round
            
            if stats.isCriticalSpace {
                NSColor.systemRed.setStroke()
            } else if stats.isLowSpace {
                NSColor.systemOrange.setStroke()
            } else {
                NSColor.labelColor.setStroke()
            }
            arcPath.stroke()
            
            return true
        }
        img.isTemplate = !(stats.isCriticalSpace || stats.isLowSpace)
        return img
    }
    
    private func createSymbolIcon(stats: DiskStats) -> NSImage {
        let symName = stats.isCriticalSpace ? "internaldrive.fill" : "internaldrive"
        if let base = NSImage(systemSymbolName: symName, accessibilityDescription: "Disk") {
            let img = base.copy() as! NSImage
            img.isTemplate = !(stats.isCriticalSpace || stats.isLowSpace)
            return img
        }
        return createGaugeIcon(stats: stats)
    }
    
    // MARK: - Menü Oluşturma
    
    public func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        
        // 1. Özel Grafik Başlık Kartı
        let card = HeaderCardView(stats: currentStats)
        self.headerCardView = card
        let cardItem = NSMenuItem()
        cardItem.view = card
        menu.addItem(cardItem)
        
        // 1b. Eğer yeni sürüm varsa en üstte tek tıkla güncelleme butonu göster
        if UpdateManager.shared.isUpdateAvailable, let newVer = UpdateManager.shared.latestVersion {
            menu.addItem(NSMenuItem.separator())
            let updateItem = NSMenuItem(
                title: "✨ Yeni Sürüm (\(newVer)) — Tek Tıkla Güncelle",
                action: #selector(handleOneClickUpdate),
                keyEquivalent: ""
            )
            updateItem.target = self
            menu.addItem(updateItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Hızlı İşlemler
        let refreshItem = NSMenuItem(title: "⚡ Şimdi Yenile", action: #selector(handleRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let checkUpdateItem = NSMenuItem(title: "🔄 Güncellemeleri Denetle...", action: #selector(handleCheckUpdate), keyEquivalent: "")
        checkUpdateItem.target = self
        menu.addItem(checkUpdateItem)
        
        let storageItem = NSMenuItem(title: "⚙️ Depolama Ayarlarını Aç...", action: #selector(openStorageSettings), keyEquivalent: "")
        storageItem.target = self
        menu.addItem(storageItem)
        
        let diskUtilItem = NSMenuItem(title: "🛠️ Disk İzlencesi'ni Aç...", action: #selector(openDiskUtility), keyEquivalent: "")
        diskUtilItem.target = self
        menu.addItem(diskUtilItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Görünüm Alt Menüsü
        let viewMenu = NSMenu(title: "Görünüm Ayarları")
        
        // 3a. Gösterge Formatları
        let modeHeader = NSMenuItem(title: "GÖSTERGE FORMATI", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        viewMenu.addItem(modeHeader)
        
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = (config.displayMode == mode) ? .on : .off
            viewMenu.addItem(item)
        }
        
        viewMenu.addItem(NSMenuItem.separator())
        
        // 3b. İkon Stili
        let iconHeader = NSMenuItem(title: "İKON TİPİ", action: nil, keyEquivalent: "")
        iconHeader.isEnabled = false
        viewMenu.addItem(iconHeader)
        
        for style in IconStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(changeIconStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            item.state = (config.iconStyle == style) ? .on : .off
            viewMenu.addItem(item)
        }
        
        viewMenu.addItem(NSMenuItem.separator())
        
        // 3c. Yenileme Sıklığı
        let freqHeader = NSMenuItem(title: "GÜNCELLEME SIKLIĞI", action: nil, keyEquivalent: "")
        freqHeader.isEnabled = false
        viewMenu.addItem(freqHeader)
        
        let intervals: [(String, TimeInterval)] = [
            ("5 Saniyede Bir", 5.0),
            ("15 Saniyede Bir", 15.0),
            ("30 Saniyede Bir (Önerilen)", 30.0),
            ("60 Saniyede Bir", 60.0)
        ]
        for (label, interval) in intervals {
            let item = NSMenuItem(title: label, action: #selector(changeRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval
            item.state = (abs(config.refreshInterval - interval) < 0.1) ? .on : .off
            viewMenu.addItem(item)
        }
        
        let viewMenuItem = NSMenuItem(title: "🎨 Görünüm & Ayarlar", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        menu.addItem(viewMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Otomatik Başlatma Seçeneği
        let autoStartItem = NSMenuItem(title: "🚀 Mac Açılışında Otomatik Başlat", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = config.isAutoStartEnabled ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Kapatma Butonu (Sağ Tık / Sol Tık Kapatma)
        let quitItem = NSMenuItem(title: "❌ DiskBar'ı Kapat", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    // MARK: - NSMenuDelegate
    
    public func menuWillOpen(_ menu: NSMenu) {
        refreshData()
    }
    
    // MARK: - Aksiyonlar
    
    @objc private func handleRefresh() {
        refreshData()
    }
    
    @objc private func openStorageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func openDiskUtility() {
        let path = "/System/Applications/Utilities/Disk Utility.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
    
    @objc private func changeDisplayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? DisplayMode else { return }
        config.displayMode = mode
        updateStatusButton()
        rebuildMenu()
    }
    
    @objc private func changeIconStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? IconStyle else { return }
        config.iconStyle = style
        updateStatusButton()
        rebuildMenu()
    }
    
    @objc private func changeRefreshInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        config.refreshInterval = interval
        startTimer()
        rebuildMenu()
    }
    
    @objc private func toggleAutoStart() {
        let newState = !config.isAutoStartEnabled
        let binaryPath = Bundle.main.executablePath ?? "/Users/ugurmac/Applications/DiskBar.app/Contents/MacOS/DiskBar"
        config.setAutoStart(enabled: newState, appPath: binaryPath)
        rebuildMenu()
    }
    
    @objc private func handleOneClickUpdate() {
        UpdateManager.shared.performOneClickUpdate()
    }
    
    @objc private func handleCheckUpdate() {
        UpdateManager.shared.checkForUpdates(isManual: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
