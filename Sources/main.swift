import AppKit
import Foundation

ProcessInfo.processInfo.processName = "ReadItSoonCompanion"

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
NSApp.setActivationPolicy(.accessory)
app.run()
