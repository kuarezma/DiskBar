//go:build linux

package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"github.com/kuarezma/DiskBar/internal/common"
)

const currentVersion = "1.1.0"

type DiskStats struct {
	MountPoint  string
	TotalBytes  uint64
	FreeBytes   uint64
	UsedBytes   uint64
	UsedPercent float64
	IsLow       bool
	IsCritical  bool
}

func getStats(path string) (DiskStats, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return DiskStats{}, err
	}

	blockSize := uint64(stat.Frsize)
	if blockSize == 0 {
		blockSize = uint64(stat.Bsize)
	}

	total := stat.Blocks * blockSize
	free := stat.Bavail * blockSize
	var used uint64
	if total > free {
		used = total - free
	}

	percent := 0.0
	if total > 0 {
		percent = (float64(used) / float64(total)) * 100.0
	}

	isCritical := total > 0 && (free < common.CriticalSpaceThresholdBytes || percent > 95.0)
	isLow := total > 0 && (free < common.LowSpaceThresholdBytes || percent > 90.0)

	return DiskStats{
		MountPoint:  path,
		TotalBytes:  total,
		FreeBytes:   free,
		UsedBytes:   used,
		UsedPercent: percent,
		IsLow:       isLow,
		IsCritical:  isCritical,
	}, nil
}

func sendNotification(title, message string, isUrgent bool) {
	urgency := "normal"
	if isUrgent {
		urgency = "critical"
	}
	_ = exec.Command("notify-send", "-u", urgency, "-a", "DiskBar", title, message).Run()
}

func checkUpdates(lastNotified *string) {
	client := http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", "https://api.github.com/repos/kuarezma/DiskBar/releases/latest", nil)
	if err != nil {
		return
	}
	req.Header.Set("User-Agent", fmt.Sprintf("DiskBar/%s (Linux)", currentVersion))
	req.Header.Set("Accept", "application/vnd.github+json")

	resp, err := client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return
	}

	var data struct {
		TagName string `json:"tag_name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil || data.TagName == "" {
		return
	}

	if common.IsVersionHigher(data.TagName, currentVersion) && *lastNotified != data.TagName {
		*lastNotified = data.TagName
		sendNotification(
			"DiskBar Güncellemesi Mevcut!",
			fmt.Sprintf("Yeni sürüm: %s yayınlandı. Güncellemek için: diskbar --update", data.TagName),
			false,
		)
	}
}

func performUpdate() error {
	fmt.Println("🚀 DiskBar güncelleniyor...")
	arch := "amd64"
	if runtime.GOARCH == "arm64" {
		arch = "arm64"
	}
	url := fmt.Sprintf("https://github.com/kuarezma/DiskBar/releases/latest/download/diskbar-linux-%s", arch)

	exePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("yürütülebilir dosya yolu bulunamadı: %w", err)
	}
	if resolved, err := filepath.EvalSymlinks(exePath); err == nil {
		exePath = resolved
	}

	client := http.Client{Timeout: 60 * time.Second}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", fmt.Sprintf("DiskBar/%s (Linux)", currentVersion))

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("indirme başarısız: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("sunucu HTTP %d yanıtı döndürdü", resp.StatusCode)
	}

	tmpPath := exePath + ".new"
	out, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
	if err != nil {
		return fmt.Errorf("geçici dosya oluşturulamadı (izin/sudo gerekebilir): %w", err)
	}

	written, copyErr := io.Copy(out, resp.Body)
	closeErr := out.Close()
	if copyErr != nil || closeErr != nil {
		_ = os.Remove(tmpPath)
		if copyErr != nil {
			return fmt.Errorf("indirme yarım kaldı: %w", copyErr)
		}
		return closeErr
	}

	if written < 100_000 {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("indirilen dosya geçersiz (boyut: %d bayt)", written)
	}

	if err := os.Rename(tmpPath, exePath); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("dosya değiştirilemedi (sudo gerekebilir): %w", err)
	}

	fmt.Println("✅ DiskBar başarıyla en son sürüme güncellendi!")
	sendNotification("DiskBar Güncellendi", "Uygulama başarıyla en son sürüme güncellendi.", false)
	return nil
}

func autostartDesktopPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".config", "autostart", "diskbar.desktop"), nil
}

func setupAutostart() error {
	desktopPath, err := autostartDesktopPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(desktopPath), 0755); err != nil {
		return err
	}
	binPath, err := os.Executable()
	if err != nil {
		binPath = "diskbar"
	} else if resolved, err := filepath.EvalSymlinks(binPath); err == nil {
		binPath = resolved
	}

	desktopContent := fmt.Sprintf(`[Desktop Entry]
Type=Application
Name=DiskBar
Comment=Linux Disk Space Monitor
Exec="%s" --daemon
Terminal=false
Categories=Utility;System;
X-GNOME-Autostart-enabled=true
`, binPath)

	return os.WriteFile(desktopPath, []byte(desktopContent), 0644)
}

func removeAutostart() error {
	desktopPath, err := autostartDesktopPath()
	if err != nil {
		return err
	}
	if err := os.Remove(desktopPath); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func alertLevel(s DiskStats) int {
	if s.IsCritical {
		return 2
	}
	if s.IsLow {
		return 1
	}
	return 0
}

func main() {
	daemonFlag := flag.Bool("daemon", false, "Arka planda servis olarak çalıştır")
	autostartFlag := flag.Bool("autostart", false, "Linux oturum açılışında otomatik başlatmayı kur")
	removeAutostartFlag := flag.Bool("remove-autostart", false, "Linux otomatik başlatma kaydını kaldır")
	updateFlag := flag.Bool("update", false, "DiskBar'ı en son sürüme güncelle")
	versionFlag := flag.Bool("version", false, "Sürüm bilgisini göster")
	intervalFlag := flag.Int("interval", 30, "Saniye cinsinden kontrol aralığı (en az 1)")
	targetPath := flag.String("path", "/", "İzlenecek disk yolu (Varsayılan: /)")
	flag.Parse()

	if *versionFlag {
		fmt.Printf("DiskBar v%s (linux/%s)\n", currentVersion, runtime.GOARCH)
		return
	}

	if *updateFlag {
		if err := performUpdate(); err != nil {
			fmt.Printf("❌ %v\n", err)
			os.Exit(1)
		}
		return
	}

	if *removeAutostartFlag {
		if err := removeAutostart(); err != nil {
			fmt.Printf("❌ Autostart kaldırılamadı: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("✅ DiskBar Linux autostart kaydı kaldırıldı.")
		return
	}

	if *autostartFlag {
		if err := setupAutostart(); err != nil {
			fmt.Printf("❌ Autostart kurulumu başarısız: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("✅ DiskBar Linux autostart başarıyla kuruldu (~/.config/autostart/diskbar.desktop)")
		return
	}

	if *intervalFlag < 1 {
		fmt.Println("❌ Hata: --interval değeri en az 1 saniye olmalıdır.")
		os.Exit(1)
	}

	stats, err := getStats(*targetPath)
	if err != nil {
		fmt.Printf("❌ Disk bilgisi alınamadı: %v\n", err)
		os.Exit(1)
	}

	if !*daemonFlag {
		fmt.Printf("💾 DiskBar v%s: %s Boş / %s Toplam (%%%.1f Dolu) [Hedef: %s]\n",
			currentVersion,
			common.FormatBytes(stats.FreeBytes),
			common.FormatBytes(stats.TotalBytes),
			stats.UsedPercent,
			stats.MountPoint,
		)
		return
	}

	fmt.Printf("🚀 DiskBar v%s Linux Daemon başlatıldı. İzlenen: %s (Kontrol: %d sn)\n", currentVersion, *targetPath, *intervalFlag)
	sendNotification("DiskBar Başlatıldı", fmt.Sprintf("Canlı Boş Alan: %s (%%%.1f Dolu)", common.FormatBytes(stats.FreeBytes), stats.UsedPercent), false)

	// Arka planda güncelleme denetimi
	go func() {
		var lastNotified string
		time.Sleep(5 * time.Second)
		checkUpdates(&lastNotified)
		updTicker := time.NewTicker(2 * time.Hour)
		defer updTicker.Stop()
		for range updTicker.C {
			checkUpdates(&lastNotified)
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	ticker := time.NewTicker(time.Duration(*intervalFlag) * time.Second)
	defer ticker.Stop()

	lastFree := stats.FreeBytes
	lastAlert := alertLevel(stats)

	for {
		select {
		case <-sigChan:
			fmt.Println("\n🛑 DiskBar kapatılıyor...")
			return
		case <-ticker.C:
			current, err := getStats(*targetPath)
			if err != nil {
				continue
			}
			if current.FreeBytes != lastFree {
				diff := int64(current.FreeBytes) - int64(lastFree)
				sign := "+"
				if diff < 0 {
					sign = "-"
					diff = -diff
				}
				fmt.Printf("[%s] Disk değişimi: %s%s -> Yeni Boş Alan: %s (%%%.1f)\n",
					time.Now().Format("15:04:05"),
					sign,
					common.FormatBytes(uint64(diff)),
					common.FormatBytes(current.FreeBytes),
					current.UsedPercent,
				)

				curAlert := alertLevel(current)
				if curAlert > lastAlert {
					if curAlert == 2 {
						sendNotification("Kritik Disk Alanı Uyarısı!", fmt.Sprintf("Diskte yalnızca %s boş alan kaldı!", common.FormatBytes(current.FreeBytes)), true)
					} else if curAlert == 1 {
						sendNotification("Düşük Disk Alanı Uyarısı!", fmt.Sprintf("Diskte %s boş alan kaldı (%%%.1f dolu).", common.FormatBytes(current.FreeBytes), current.UsedPercent), true)
					}
				}
				lastAlert = curAlert
				lastFree = current.FreeBytes
			}
		}
	}
}
