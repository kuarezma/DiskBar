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
            return val > 0 ? val : 20.0
        }
        set {
            defaults.set(newValue, forKey: kRefreshInterval)
        }
    }
    
    public static var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.ugur.diskbar.plist")
    }
    
    public var isAutoStartEnabled: Bool {
        return FileManager.default.fileExists(atPath: DiskBarConfig.launchAgentURL.path)
    }
    
    public func setAutoStart(enabled: Bool, appPath: String) {
        let url = DiskBarConfig.launchAgentURL
        let fm = FileManager.default
        
        if enabled {
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.ugur.diskbar</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
            
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plistContent.write(to: url, atomically: true, encoding: .utf8)
            
            // launchctl load
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["load", url.path]
            try? task.run()
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["unload", url.path]
            try? task.run()
            
            try? fm.removeItem(at: url)
        }
    }
}
