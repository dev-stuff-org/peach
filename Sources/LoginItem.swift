import Foundation

/// הפעלה בהתחברות, דרך סוכן־הפעלה של המערכת.
///
/// לא נעשה כאן שימוש בשירות־ההרשמה החדש של אפל: הוא קיים רק ממערכת 13,
/// והרצפה כאן היא 12. קובץ־סוכן פשוט עובד בשתיהן, ואפשר לראות ולמחוק אותו ביד.
enum LoginItem {

    private static let label = "org.hameretz2.peach.login"

    private static var plist: URL {
        Terminals.home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// הנתיב של האפליקציה הרצה — לא נתיב קשיח, כדי שהתקנה למקום אחר לא תישבר.
    private static var executable: String {
        Bundle.main.executablePath ?? ""
    }

    static var enabled: Bool {
        get { FileManager.default.fileExists(atPath: plist.path) }
        set { newValue ? install() : remove() }
    }

    private static func install() {
        guard !executable.isEmpty else { return }
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array><string>\(executable)</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><false/>
        </dict>
        </plist>
        """
        let dir = plist.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? body.write(to: plist, atomically: true, encoding: .utf8)
        _ = Terminals.shell("/bin/launchctl", ["load", "-w", plist.path])
    }

    private static func remove() {
        _ = Terminals.shell("/bin/launchctl", ["unload", "-w", plist.path])
        try? FileManager.default.removeItem(at: plist)
    }
}
