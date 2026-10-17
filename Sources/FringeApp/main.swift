import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// No Dock icon and no menu bar of its own: the notch panel is the whole interface.
app.setActivationPolicy(.accessory)
app.run()
