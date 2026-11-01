import Foundation

/// שמות שהמשתמש נתן למסופים.
///
/// ⛔ ‏**שם שאינו נשמר אינו שם.** הכותרת שהמודל נותן לשיחה משתנה מעצמה
///    לאורך היום, ולכן שם שהמשתמש בחר חייב לגבור עליה ולשרוד סגירה ופתיחה.
///    ⇒ קובץ אחד, ליד כל השאר, ומפתח לפי מזהה־השיחה.
enum Names {

    private static var file: URL {
        Terminals.home.appendingPathComponent(".claude/peach-names.json")
    }

    private static let lock = NSLock()
    private static var cache: [String: String]?

    private static func all() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let data = (try? Data(contentsOf: file)) ?? Data()
        let loaded = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] ?? [:]
        cache = loaded
        return loaded
    }

    static func name(for sid: String) -> String {
        guard !sid.isEmpty else { return "" }
        return all()[sid] ?? ""
    }

    // MARK: - Renaming a live conversation

    /// Reported 3.10: renaming from Peach "did not really rename". Appending
    /// the name to the log is read by /resume, but a running console keeps its
    /// name in memory — the prompt box, the window title and its own record
    /// stayed old. Measured the same day on a throwaway session: sending
    /// `/rename <name>` updates all three, and writes the log line itself.
    ///
    /// A busy conversation is never interrupted: the rename waits here until
    /// Claude Code's own record says "idle", and is confirmed by that record
    /// showing the new name. A conversation that closes first gets the name
    /// in its log instead.
    /// Kept in a file, so a rename still waiting survives a restart of Peach.
    private static var waitingFile: URL { Terminals.home.appendingPathComponent(".claude/peach-renames.json") }
    private static var waiting: [String: String] {
        get { ((try? JSONSerialization.jsonObject(with: Data(contentsOf: waitingFile))) as? [String: String]) ?? [:] }
        set {
            if let data = try? JSONSerialization.data(withJSONObject: newValue, options: [.prettyPrinted]) {
                try? data.write(to: waitingFile, options: .atomic)
            }
        }
    }

    static func rename(_ name: String, sid: String, live: Bool) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty, !clean.isEmpty else { return }
        if live {
            // The window shows the new name at once; the conversation's own
            // name follows as soon as it is idle.
            if let term = Terminals.open().first(where: { $0.sessionID == sid }) {
                Terminals.setWindowTitle(clean, tty: term.tty)
            }
            lock.lock(); waiting[sid] = String(clean.prefix(80)); lock.unlock()
        } else { setReal(clean, for: sid) }
    }

    /// Called from the scan, off the main thread.
    static func tick(_ terms: [Terminal]) {
        lock.lock(); let todo = waiting; lock.unlock()
        for (sid, name) in todo {
            guard let term = terms.first(where: { $0.sessionID == sid }) else {
                setReal(name, for: sid)
                lock.lock(); waiting.removeValue(forKey: sid); lock.unlock()
                continue
            }
            guard Terminals.status(pid: term.pid) == "idle" else { continue }
            _ = Terminals.send("/rename " + name, tty: term.tty)
            if recordName(pid: term.pid) == name {
                lock.lock(); waiting.removeValue(forKey: sid); lock.unlock()
            }
        }
    }

    private static func recordName(pid: Int) -> String {
        let url = Terminals.home.appendingPathComponent(".claude/sessions/\(pid).json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return obj["name"] as? String ?? ""
    }

    /// Writes the name into the conversation itself, the same record Claude
    /// Code writes on /rename, so it shows in the /resume picker and in every
    /// other place — not only in Peach.
    ///
    /// ⛔ The transcript may be live. The line is appended with O_APPEND, so
    ///    the kernel places it after whatever Claude Code wrote last; a seek
    ///    followed by a write could land on top of a line written in between.
    static func setReal(_ name: String, for sid: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty, !clean.isEmpty, let url = Sessions.transcriptURL(for: sid) else { return }
        let entry: [String: Any] = ["type": "custom-title", "customTitle": String(clean.prefix(80)), "sessionId": sid]
        guard let json = try? JSONSerialization.data(withJSONObject: entry) else { return }
        var bytes = Data()
        // Start on a fresh line if the file does not end with one.
        if let h = try? FileHandle(forReadingFrom: url) {
            let size = (try? h.seekToEnd()) ?? 0
            if size > 0 { try? h.seek(toOffset: size - 1)
                if (try? h.read(upToCount: 1)) != Data([0x0A]) { bytes.append(0x0A) } }
            try? h.close()
        }
        bytes.append(json); bytes.append(0x0A)
        let fd = open(url.path, O_WRONLY | O_APPEND)
        guard fd >= 0 else { return }
        _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }

    /// שם ריק מוחק את הרישום ומחזיר את הכותרת האוטומטית.
    static func set(_ name: String, for sid: String) {
        guard !sid.isEmpty else { return }
        var next = all()
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { next.removeValue(forKey: sid) } else { next[sid] = String(clean.prefix(80)) }
        lock.lock(); cache = next; lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted]) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
