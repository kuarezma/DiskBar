//go:build linux

package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

type DiskStats struct {
	MountPoint  string
	TotalBytes  uint64
	FreeBytes   uint64
	UsedBytes   uint64
	UsedPercent float64
	IsLow       bool
}

func getStats(path string) (DiskStats, error) {
	var stat syscall.Statfs_t
	err := syscall.Statfs(path, &stat)
	if err != nil {
		return DiskStats{}, err
	}
	total := stat.Blocks * uint64(stat.Bsize)
	free := stat.Bavail * uint64(stat.Bsize)
	used := total - free
	percent := 0.0
	if total > 0 {
		percent = (float64(used) / float64(total)) * 100.0
	}
	return DiskStats{
		MountPoint:  path,
		TotalBytes:  total,
		FreeBytes:   free,
		UsedBytes:   used,
		UsedPercent: percent,
		IsLow:       free < (10*1000*1000*1000) || percent > 90.0,
	}, nil
}

func formatBytes(bytes uint64) string {
	const (
		KB = 1000
		MB = KB * 1000
		GB = MB * 1000
		TB = GB * 1000
	)
	switch {
	case bytes >= TB:
		return fmt.Sprintf("%.2f TB", float64(bytes)/float64(TB))
	case bytes >= GB:
		return fmt.Sprintf("%.1f GB", float64(bytes)/float64(GB))
	case bytes >= MB:
		return fmt.Sprintf("%.1f MB", float64(bytes)/float64(MB))
	default:
		return fmt.Sprintf("%d Bytes", bytes)
	}
}

func sendNotification(title, message string, isUrgent bool) {
	urgency := "normal"
	if isUrgent {
		urgency = "critical"
	}
	_ = exec.Command("notify-send", "-u", urgency, "-a", "DiskBar", title, message).Run()
}

func setupAutostart() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	dir := filepath.Join(home, ".config", "autostart")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	binPath, err := os.Executable()
	if err != nil {
		binPath = "diskbar"
	}
	desktopContent := fmt.Sprintf(`[Desktop Entry]
Type=Application
Name=DiskBar
Comment=Linux Disk Space Monitor
Exec=%s --daemon
Terminal=false
Categories=Utility;System;
X-GNOME-Autostart-enabled=true
`, binPath)

	return os.WriteFile(filepath.Join(dir, "diskbar.desktop"), []byte(desktopContent), 0644)
}

func main() {
	daemonFlag := flag.Bool("daemon", false, "Arka planda servis olarak çalıştır")
	autostartFlag := flag.Bool("autostart", false, "Linux oturum açılışında otomatik başlatmayı kur")
	intervalFlag := flag.Int("interval", 3, "Saniye cinsinden kontrol aralığı")
	targetPath := flag.String("path", "/", "İzlenecek disk yolu (Varsayılan: /)")
	flag.Parse()

	if *autostartFlag {
		if err := setupAutostart(); err != nil {
			fmt.Printf("❌ Autostart kurulumu başarısız: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("✅ DiskBar Linux autostart başarıyla kuruldu (~/.config/autostart/diskbar.desktop)")
		return
	}

	stats, err := getStats(*targetPath)
	if err != nil {
		fmt.Printf("❌ Disk bilgisi alınamadı: %v\n", err)
		os.Exit(1)
	}

	if !*daemonFlag {
		fmt.Printf("💾 DiskBar: %s Boş / %s Toplam (%%%.1f Dolu) [Hedef: %s]\n",
			formatBytes(stats.FreeBytes),
			formatBytes(stats.TotalBytes),
			stats.UsedPercent,
			stats.MountPoint,
		)
		return
	}

	fmt.Printf("🚀 DiskBar Linux Daemon başlatıldı. İzlenen: %s (Kontrol: %d sn)\n", *targetPath, *intervalFlag)
	sendNotification("DiskBar Başlatıldı", fmt.Sprintf("Canlı Boş Alan: %s (%%% .1f Dolu)", formatBytes(stats.FreeBytes), stats.UsedPercent), false)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	ticker := time.NewTicker(time.Duration(*intervalFlag) * time.Second)
	defer ticker.Stop()

	var lastFree uint64 = stats.FreeBytes

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
					formatBytes(uint64(diff)),
					formatBytes(current.FreeBytes),
					current.UsedPercent,
				)

				if current.IsLow && !stats.IsLow {
					sendNotification("⚠️ Düşük Disk Alanı Uyarısı!", fmt.Sprintf("Diskte yalnızca %s boş alan kaldı!", formatBytes(current.FreeBytes)), true)
				}
				lastFree = current.FreeBytes
				stats = current
			}
		}
	}
}
