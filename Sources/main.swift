import AppKit

// פיץ׳ — מסך־המצב של כל המסופים הפתוחים.
// חלון אחד, פונט אחד, יישור לימין.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
