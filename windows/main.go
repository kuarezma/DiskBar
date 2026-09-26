//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	advapi32 = syscall.NewLazyDLL("advapi32.dll")

	procGetDiskFreeSpaceExW     = kernel32.NewProc("GetDiskFreeSpaceExW")
	procGetLogicalDriveStringsW = kernel32.NewProc("GetLogicalDriveStringsW")
	procShell_NotifyIconW       = shell32.NewProc("Shell_NotifyIconW")
	procShellExecuteW           = shell32.NewProc("ShellExecuteW")
	procRegisterClassExW        = user32.NewProc("RegisterClassExW")
	procCreateWindowExW         = user32.NewProc("CreateWindowExW")
	procDefWindowProcW          = user32.NewProc("DefWindowProcW")
	procDestroyWindow           = user32.NewProc("DestroyWindow")
	procPostQuitMessage         = user32.NewProc("PostQuitMessage")
	procGetMessageW             = user32.NewProc("GetMessageW")
	procTranslateMessage        = user32.NewProc("TranslateMessage")
	procDispatchMessageW        = user32.NewProc("DispatchMessageW")
	procCreatePopupMenu         = user32.NewProc("CreatePopupMenu")
	procAppendMenuW             = user32.NewProc("AppendMenuW")
	procTrackPopupMenu          = user32.NewProc("TrackPopupMenu")
	procSetForegroundWindow     = user32.NewProc("SetForegroundWindow")
	procGetCursorPos            = user32.NewProc("GetCursorPos")
	procLoadIconW               = user32.NewProc("LoadIconW")
	procRegOpenKeyExW           = advapi32.NewProc("RegOpenKeyExW")
	procRegSetValueExW          = advapi32.NewProc("RegSetValueExW")
	procRegDeleteValueW         = advapi32.NewProc("RegDeleteValueW")
	procRegCloseKey             = advapi32.NewProc("RegCloseKey")
)

const (
	WM_USER         = 0x0400
	WM_TRAYICON     = WM_USER + 1
	WM_RBUTTONUP    = 0x0205
	WM_LBUTTONUP    = 0x0202
	WM_COMMAND      = 0x0111
	WM_DESTROY      = 0x0002

	NIM_ADD         = 0x00000000
	NIM_MODIFY      = 0x00000001
	NIM_DELETE      = 0x00000002
	NIF_MESSAGE     = 0x00000001
	NIF_ICON        = 0x00000002
	NIF_TIP         = 0x00000004
	NIF_INFO        = 0x00000010
	NIIF_INFO       = 0x00000001

	MF_STRING       = 0x00000000
	MF_SEPARATOR    = 0x00000800
	MF_GRAYED       = 0x00000001
	MF_CHECKED      = 0x00000008

	TPM_RIGHTBUTTON = 0x0002
	TPM_BOTTOMALIGN = 0x0020

	IDI_APPLICATION = 32512

	HKEY_CURRENT_USER = 0x80000001
	KEY_SET_VALUE     = 0x0002
	KEY_QUERY_VALUE   = 0x0001
	REG_SZ            = 1

	CMD_UPDATE    = 2000
	CMD_REFRESH   = 2001
	CMD_SETTINGS  = 2002
	CMD_DISKMGMT  = 2003
	CMD_AUTOSTART = 2004
	CMD_EXIT      = 2005
)

type NOTIFYICONDATAW struct {
	CbSize           uint32
	HWnd             uintptr
	UID              uint32
	UFlags           uint32
	UCallbackMessage uint32
	HIcon            uintptr
	SzTip            [128]uint16
	DwState          uint32
	DwStateMask      uint32
	SzInfo           [256]uint16
	UVersion         uint32
	SzInfoTitle      [64]uint16
	DwInfoFlags      uint32
	GuidItem         [16]byte
	HBalloonIcon     uintptr
}

type POINT struct {
	X int32
	Y int32
}

type WNDCLASSEXW struct {
	CbSize        uint32
	Style         uint32
	LpfnWndProc   uintptr
	CbClsExtra    int32
	CbWndExtra    int32
	HInstance     uintptr
	HIcon         uintptr
	HCursor       uintptr
	HbrBackground uintptr
	LpszMenuName  *uint16
	LpszClassName *uint16
	HIconSm       uintptr
}

type MSG struct {
	HWnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      POINT
}

type DiskStats struct {
	DriveLetter string
	TotalBytes  uint64
	FreeBytes   uint64
	UsedBytes   uint64
	UsedPercent float64
}

var (
	currentHWnd       uintptr
	nid               NOTIFYICONDATAW
	stats             DiskStats
	currentVersion    = "1.0.0"
	latestVersion     = ""
	isUpdateAvailable = false
)

func getDiskStats(drive string) (DiskStats, error) {
	drivePtr, err := syscall.UTF16PtrFromString(drive)
	if err != nil {
		return DiskStats{}, err
	}
	var freeBytes, totalBytes, totalFree uint64
	r1, _, errSys := procGetDiskFreeSpaceExW.Call(
		uintptr(unsafe.Pointer(drivePtr)),
		uintptr(unsafe.Pointer(&freeBytes)),
		uintptr(unsafe.Pointer(&totalBytes)),
		uintptr(unsafe.Pointer(&totalFree)),
	)
	if r1 == 0 {
		return DiskStats{}, errSys
	}
	used := totalBytes - freeBytes
	percent := 0.0
	if totalBytes > 0 {
		percent = (float64(used) / float64(totalBytes)) * 100.0
	}
	return DiskStats{
		DriveLetter: drive,
		TotalBytes:  totalBytes,
		FreeBytes:   freeBytes,
		UsedBytes:   used,
		UsedPercent: percent,
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

func utf16Ptr(s string) *uint16 {
	p, _ := syscall.UTF16PtrFromString(s)
	return p
}

func showWindowsNotification(title, message string) {
	copy(nid.SzInfoTitle[:], syscall.StringToUTF16(title))
	copy(nid.SzInfo[:], syscall.StringToUTF16(message))
	nid.UFlags |= NIF_INFO
	nid.DwInfoFlags = NIIF_INFO
	procShell_NotifyIconW.Call(NIM_MODIFY, uintptr(unsafe.Pointer(&nid)))
}

func checkUpdates() {
	client := http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get("https://api.github.com/repos/kuarezma/DiskBar/releases/latest")
	if err != nil {
		return
	}
	defer resp.Body.Close()

	var data struct {
		TagName string `json:"tag_name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err == nil && data.TagName != "" {
		cleanRemote := strings.TrimPrefix(strings.TrimPrefix(data.TagName, "v"), "V")
		cleanCurrent := strings.TrimPrefix(strings.TrimPrefix(currentVersion, "v"), "V")
		if cleanRemote > cleanCurrent {
			isUpdateAvailable = true
			latestVersion = data.TagName
			showWindowsNotification(
				"🚀 DiskBar Güncellemesi Mevcut!",
				fmt.Sprintf("Yeni sürüm: %s hazır. Menüden tek tıkla güncelleyebilirsiniz.", data.TagName),
			)
		}
	}
}

func performOneClickUpdate() {
	showWindowsNotification("DiskBar Güncelleniyor...", "En son sürüm indiriliyor...")
	exePath, err := os.Executable()
	if err != nil {
		openURL("https://github.com/kuarezma/DiskBar/releases/latest")
		return
	}

	batchScript := fmt.Sprintf(`@echo off
timeout /t 1 /nobreak >nul
curl -fsSL https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar.exe -o "%s.new"
if exist "%s.new" (
    move /y "%s.new" "%s"
    start "" "%s"
)
del "%%~f0"
`, exePath, exePath, exePath, exePath, exePath)

	tmpBatch := filepath.Join(os.TempDir(), "diskbar_update.bat")
	_ = os.WriteFile(tmpBatch, []byte(batchScript), 0755)

	cmd := exec.Command("cmd.exe", "/c", tmpBatch)
	_ = cmd.Start()
	os.Exit(0)
}

func wndProc(hWnd uintptr, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_TRAYICON:
		if lParam == WM_RBUTTONUP || lParam == WM_LBUTTONUP {
			showContextMenu(hWnd)
		}
		return 0
	case WM_COMMAND:
		switch wParam {
		case CMD_UPDATE:
			performOneClickUpdate()
		case CMD_REFRESH:
			updateStats()
			checkUpdates()
		case CMD_SETTINGS:
			openURL("ms-settings:storagesense")
		case CMD_DISKMGMT:
			openURL("diskmgmt.msc")
		case CMD_AUTOSTART:
			toggleAutostart()
		case CMD_EXIT:
			procShell_NotifyIconW.Call(NIM_DELETE, uintptr(unsafe.Pointer(&nid)))
			procPostQuitMessage.Call(0)
		}
		return 0
	case WM_DESTROY:
		procShell_NotifyIconW.Call(NIM_DELETE, uintptr(unsafe.Pointer(&nid)))
		procPostQuitMessage.Call(0)
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(hWnd, uintptr(msg), wParam, lParam)
	return r
}

func openURL(url string) {
	procShellExecuteW.Call(0, uintptr(unsafe.Pointer(utf16Ptr("open"))), uintptr(unsafe.Pointer(utf16Ptr(url))), 0, 0, 1)
}

func updateStats() {
	s, err := getDiskStats("C:\\")
	if err == nil {
		stats = s
		tip := fmt.Sprintf("DiskBar - C: %s Boş (%%%.1f Dolu)", formatBytes(s.FreeBytes), s.UsedPercent)
		copy(nid.SzTip[:], syscall.StringToUTF16(tip))
		procShell_NotifyIconW.Call(NIM_MODIFY, uintptr(unsafe.Pointer(&nid)))
	}
}

func showContextMenu(hWnd uintptr) {
	hMenu, _, _ := procCreatePopupMenu.Call()

	// 1. Yeni sürüm varsa en üstte tek tıkla güncelleme butonu
	if isUpdateAvailable {
		updateText := fmt.Sprintf("✨ Yeni Sürüm (%s) — Tek Tıkla Güncelle", latestVersion)
		procAppendMenuW.Call(hMenu, MF_STRING, CMD_UPDATE, uintptr(unsafe.Pointer(utf16Ptr(updateText))))
		procAppendMenuW.Call(hMenu, MF_SEPARATOR, 0, 0)
	}

	// 2. Başlık Kartı
	headerText := fmt.Sprintf("🖴 Disk (C:) — %s Boş", formatBytes(stats.FreeBytes))
	procAppendMenuW.Call(hMenu, MF_STRING|MF_GRAYED, 0, uintptr(unsafe.Pointer(utf16Ptr(headerText))))

	usedText := fmt.Sprintf("   Dolu: %s / %s (%%%.1f)", formatBytes(stats.UsedBytes), formatBytes(stats.TotalBytes), stats.UsedPercent)
	procAppendMenuW.Call(hMenu, MF_STRING|MF_GRAYED, 0, uintptr(unsafe.Pointer(utf16Ptr(usedText))))

	procAppendMenuW.Call(hMenu, MF_SEPARATOR, 0, 0)

	// 3. İşlemler
	procAppendMenuW.Call(hMenu, MF_STRING, CMD_REFRESH, uintptr(unsafe.Pointer(utf16Ptr("⚡ Şimdi Yenile & Güncelleme Kontrolü"))))
	procAppendMenuW.Call(hMenu, MF_STRING, CMD_SETTINGS, uintptr(unsafe.Pointer(utf16Ptr("⚙️ Windows Depolama Ayarları..."))))
	procAppendMenuW.Call(hMenu, MF_STRING, CMD_DISKMGMT, uintptr(unsafe.Pointer(utf16Ptr("🛠️ Disk Yönetimi (diskmgmt)..."))))

	procAppendMenuW.Call(hMenu, MF_SEPARATOR, 0, 0)

	// 4. Otomatik Başlatma
	autostartFlags := uintptr(MF_STRING)
	if isAutostartEnabled() {
		autostartFlags |= MF_CHECKED
	}
	procAppendMenuW.Call(hMenu, autostartFlags, CMD_AUTOSTART, uintptr(unsafe.Pointer(utf16Ptr("🚀 Windows Açılışında Başlat"))))

	procAppendMenuW.Call(hMenu, MF_SEPARATOR, 0, 0)

	// 5. Çıkış
	procAppendMenuW.Call(hMenu, MF_STRING, CMD_EXIT, uintptr(unsafe.Pointer(utf16Ptr("❌ DiskBar'dan Çık"))))

	var pt POINT
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	procSetForegroundWindow.Call(hWnd)
	procTrackPopupMenu.Call(hMenu, TPM_RIGHTBUTTON|TPM_BOTTOMALIGN, uintptr(pt.X), uintptr(pt.Y), 0, hWnd, 0)
}

func isAutostartEnabled() bool {
	var hKey uintptr
	keyPath := utf16Ptr("Software\\Microsoft\\Windows\\CurrentVersion\\Run")
	r, _, _ := procRegOpenKeyExW.Call(HKEY_CURRENT_USER, uintptr(unsafe.Pointer(keyPath)), 0, KEY_QUERY_VALUE, uintptr(unsafe.Pointer(&hKey)))
	if r == 0 {
		defer procRegCloseKey.Call(hKey)
		return true
	}
	return false
}

func toggleAutostart() {
	var hKey uintptr
	keyPath := utf16Ptr("Software\\Microsoft\\Windows\\CurrentVersion\\Run")
	r, _, _ := procRegOpenKeyExW.Call(HKEY_CURRENT_USER, uintptr(unsafe.Pointer(keyPath)), 0, KEY_SET_VALUE, uintptr(unsafe.Pointer(&hKey)))
	if r == 0 {
		defer procRegCloseKey.Call(hKey)
		valName := utf16Ptr("DiskBar")
		exePath, _ := os.Executable()
		exePtr := utf16Ptr(exePath)
		procRegSetValueExW.Call(hKey, uintptr(unsafe.Pointer(valName)), 0, REG_SZ, uintptr(unsafe.Pointer(exePtr)), uintptr(len(exePath)*2+2))
	}
}

func main() {
	runtime.LockOSThread()

	className := utf16Ptr("DiskBarWindowClass")
	hIcon, _, _ := procLoadIconW.Call(0, IDI_APPLICATION)

	var wc WNDCLASSEXW
	wc.CbSize = uint32(unsafe.Sizeof(wc))
	wc.LpfnWndProc = syscall.NewCallback(wndProc)
	wc.LpszClassName = className
	wc.HIcon = hIcon
	wc.HIconSm = hIcon

	procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))

	hWnd, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(utf16Ptr("DiskBar"))),
		0,
		0, 0, 0, 0,
		0, 0, 0, 0,
	)
	currentHWnd = hWnd

	nid.CbSize = uint32(unsafe.Sizeof(nid))
	nid.HWnd = hWnd
	nid.UID = 1
	nid.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
	nid.UCallbackMessage = WM_TRAYICON
	nid.HIcon = hIcon

	updateStats()
	procShell_NotifyIconW.Call(NIM_ADD, uintptr(unsafe.Pointer(&nid)))

	// Açılışta ve her 2 saatte bir güncelleme kontrolü
	go func() {
		time.Sleep(3 * time.Second)
		checkUpdates()
		for {
			time.Sleep(2 * time.Hour)
			checkUpdates()
		}
	}()

	// Canlı arka plan disk kontrolü (Her 2 saniyede bir)
	go func() {
		for {
			time.Sleep(2 * time.Second)
			updateStats()
		}
	}()

	var msg MSG
	for {
		r, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if r == 0 || int32(r) == -1 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&msg)))
	}
}
