import AppKit

// Manual bootstrap because this executable is packaged into an .app bundle at
// build time. We instantiate NSApplication explicitly and attach our delegate
// rather than relying on @main, so behavior is predictable across run modes
// (raw executable vs. bundled .app).

let app = NSApplication.shared

// .accessory = background utility with no Dock icon. Pairs with LSUIElement=1
// in Info.plist. Prevents stealing focus from other apps (Cursor, Chrome, ...).
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
