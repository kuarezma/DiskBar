import AppKit
import Foundation

public class UpdateManager {
    public static let shared = UpdateManager()
    
    public let currentVersion = "1.0.0"
    public private(set) var latestVersion: String?
    public private(set) var zipDownloadURL: URL?
    public private(set) var releasePageURL: URL?
    public private(set) var isUpdateAvailable = false
    public var onUpdateStatusChanged: (() -> Void)?
    
    private var checkTimer: Timer?
    private let repoURL = "https://api.github.com/repos/kuarezma/DiskBar/releases/latest"
    
    private init() {}
    
    public func startPeriodicChecks() {
        // Uygulama açıldıktan 4 saniye sonra ilk kontrolü yap
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.checkForUpdates(isManual: false)
        }
        
        // Her 2 saatte bir arka planda kontrol et
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 7200, repeats: true) { [weak self] _ in
            self?.checkForUpdates(isManual: false)
        }
    }
    
    public func checkForUpdates(isManual: Bool = false) {
        guard let url = URL(string: repoURL) else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("DiskBar-App", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                if isManual {
                    DispatchQueue.main.async {
                        self?.showAlert(title: "Bağlantı Hatası", message: "Güncellemeler kontrol edilirken GitHub sunucusuna ulaşılamadı.")
                    }
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    
                    let cleanRemote = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                    let cleanCurrent = self.currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                    
                    var zipURL: URL?
                    if let assets = json["assets"] as? [[String: Any]] {
                        for asset in assets {
                            if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                               let download = asset["browser_download_url"] as? String {
                                zipURL = URL(string: download)
                                break
                            }
                        }
                    }
                    
                    let htmlURL = (json["html_url"] as? String).flatMap { URL(string: $0) }
                    
                    DispatchQueue.main.async {
                        if self.isVersion(cleanRemote, higherThan: cleanCurrent) {
                            self.isUpdateAvailable = true
                            self.latestVersion = tagName
                            self.zipDownloadURL = zipURL
                            self.releasePageURL = htmlURL
                            self.onUpdateStatusChanged?()
                            
                            // macOS yerel sesli ve görsel bildirim gönder
                            self.sendNotification(
                                title: "🚀 DiskBar Güncellemesi Mevcut!",
                                message: "Yeni sürüm: \(tagName) hazır. Menüden tek tıkla güncelleyebilirsiniz."
                            )
                            
                            if isManual {
                                self.showUpdatePrompt(newVersion: tagName)
                            }
                        } else {
                            self.isUpdateAvailable = false
                            self.onUpdateStatusChanged?()
                            if isManual {
                                self.showAlert(title: "DiskBar Güncel", message: "Zaten en son sürümü (v\(self.currentVersion)) kullanıyorsunuz.")
                            }
                        }
                    }
                }
            } catch {
                if isManual {
                    DispatchQueue.main.async {
                        self.showAlert(title: "Hata", message: "Sürüm bilgisi çözümlenemedi.")
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Tek Tıkla Güncelleme
    
    public func performOneClickUpdate() {
        sendNotification(title: "DiskBar Güncelleniyor...", message: "En son sürüm indiriliyor ve kuruluyor...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // install.sh betiğini arka planda çalıştırarak en son paketi kur ve uygulamayı yeniden başlat
            let script = """
            TMP_DIR=$(mktemp -d)
            cd "$TMP_DIR"
            curl -fsSL https://raw.githubusercontent.com/kuarezma/DiskBar/main/install.sh | bash
            rm -rf "$TMP_DIR"
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.sendNotification(
                            title: "🎉 Güncelleme Başarılı!",
                            message: "DiskBar en son sürüme güncellendi ve yeniden başlatılıyor."
                        )
                        
                        // Güncel uygulamayı aç ve mevcut süreci kapat
                        let appPath = "/Users/ugurmac/Applications/DiskBar.app"
                        NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showAlert(title: "Güncelleme Başarısız", message: "Güncelleme sırasında bir hata oluştu. Lütfen GitHub sayfasından DMG dosyasını indirin.")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: "Güncelleme Hatası", message: error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Bildirim & İletişim
    
    private func sendNotification(title: String, message: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMsg = message.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "display notification \"\(escapedMsg)\" with title \"\(escapedTitle)\" sound name \"Glass\""
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]
        try? proc.run()
    }
    
    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }
    
    private func showUpdatePrompt(newVersion: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Yeni Sürüm Mevcut! (\(newVersion))"
        alert.informativeText = "DiskBar \(newVersion) yayınlandı. Şimdi tek tıkla güncellemek ister misiniz?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "⚡ Şimdi Güncelle")
        alert.addButton(withTitle: "Daha Sonra")
        
        if alert.runModal() == .alertFirstButtonReturn {
            performOneClickUpdate()
        }
    }
    
    // MARK: - Sürüm Karşılaştırma
    
    private func isVersion(_ v1: String, higherThan v2: String) -> Bool {
        let p1 = v1.split(separator: ".").compactMap { Int($0) }
        let p2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(p1.count, p2.count)
        for i in 0..<maxCount {
            let num1 = i < p1.count ? p1[i] : 0
            let num2 = i < p2.count ? p2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }
}
