import AppKit
import MiracleShotUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "MS"
let menu = NSMenu()
menu.addItem(withTitle: "Quit Miracle Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
statusItem.menu = menu
app.run()
