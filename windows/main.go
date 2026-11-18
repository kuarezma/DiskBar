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
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/kuarezma/DiskBar/internal/common"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	advapi32 = syscall.NewLazyDLL("advapi32.dll")

	procGetDiskFreeSpaceExW     = kernel32.NewProc("GetDiskFreeSpaceExW")
	procGetLogicalDriveStringsW = kernel32.NewProc("GetLogicalDriveStringsW")
	procGetDriveTypeW           = kernel32.NewProc("GetDriveTypeW")
	procCreateMutexW            = kernel32.NewProc("CreateMutexW")
	procShell_NotifyIconW       = shell32.NewProc("Shell_NotifyIconW")
	procShellExecuteW           = shell32.NewProc("ShellExecuteW")
	procRegisterClassExW        = user32.NewProc("RegisterClassExW")
	procCreateWindowExW         = user32.NewProc("CreateWindowExW")
	procDefWindowProcW          = user32.NewProc("DefWindowProcW")
	procPostQuitMessage         = user32.NewProc("PostQuitMessage")
	procGetMessageW             = user32.NewProc("GetMessageW")
	procTranslateMessage        = user32.NewProc("TranslateMessage")
	procDispatchMessageW        = user32.NewProc("DispatchMessageW")
	procCreatePopupMenu         = user32.NewProc("CreatePopupMenu")
	procDestroyMenu             = user32.NewProc("DestroyMenu")
	procAppendMenuW             = user32.NewProc("AppendMenuW")
	procTrackPopupMenu          = user32.NewProc("TrackPopupMenu")
	procSetForegroundWindow     = user32.NewProc("SetForegroundWindow")
	procGetCursorPos            = user32.NewProc("GetCursorPos")
	procLoadIconW               = user32.NewProc("LoadIconW")
	procRegOpenKeyExW           = advapi32.NewProc("RegOpenKeyExW")
	procRegQueryValueExW        = advapi32.NewProc("RegQueryValueExW")
	procRegSetValueExW          = advapi32.NewProc("RegSetValueExW")
	procRegDeleteValueW         = advapi32.NewProc("RegDeleteValueW")
	procRegCloseKey             = advapi32.NewProc("RegCloseKey")
)

const (
	WM_USER      = 0x0400
	WM_TRAYICON  = WM_USER + 1
	WM_RBUTTONUP = 0x0205
	WM_LBUTTONUP = 0x0202
	WM_COMMAND   = 0x0111
	WM_DESTROY   = 0x0002

	NIM_ADD      = 0x00000000
	NIM_MODIFY   = 0x00000001
	NIM_DELETE   = 0x00000002
	NIF_MESSAGE  = 0x00000001
	NIF_ICON     = 0x00000002
	NIF_TIP      = 0x00000004
	NIF_INFO     = 0x00000010
	NIIF_INFO    = 0x00000001
	NIIF_WARNING = 0x00000002

	MF_STRING    = 0x00000000
	MF_SEPARATOR = 0x00000800
	MF_GRAYED    = 0x00000001
	MF_CHECKED   = 0x00000008

	TPM_RIGHTBUTTON = 0x0002
	TPM_BOTTOMALIGN = 0x0020

	IDI_APPLICATION = 32512

	DRIVE_REMOVABLE = 2
	DRIVE_FIXED     = 3

	ERROR_ALREADY_EXISTS = 183

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
	IsLow       bool
	IsCritical  bool
}

const currentVersion = "1.1.0"

var (
	stateMu             sync.Mutex
	currentHWnd         uintptr
	nid                 NOTIFYICONDATAW
	stats               DiskStats
	allDrives           []DiskStats
	lastTip             string
	latestVersion       string
	lastNotifiedVersion string
	isUpdateAvailable   bool
	lastAlertLevel      int // 0=normal, 1=low, 2=critical
)

func systemDriveRoot() string {
	drive := strings.TrimSpace(os.Getenv("SystemDrive"))
	if drive == "" {
		return "C:\\"
	}
	if !strings.HasSuffix(drive, "\\") {
		drive += "\\"
	}
	return drive
}

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
	var used uint64
	if totalBytes > freeBytes {
		used = totalBytes - freeBytes
	}
	percent := 0.0
	if totalBytes > 0 {
		percent = (float64(used) / float64(totalBytes)) * 100.0
	}
	isCrit := totalBytes > 0 && (freeBytes < common.CriticalSpaceThresholdBytes || percent > 95.0)
	isLow := totalBytes > 0 && (freeBytes < common.LowSpaceThresholdBytes || percent > 90.0)

	return DiskStats{
		DriveLetter: strings.TrimSuffix(drive, "\\"),
		TotalBytes:  totalBytes,
		FreeBytes:   freeBytes,
		UsedBytes:   used,
		UsedPercent: percent,
		IsLow:       isLow,
		IsCritical:  isCrit,
	}, nil
}

func listLogicalDrives() []DiskStats {
	buf := make([]uint16, 256)
	n, _, _ := procGetLogicalDriveStringsW.Call(uintptr(len(buf)-1), uintptr(unsafe.Pointer(&buf[0])))
	if n == 0 || int(n) >= len(buf) {
		if s, err := getDiskStats(systemDriveRoot()); err == nil {
			return []DiskStats{s}
		}
		return nil
	}

	var drives []DiskStats
	start := 0
	for i := 0; i < int(n); i++ {
		if buf[i] == 0 {
			if i > start {
				root := syscall.UTF16ToString(buf[start:i])
				dt, _, _ := procGetDriveTypeW.Call(uintptr(unsafe.Pointer(utf16Ptr(root))))
				if dt == DRIVE_FIXED || dt == DRIVE_REMOVABLE {
					if s, err := getDiskStats(root); err == nil && s.TotalBytes > 0 {
						drives = append(drives, s)
					}
				}
			}
			start = i + 1
		}
	}
	return drives
}

func utf16Ptr(s string) *uint16 {
	p, _ := syscall.UTF16PtrFromString(s)
	return p
}

func copyUTF16Fixed(dst []uint16, s string) {
	for i := range dst {
		dst[i] = 0
	}
	src := syscall.StringToUTF16(s)
	if len(src) >= len(dst) {
		copy(dst[:len(dst)-1], src[:len(dst)-1])
		dst[len(dst)-1] = 0
		return
	}
	copy(dst, src)
}

func showWindowsNotification(title, message string, warning bool) {
	stateMu.Lock()
	defer stateMu.Unlock()

	copyUTF16Fixed(nid.SzInfoTitle[:], title)
	copyUTF16Fixed(nid.SzInfo[:], message)
	nid.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_INFO
	if warning {
		nid.DwInfoFlags = NIIF_WARNING
	} else {
		nid.DwInfoFlags = NIIF_INFO
	}
	procShell_NotifyIconW.Call(NIM_MODIFY, uintptr(unsafe.Pointer(&nid)))

	// NIF_INFO bayrağını hemen temizle ki sonraki tooltip güncellemelerinde balon tekrar etmesin
	nid.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
	copyUTF16Fixed(nid.SzInfoTitle[:], "")
	copyUTF16Fixed(nid.SzInfo[:], "")
}

func checkUpdates(manual bool) {
	client := http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", "https://api.github.com/repos/kuarezma/DiskBar/releases/latest", nil)
	if err != nil {
		return
	}
	req.Header.Set("User-Agent", fmt.Sprintf("DiskBar/%s (Windows)", currentVersion))
	req.Header.Set("Accept", "application/vnd.github+json")

	resp, err := client.Do(req)
	if err != nil {
		if manual {
			showWindowsNotification("Bağlantı Hatası", "GitHub sunucusuna ulaşılamadı.", true)
		}
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if manual {
			showWindowsNotification("Güncelleme Kontrolü", fmt.Sprintf("Sunucu HTTP %d yanıtı döndürdü.", resp.StatusCode), true)
		}
		return
	}

	var data struct {
		TagName string `json:"tag_name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil || data.TagName == "" {
		return
	}

	if common.IsVersionHigher(data.TagName, currentVersion) {
		stateMu.Lock()
		isUpdateAvailable = true
		latestVersion = data.TagName
		shouldNotify := manual || lastNotifiedVersion != data.TagName
		if shouldNotify {
			lastNotifiedVersion = data.TagName
		}
		stateMu.Unlock()

		if shouldNotify {
			showWindowsNotification(
				"DiskBar Güncellemesi Mevcut!",
				fmt.Sprintf("Yeni sürüm: %s hazır. Menüden tek tıkla güncelleyebilirsiniz.", data.TagName),
				false,
			)
		}
	} else if manual {
		showWindowsNotification(
			"DiskBar Güncel",
			fmt.Sprintf("Zaten en son sürümü (v%s) kullanıyorsunuz.", currentVersion),
			false,
		)
	}
}

func performOneClickUpdate() {
	showWindowsNotification("DiskBar Güncelleniyor...", "En son sürüm indiriliyor...", false)
	exePath, err := os.Executable()
	if err != nil {
		openURL("https://github.com/kuarezma/DiskBar/releases/latest")
		return
	}

	batchScript := fmt.Sprintf(`@echo off
setlocal
timeout /t 1 /nobreak >nul
curl -fsSL -A "DiskBar/%s" https://github.com/kuarezma/DiskBar/releases/latest/download/DiskBar.exe -o "%s.new"
if errorlevel 1 (
    del /f /q "%s.new" 2>nul
    start "" "%s"
    del "%%~f0"
    exit /b 1
)
for %%%%A in ("%s.new") do if %%%%~zA LSS 100000 (
    del /f /q "%s.new" 2>nul
    start "" "%s"
    del "%%~f0"
    exit /b 1
)
move /y "%s.new" "%s" >nul
start "" "%s"
del "%%~f0"
`, currentVersion, exePath, exePath, exePath, exePath, exePath, exePath, exePath, exePath, exePath)

	tmpBatch := filepath.Join(os.TempDir(), "diskbar_update.bat")
	if err := os.WriteFile(tmpBatch, []byte(batchScript), 0755); err != nil {
		openURL("https://github.com/kuarezma/DiskBar/releases/latest")
		return
	}

	cmd := exec.Command("cmd.exe", "/c", tmpBatch)
	if err := cmd.Start(); err != nil {
		openURL("https://github.com/kuarezma/DiskBar/releases/latest")
		return
	}

	stateMu.Lock()
	procShell_NotifyIconW.Call(NIM_DELETE, uintptr(unsafe.Pointer(&nid)))
	stateMu.Unlock()
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
		switch wParam & 0xFFFF {
		case CMD_UPDATE:
			go performOneClickUpdate()
		case CMD_REFRESH:
			updateStats(false)
			go checkUpdates(true)
		case CMD_SETTINGS:
			openURL("ms-settings:storagesense")
		case CMD_DISKMGMT:
			openURL("diskmgmt.msc")
		case CMD_AUTOSTART:
			toggleAutostart()
		case CMD_EXIT:
			stateMu.Lock()
			procShell_NotifyIconW.Call(NIM_DELETE, uintptr(unsafe.Pointer(&nid)))
			stateMu.Unlock()
			procPostQuitMessage.Call(0)
		}
		return 0
	case WM_DESTROY:
		stateMu.Lock()
		procShell_NotifyIconW.Call(NIM_DELETE, uintptr(unsafe.Pointer(&nid)))
		stateMu.Unlock()
		procPostQuitMessage.Call(0)
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(hWnd, uintptr(msg), wParam, lParam)
	return r
}

func openURL(url string) {
	procShellExecuteW.Call(0, uintptr(unsafe.Pointer(utf16Ptr("open"))), uintptr(unsafe.Pointer(utf16Ptr(url))), 0, 0, 1)
}

func updateStats(initial bool) {
	root := systemDriveRoot()
	s, err := getDiskStats(root)
	if err != nil {
		return
	}
	drives := listLogicalDrives()

	tip := fmt.Sprintf("DiskBar - %s %s Boş (%%%.1f Dolu)", s.DriveLetter, common.FormatBytes(s.FreeBytes), s.UsedPercent)

	alertLevel := 0
	if s.IsCritical {
		alertLevel = 2
	} else if s.IsLow {
		alertLevel = 1
	}

	var notifyTitle, notifyMsg string

	stateMu.Lock()
	stats = s
	allDrives = drives
	if initial {
		lastAlertLevel = alertLevel
	} else if alertLevel > lastAlertLevel {
		if alertLevel == 2 {
			notifyTitle = fmt.Sprintf("Kritik Disk Alanı! (%s)", s.DriveLetter)
			notifyMsg = fmt.Sprintf("Yalnızca %s boş alan kaldı (%%%.1f dolu)!", common.FormatBytes(s.FreeBytes), s.UsedPercent)
		} else if alertLevel == 1 {
			notifyTitle = fmt.Sprintf("Düşük Disk Alanı (%s)", s.DriveLetter)
			notifyMsg = fmt.Sprintf("Boş alan %s seviyesine düştü (%%%.1f dolu).", common.FormatBytes(s.FreeBytes), s.UsedPercent)
		}
	}
	lastAlertLevel = alertLevel

	if tip != lastTip {
		lastTip = tip
		copyUTF16Fixed(nid.SzTip[:], tip)
		nid.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
		if !initial {
			procShell_NotifyIconW.Call(NIM_MODIFY, uintptr(unsafe.Pointer(&nid)))
		}
	}
	stateMu.Unlock()

	if notifyTitle != "" {
		showWindowsNotification(notifyTitle, notifyMsg, true)
	}
}

func showContextMenu(hWnd uintptr) {
	updateStats(false)

	hMenu, _, _ := procCreatePopupMenu.Call()
	defer procDestroyMenu.Call(hMenu)

	stateMu.Lock()
	curStats := stats
	drivesCopy := append([]DiskStats(nil), allDrives...)
	updAvail := isUpdateAvailable
	updVer := latestVersion
	stateMu.Unlock()

	// 1. Yeni sürüm varsa en üstte tek tıkla güncelleme butonu
	if updAvail {
		updateText := fmt.Sprintf("✨ Yeni Sürüm (%s) — Tek Tıkla Güncelle", updVer)
		procAppendMenuW.Call(hMenu, MF_STRING, CMD_UPDATE, uintptr(unsafe.Pointer(utf16Ptr(updateText))))
		procAppendMenuW.Call(hMenu, MF_SEPARATOR, 0, 0)
	}

	// 2. Başlık Kartı (Ana sürücü)
	headerText := fmt.Sprintf("Disk (%s) — %s Boş", curStats.DriveLetter, common.FormatBytes(curStats.FreeBytes))
	procAppendMenuW.Call(hMenu, MF_STRING|MF_GRAYED, 0, uintptr(unsafe.Pointer(utf16Ptr(headerText))))

	usedText := fmt.Sprintf("   Dolu: %s / %s (%%%.1f)", common.FormatBytes(curStats.UsedBytes), common.FormatBytes(curStats.TotalBytes), curStats.UsedPercent)
	procAppendMenuW.Call(hMenu, MF_STRING|MF_GRAYED, 0, uintptr(unsafe.Pointer(utf16Ptr(usedText))))

	// Ek sürücüler varsa göster
	for _, d := range drivesCopy {
		if strings.EqualFold(d.DriveLetter, curStats.DriveLetter) {
			continue
		}
		extraText := fmt.Sprintf("   %s — %s Boş / %s (%%%.1f)", d.DriveLetter, common.FormatBytes(d.FreeBytes), common.FormatBytes(d.TotalBytes), d.UsedPercent)
		procAppendMenuW.Call(hMenu, MF_STRING|MF_GRAYED, 0, uintptr(unsafe.Pointer(utf16Ptr(extraText))))
	}

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

	verText := fmt.Sprintf("DiskBar v%s", currentVersion)
	procAppendMenuW.Call(hMenu, MF_STRING|MF_GRAYED, 0, uintptr(unsafe.Pointer(utf16Ptr(verText))))

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
	if r != 0 {
		return false
	}
	defer procRegCloseKey.Call(hKey)

	valName := utf16Ptr("DiskBar")
	var dataType uint32
	var dataSize uint32
	r2, _, _ := procRegQueryValueExW.Call(
		hKey,
		uintptr(unsafe.Pointer(valName)),
		0,
		uintptr(unsafe.Pointer(&dataType)),
		0,
		uintptr(unsafe.Pointer(&dataSize)),
	)
	return r2 == 0
}

func toggleAutostart() {
	var hKey uintptr
	keyPath := utf16Ptr("Software\\Microsoft\\Windows\\CurrentVersion\\Run")
	r, _, _ := procRegOpenKeyExW.Call(HKEY_CURRENT_USER, uintptr(unsafe.Pointer(keyPath)), 0, KEY_SET_VALUE|KEY_QUERY_VALUE, uintptr(unsafe.Pointer(&hKey)))
	if r != 0 {
		return
	}
	defer procRegCloseKey.Call(hKey)

	valName := utf16Ptr("DiskBar")
	if isAutostartEnabled() {
		procRegDeleteValueW.Call(hKey, uintptr(unsafe.Pointer(valName)))
		return
	}

	exePath, err := os.Executable()
	if err != nil {
		return
	}
	quoted := fmt.Sprintf("\"%s\"", exePath)
	utf16Val, err := syscall.UTF16FromString(quoted)
	if err != nil {
		return
	}
	procRegSetValueExW.Call(
		hKey,
		uintptr(unsafe.Pointer(valName)),
		0,
		REG_SZ,
		uintptr(unsafe.Pointer(&utf16Val[0])),
		uintptr(len(utf16Val)*2),
	)
}

func ensureSingleInstance() bool {
	mutexName := utf16Ptr("Global\\DiskBarSingleInstanceMutex")
	handle, _, lastErr := procCreateMutexW.Call(0, 0, uintptr(unsafe.Pointer(mutexName)))
	if handle == 0 {
		return true
	}
	if errno, ok := lastErr.(syscall.Errno); ok && errno == ERROR_ALREADY_EXISTS {
		return false
	}
	return true
}

func main() {
	if !ensureSingleInstance() {
		return
	}

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

	stateMu.Lock()
	nid.CbSize = uint32(unsafe.Sizeof(nid))
	nid.HWnd = hWnd
	nid.UID = 1
	nid.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
	nid.UCallbackMessage = WM_TRAYICON
	nid.HIcon = hIcon
	stateMu.Unlock()

	updateStats(true)
	stateMu.Lock()
	procShell_NotifyIconW.Call(NIM_ADD, uintptr(unsafe.Pointer(&nid)))
	stateMu.Unlock()

	// Açılışta ve her 2 saatte bir güncelleme kontrolü
	go func() {
		time.Sleep(3 * time.Second)
		checkUpdates(false)
		ticker := time.NewTicker(2 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			checkUpdates(false)
		}
	}()

	// Arka plan disk kontrolü (15 saniyede bir, yalnızca değişimde UI günceller)
	go func() {
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			updateStats(false)
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
