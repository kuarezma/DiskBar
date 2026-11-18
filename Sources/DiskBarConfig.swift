import Foundation

public enum DisplayMode: String, CaseIterable {
    case iconAndFreeSpace = "iconAndFreeSpace"     // 💾 5.5 GB Boş
    case freeSpaceOnly = "freeSpaceOnly"           // 5.5 GB Boş
    case freeAndTotal = "freeAndTotal"             // 5.5 / 245 GB
    case percentUsed = "percentUsed"               // %97.8 Dolu
    case percentFree = "percentFree"               // %2.2 Boş
    case compactIconOnly = "compactIconOnly"       // Yalnızca İkon

    public var title: String {
        switch self {
        case .iconAndFreeSpace: return "İkon + Boş Alan (Örn: 5.5 GB Boş)"
        case .freeSpaceOnly: return "Sadece Boş Alan (Örn: 5.5 GB)"
        case .freeAndTotal: return "Boş / Toplam Alan (Örn: 5.5 / 245 GB)"
        case .percentUsed: return "Doluluk Oranı (Örn: %97.8 Dolu)"
        case .percentFree: return "Boş Alan Oranı (Örn: %2.2 Boş)"
        case .compactIconOnly: return "Kompakt (Yalnızca İkon)"
        }
    }
}

public enum IconStyle: String, CaseIterable {
    case sfSymbolDrive = "sfSymbolDrive"
    case dynamicGauge = "dynamicGauge"

    public var title: String {
        switch self {
        case .sfSymbolDrive: return "Apple Sürücü Simgesi (SF Symbol)"
        case .dynamicGauge: return "Dinamik Halka Göstergesi (Canlı)"
        }
    }
}

public class DiskBarConfig {
    public static let shared = DiskBarConfig()

    private let defaults = UserDefaults.standard
    private let kDisplayMode = "DiskBar_DisplayMode"
    private let kIconStyle = "DiskBar_IconStyle"
    private let kRefreshInterval = "DiskBar_RefreshInterval"
    private let kSelectedVolumePath = "DiskBar_SelectedVolumePath"
    private let kLowSpaceNotifications = "DiskBar_LowSpaceNotifications"

    public var displayMode: DisplayMode {
        get {
            if let raw = defaults.string(forKey: kDisplayMode),
               let mode = DisplayMode(rawValue: raw) {
                return mode
            }
            return .iconAndFreeSpace
        }
        set {
            defaults.set(newValue.rawValue, forKey: kDisplayMode)
        }
    }

    public var iconStyle: IconStyle {
        get {
            if let raw = defaults.string(forKey: kIconStyle),
               let style = IconStyle(rawValue: raw) {
                return style
            }
            return .dynamicGauge
        }
        set {
            defaults.set(newValue.rawValue, forKey: kIconStyle)
        }
    }

    public var refreshInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: kRefreshInterval)
            return val >= 5.0 ? val : 60.0
        }
        set {
            defaults.set(max(5.0, newValue), forKey: kRefreshInterval)
        }
    }

    public var selectedVolumePath: String {
        get {
            let path = defaults.string(forKey: kSelectedVolumePath) ?? "/"
            return path.isEmpty ? "/" : path
        }
        set {
            defaults.set(newValue.isEmpty ? "/" : newValue, forKey: kSelectedVolumePath)
        }
    }

    public var lowSpaceNotificationsEnabled: Bool {
        get {
            if defaults.object(forKey: kLowSpaceNotifications) == nil {
                return true
            }
            return defaults.bool(forKey: kLowSpaceNotifications)
        }
        set {
            defaults.set(newValue, forKey: kLowSpaceNotifications)
        }
    }

    public static var launchAgentLabel: String {
        return Bundle.main.bundleIdentifier ?? "com.ugur.diskbar"
    }

    public static var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    public static var defaultAppBundleURL: URL {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return Bundle.main.bundleURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/DiskBar.app")
    }

    public static var defaultExecutablePath: String {
        if let execPath = Bundle.main.executablePath, !execPath.isEmpty {
            return execPath
        }
        return defaultAppBundleURL
            .appendingPathComponent("Contents/MacOS/DiskBar")
            .path
    }

    public var isAutoStartEnabled: Bool {
        return FileManager.default.fileExists(atPath: DiskBarConfig.launchAgentURL.path)
    }

    @discardableResult
    public func setAutoStart(enabled: Bool, appPath: String = DiskBarConfig.defaultExecutablePath) -> Bool {
        let url = DiskBarConfig.launchAgentURL
        let fm = FileManager.default
        let uid = getuid()
        let serviceTarget = "gui/\(uid)/\(DiskBarConfig.launchAgentLabel)"

        if enabled {
            let plistDict: [String: Any] = [
                "Label": DiskBarConfig.launchAgentLabel,
                "ProgramArguments": [appPath],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]

            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                try data.write(to: url, options: .atomic)
            } catch {
                return false
            }

            // Eğer daha önce launchd ile devre dışı bırakıldıysa etkinleştir (mevcut örneği tekrar başlatmadan)
            runLaunchctl(["enable", serviceTarget])
            return true
        } else {
            // Çalışan mevcut uygulamayı öldürmeden sadece açılış kaydını kaldır
            do {
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
            } catch {
                return false
            }
            runLaunchctl(["disable", serviceTarget])
            return true
        }
    }

    private func runLaunchctl(_ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // launchctl hataları sessizce yok sayılır
        }
    }
}
