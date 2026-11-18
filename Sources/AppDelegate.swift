import AppKit

private enum SpaceAlertLevel: Int {
    case normal = 0
    case low = 1
    case critical = 2
}

public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var currentStats: DiskStats = DiskStats.current()
    private var headerCardView: HeaderCardView?
    private let config = DiskBarConfig.shared
    private var lastAlertLevel: SpaceAlertLevel = .normal
    private var isMenuOpen = false
    private var pendingMenuRebuild = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // İlk veriyi al (bildirim tetiklemeden başlangıç eşik durumunu sabitle)
        currentStats = DiskStats.current(forPath: config.selectedVolumePath)
        if currentStats.volumePath != config.selectedVolumePath {
            config.selectedVolumePath = currentStats.volumePath
        }
        lastAlertLevel = alertLevel(for: currentStats)
        updateStatusButton()

        rebuildMenu()
        startTimer()

        // Sürücü takılma/çıkarılma bildirimlerini dinle
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(diskDidChange), name: NSWorkspace.didMountNotification, object: nil)
        ws.addObserver(self, selector: #selector(diskDidChange), name: NSWorkspace.didUnmountNotification, object: nil)

        // Otomatik güncelleme kontrolcüsünü bağla
        UpdateManager.shared.onUpdateStatusChanged = { [weak self] in
            self?.scheduleMenuRebuild()
        }
        UpdateManager.shared.startPeriodicChecks()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        UpdateManager.shared.stopPeriodicChecks()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Zamanlayıcı & Güncelleme

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: config.refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshData()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func diskDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshData()
            self.scheduleMenuRebuild()
        }
    }

    @objc public func refreshData() {
        let stats = DiskStats.current(forPath: config.selectedVolumePath)
        if stats.volumePath != config.selectedVolumePath {
            config.selectedVolumePath = stats.volumePath
        }
        applyStats(stats)
    }

    public func applyStats(_ stats: DiskStats) {
        currentStats = stats
        updateStatusButton()
        headerCardView?.update(stats: stats)
        evaluateSpaceAlert(for: stats)
    }

    private func alertLevel(for stats: DiskStats) -> SpaceAlertLevel {
        if stats.isCriticalSpace { return .critical }
        if stats.isLowSpace { return .low }
        return .normal
    }

    private func evaluateSpaceAlert(for stats: DiskStats) {
        let newLevel = alertLevel(for: stats)
        defer { lastAlertLevel = newLevel }

        guard config.lowSpaceNotificationsEnabled else { return }
        guard newLevel.rawValue > lastAlertLevel.rawValue else { return }

        switch newLevel {
        case .critical:
            UpdateManager.shared.sendNotification(
                title: "Kritik Disk Alanı! (\(stats.volumeName))",
                message: "Yalnızca \(stats.freeFormatted) (\(stats.percentFreeFormatted)) boş alan kaldı!"
            )
        case .low:
            UpdateManager.shared.sendNotification(
                title: "Düşük Disk Alanı (\(stats.volumeName))",
                message: "Boş alan \(stats.freeFormatted) (\(stats.percentFreeFormatted)) seviyesine düştü."
            )
        case .normal:
            break
        }
    }

    private func scheduleMenuRebuild() {
        if isMenuOpen {
            pendingMenuRebuild = true
        } else {
            rebuildMenu()
        }
    }

    // MARK: - Menü Çubuğu Butonu Güncelleme

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        if config.displayMode == .freeSpaceOnly {
            button.image = nil
            button.imagePosition = .noImage
        } else {
            switch config.iconStyle {
            case .dynamicGauge:
                button.image = createGaugeIcon(stats: currentStats)
            case .sfSymbolDrive:
                button.image = createSymbolIcon(stats: currentStats)
            }
            button.imagePosition = (config.displayMode == .compactIconOnly) ? .imageOnly : .imageLeading
        }

        switch config.displayMode {
        case .iconAndFreeSpace:
            button.title = " \(currentStats.freeFormatted) Boş"
        case .freeSpaceOnly:
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

        var tooltipLines = [
            "DiskBar: \(currentStats.volumeName)",
            "• Boş Alan: \(currentStats.freeFormatted) (\(currentStats.percentFreeFormatted))",
            "• Kullanılan: \(currentStats.usedFormatted) (\(currentStats.percentUsedFormatted))",
            "• Toplam Boyut: \(currentStats.totalFormatted)"
        ]
        if currentStats.purgeableBytes > 0 {
            tooltipLines.append("• Temizlenebilir (APFS): \(currentStats.purgeableFormatted)")
        }
        tooltipLines.append("• Tıkla: Detaylı menü ve ayarlar")
        button.toolTip = tooltipLines.joined(separator: "\n")
    }

    // MARK: - İkon Çizimleri

    private func createGaugeIcon(stats: DiskStats) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let isAlert = stats.isCriticalSpace || stats.isLowSpace

        let img = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.2
            let lineWidth: CGFloat = 2.2

            // Arka plan çemberi
            let bgPath = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            bgPath.lineWidth = lineWidth
            let bgColor: NSColor = isAlert
                ? NSColor.gray.withAlphaComponent(0.35)
                : NSColor.labelColor.withAlphaComponent(0.25)
            bgColor.setStroke()
            bgPath.stroke()

            // Doluluk yayı
            let fraction = CGFloat(stats.usedFraction)
            if fraction > 0 {
                let startAngle: CGFloat = 90.0
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
            }

            return true
        }
        img.isTemplate = !isAlert
        return img
    }

    private func createSymbolIcon(stats: DiskStats) -> NSImage {
        let symName: String
        if stats.volumePath != "/" {
            symName = stats.isCriticalSpace ? "externaldrive.fill" : "externaldrive"
        } else {
            symName = stats.isCriticalSpace ? "internaldrive.fill" : "internaldrive"
        }

        if let base = NSImage(systemSymbolName: symName, accessibilityDescription: "Disk") {
            if stats.isCriticalSpace || stats.isLowSpace {
                let color: NSColor = stats.isCriticalSpace ? .systemRed : .systemOrange
                let symbolConfig = NSImage.SymbolConfiguration(paletteColors: [color])
                if let colored = base.withSymbolConfiguration(symbolConfig) {
                    colored.isTemplate = false
                    return colored
                }
            }
            let img = base.copy() as! NSImage
            img.isTemplate = true
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

        // 1b. Yeni sürüm varsa en üstte tek tıkla güncelleme butonu göster
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

        // 1c. Bağlı Diskler Alt Menüsü (Harici/ikinci diskler varsa veya seçim için)
        let volumes = DiskStats.mountedVolumes()
        if volumes.count > 1 {
            menu.addItem(NSMenuItem.separator())
            let diskMenu = NSMenu(title: "İzlenen Disk")
            for vol in volumes {
                let label = "\(vol.volumeName) — \(vol.freeFormatted) Boş / \(vol.totalFormatted)"
                let item = NSMenuItem(title: label, action: #selector(changeSelectedVolume(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = vol.volumePath
                item.state = (vol.volumePath == config.selectedVolumePath) ? .on : .off
                diskMenu.addItem(item)
            }
            let diskMenuItem = NSMenuItem(title: "💽 Diskler (\(volumes.count))", action: nil, keyEquivalent: "")
            diskMenuItem.submenu = diskMenu
            menu.addItem(diskMenuItem)
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

        let freqHeader = NSMenuItem(title: "GÜNCELLEME SIKLIĞI", action: nil, keyEquivalent: "")
        freqHeader.isEnabled = false
        viewMenu.addItem(freqHeader)

        let intervals: [(String, TimeInterval)] = [
            ("15 Saniyede Bir", 15.0),
            ("30 Saniyede Bir", 30.0),
            ("1 Dakikada Bir (Önerilen)", 60.0),
            ("5 Dakikada Bir", 300.0)
        ]
        for (label, interval) in intervals {
            let item = NSMenuItem(title: label, action: #selector(changeRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval
            item.state = (abs(config.refreshInterval - interval) < 0.1) ? .on : .off
            viewMenu.addItem(item)
        }

        viewMenu.addItem(NSMenuItem.separator())

        let alertItem = NSMenuItem(title: "🔔 Düşük Alan Bildirimleri", action: #selector(toggleLowSpaceNotifications), keyEquivalent: "")
        alertItem.target = self
        alertItem.state = config.lowSpaceNotificationsEnabled ? .on : .off
        viewMenu.addItem(alertItem)

        let viewMenuItem = NSMenuItem(title: "🎨 Görünüm & Ayarlar", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        menu.addItem(viewMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Otomatik Başlatma Seçeneği
        let autoStartItem = NSMenuItem(title: "🚀 Mac Açılışında Otomatik Başlat", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = config.isAutoStartEnabled ? .on : .off
        menu.addItem(autoStartItem)

        // 4b. Sürüm Bilgisi
        let versionItem = NSMenuItem(title: "DiskBar v\(UpdateManager.shared.currentVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Kapatma Butonu
        let quitItem = NSMenuItem(title: "❌ DiskBar'ı Kapat", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refreshData()
    }

    public func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if pendingMenuRebuild {
            pendingMenuRebuild = false
            rebuildMenu()
        }
    }

    // MARK: - Aksiyonlar

    @objc private func handleRefresh() {
        refreshData()
    }

    @objc private func openStorageSettings() {
        let modernURL = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")
        if let url = modernURL, NSWorkspace.shared.open(url) {
            return
        }
        // macOS 12 Monterey yedeği
        let legacyPath = "/System/Library/CoreServices/Applications/Storage Management.app"
        if FileManager.default.fileExists(atPath: legacyPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: legacyPath))
        }
    }

    @objc private func openDiskUtility() {
        let path = "/System/Applications/Utilities/Disk Utility.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func changeSelectedVolume(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        config.selectedVolumePath = path
        currentStats = DiskStats.current(forPath: path)
        lastAlertLevel = alertLevel(for: currentStats)
        updateStatusButton()
        headerCardView?.update(stats: currentStats)
        rebuildMenu()
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

    @objc private func toggleLowSpaceNotifications() {
        config.lowSpaceNotificationsEnabled = !config.lowSpaceNotificationsEnabled
        rebuildMenu()
    }

    @objc private func toggleAutoStart() {
        let newState = !config.isAutoStartEnabled
        config.setAutoStart(enabled: newState, appPath: DiskBarConfig.defaultExecutablePath)
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
