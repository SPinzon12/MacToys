import AppKit

// Entry point: menu-bar-only accessory app (no Dock icon, no main window).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = app.setActivationPolicy(.accessory)
app.run()
