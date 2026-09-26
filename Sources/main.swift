import AppKit

let bundleId = Bundle.main.bundleIdentifier ?? "com.ugur.diskbar"
let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
if running.count > 1 {
    // Başka bir örnek zaten çalışıyorsa sessizce çık
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
