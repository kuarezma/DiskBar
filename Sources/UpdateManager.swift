import AppKit
import Foundation

public class UpdateManager {
    public static let shared = UpdateManager()

    public var currentVersion: String {
        if let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !ver.isEmpty {
            return ver
        }
        return "1.1.0"
    }

    public private(set) var latestVersion: String?
    public private(set) var zipDownloadURL: URL?
    public private(set) var releasePageURL: URL?
    public private(set) var isUpdateAvailable = false
    public var onUpdateStatusChanged: (() -> Void)?

    private var checkTimer: Timer?
    private var lastNotifiedVersion: String?
    private var isUpdating = false
    private let repoURL = "https://api.github.com/repos/kuarezma/DiskBar/releases/latest"

    private init() {}

    public func startPeriodicChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.checkForUpdates(isManual: false)
        }

        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 7200, repeats: true) { [weak self] _ in
            self?.checkForUpdates(isManual: false)
        }
        if let timer = checkTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stopPeriodicChecks() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    public func checkForUpdates(isManual: Bool = false) {
        guard let url = URL(string: repoURL) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("DiskBar/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                if isManual {
                    DispatchQueue.main.async {
                        self.showAlert(
                            title: "Bağlantı Hatası",
                            message: "GitHub sunucusuna ulaşılamadı: \(error.localizedDescription)"
                        )
                    }
                }
                return
            }

            if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                if isManual {
                    let msg = httpResp.statusCode == 403
                        ? "GitHub API hız sınırına ulaşıldı. Lütfen birkaç dakika sonra tekrar deneyin."
                        : "Güncelleme sunucusu HTTP \(httpResp.statusCode) hatası döndürdü."
                    DispatchQueue.main.async {
                        self.showAlert(title: "Güncelleme Kontrolü Başarısız", message: msg)
                    }
                }
                return
            }

            guard let data = data else {
                if isManual {
                    DispatchQueue.main.async {
                        self.showAlert(title: "Hata", message: "Sunucudan boş yanıt alındı.")
                    }
                }
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    if isManual {
                        DispatchQueue.main.async {
                            self.showAlert(title: "Hata", message: "Yayınlanmış sürüm bilgisi bulunamadı.")
                        }
                    }
                    return
                }

                let cleanRemote = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let cleanCurrent = self.currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

                var zipURL: URL?
                if let assets = json["assets"] as? [[String: Any]] {
                    // Önce doğrudan DiskBar.zip varlığını ara (Windows ZIP'i ile karışmasın)
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.lowercased() == "diskbar.zip",
                           let download = asset["browser_download_url"] as? String {
                            zipURL = URL(string: download)
                            break
                        }
                    }
                }

                let htmlURL = (json["html_url"] as? String).flatMap { URL(string: $0) }

                DispatchQueue.main.async {
                    let wasAvailable = self.isUpdateAvailable
                    let prevVersion = self.latestVersion

                    if UpdateManager.isVersion(cleanRemote, higherThan: cleanCurrent) {
                        self.isUpdateAvailable = true
                        self.latestVersion = tagName
                        self.zipDownloadURL = zipURL
                        self.releasePageURL = htmlURL

                        if !wasAvailable || prevVersion != tagName {
                            self.onUpdateStatusChanged?()
                        }

                        // Aynı sürüm için arka planda tekrar tekrar bildirim gönderme
                        if self.lastNotifiedVersion != tagName {
                            self.lastNotifiedVersion = tagName
                            self.sendNotification(
                                title: "DiskBar Güncellemesi Mevcut!",
                                message: "Yeni sürüm: \(tagName) hazır. Menüden tek tıkla güncelleyebilirsiniz."
                            )
                        }

                        if isManual {
                            self.showUpdatePrompt(newVersion: tagName)
                        }
                    } else {
                        self.isUpdateAvailable = false
                        self.latestVersion = nil
                        if wasAvailable {
                            self.onUpdateStatusChanged?()
                        }
                        if isManual {
                            self.showAlert(
                                title: "DiskBar Güncel",
                                message: "Zaten en son sürümü (v\(self.currentVersion)) kullanıyorsunuz."
                            )
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

    // MARK: - Tek Tıkla Güncelleme (Derleyici Gerektirmeyen Doğrudan ZIP Kurulumu)

    public func performOneClickUpdate() {
        guard !isUpdating else { return }

        guard let downloadURL = zipDownloadURL else {
            if let page = releasePageURL ?? URL(string: "https://github.com/kuarezma/DiskBar/releases/latest") {
                NSWorkspace.shared.open(page)
            }
            return
        }

        isUpdating = true
        sendNotification(title: "DiskBar Güncelleniyor...", message: "En son sürüm indiriliyor ve kuruluyor...")

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 60
        request.setValue("DiskBar/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async { self.isUpdating = false }
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.showAlert(title: "İndirme Hatası", message: "Paket indirilemedi: \(error.localizedDescription)")
                }
                return
            }

            if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                DispatchQueue.main.async {
                    self.showAlert(title: "İndirme Hatası", message: "Sunucu HTTP \(httpResp.statusCode) döndürdü.")
                }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async {
                    self.showAlert(title: "İndirme Hatası", message: "Geçici dosya oluşturulamadı.")
                }
                return
            }

            let fm = FileManager.default
            let stagingDir = fm.temporaryDirectory.appendingPathComponent("DiskBarUpdate-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: stagingDir) }

            do {
                try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                let zipFile = stagingDir.appendingPathComponent("DiskBar.zip")
                try fm.moveItem(at: tempURL, to: zipFile)

                // ditto ile .app bundle özniteliklerini koruyarak aç
                let unzipProc = Process()
                unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzipProc.arguments = ["-xk", zipFile.path, stagingDir.path]
                try unzipProc.run()
                unzipProc.waitUntilExit()

                guard unzipProc.terminationStatus == 0 else {
                    throw NSError(domain: "DiskBarUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "ZIP arşivi açılamadı."])
                }

                let extractedApp = stagingDir.appendingPathComponent("DiskBar.app")
                guard fm.fileExists(atPath: extractedApp.appendingPathComponent("Contents/MacOS/DiskBar").path) else {
                    throw NSError(domain: "DiskBarUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "İndirilen pakette geçerli DiskBar.app bulunamadı."])
                }

                let targetAppURL = DiskBarConfig.defaultAppBundleURL
                let backupAppURL = stagingDir.appendingPathComponent("DiskBar.backup.app")

                try fm.createDirectory(at: targetAppURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                if fm.fileExists(atPath: targetAppURL.path) {
                    try fm.moveItem(at: targetAppURL, to: backupAppURL)
                }

                do {
                    try fm.moveItem(at: extractedApp, to: targetAppURL)
                } catch {
                    // Başarısız olursa eski uygulamayı geri yükle
                    if fm.fileExists(atPath: backupAppURL.path) {
                        try? fm.moveItem(at: backupAppURL, to: targetAppURL)
                    }
                    throw error
                }

                // Karantina özniteliğini temizle (varsa)
                let xattrProc = Process()
                xattrProc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattrProc.arguments = ["-dr", "com.apple.quarantine", targetAppURL.path]
                try? xattrProc.run()
                xattrProc.waitUntilExit()

                DispatchQueue.main.async {
                    self.sendNotification(
                        title: "Güncelleme Başarılı!",
                        message: "DiskBar \(self.latestVersion ?? "") sürümüne güncellendi ve yeniden başlatılıyor."
                    )
                    let openConfig = NSWorkspace.OpenConfiguration()
                    openConfig.createsNewApplicationInstance = true
                    NSWorkspace.shared.openApplication(at: targetAppURL, configuration: openConfig) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(
                        title: "Güncelleme Başarısız",
                        message: "Güncelleme kurulurken hata oluştu: \(error.localizedDescription)\n\nGitHub sayfasından DMG indirebilirsiniz."
                    )
                }
            }
        }.resume()
    }

    // MARK: - Bildirim & İletişim

    public func sendNotification(title: String, message: String) {
        let escapedTitle = escapeForAppleScript(title)
        let escapedMsg = escapeForAppleScript(message)
        let appleScript = "display notification \"\(escapedMsg)\" with title \"\(escapedTitle)\" sound name \"Glass\""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    private func escapeForAppleScript(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
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
        alert.addButton(withTitle: "Şimdi Güncelle")
        alert.addButton(withTitle: "Daha Sonra")

        if alert.runModal() == .alertFirstButtonReturn {
            performOneClickUpdate()
        }
    }

    // MARK: - Semantik Sürüm Karşılaştırma

    public static func isVersion(_ v1: String, higherThan v2: String) -> Bool {
        let parts1 = v1.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let parts2 = v2.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        let nums1 = parts1[0].split(separator: ".").map { Int($0) ?? 0 }
        let nums2 = parts2[0].split(separator: ".").map { Int($0) ?? 0 }

        let maxCount = max(nums1.count, nums2.count)
        for i in 0..<maxCount {
            let num1 = i < nums1.count ? nums1[i] : 0
            let num2 = i < nums2.count ? nums2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }

        // Aynı ana sürümde stabil sürüm, pre-release'ten (örn: 1.1.0 > 1.1.0-beta.1) büyüktür
        let isPre1 = parts1.count > 1
        let isPre2 = parts2.count > 1
        if isPre1 != isPre2 {
            return !isPre1 && isPre2
        }
        if isPre1 && isPre2 {
            return String(parts1[1]) > String(parts2[1])
        }
        return false
    }
}
