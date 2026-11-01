import Foundation

/// אינדקס־החיפוש: העתק דחוס של מה שנאמר בשיחות, בלי פלט־הכלים.
///
/// **למה זה קיים.** היומנים שוקלים ג'יגה־בתים, ותשעים אחוז מהנפח הוא תוצאות
/// של כלים — פלט שאיש אינו מחפש בו. סריקה ישירה עליהם ארכה כשלוש שניות בכל
/// שאילתה, בכל פעם מחדש. האינדקס מחזיק רק את מה שהמשתמש או המסוף אמרו, וזה
/// שני סדרי־גודל פחות.
///
/// **מצטבר, לא נבנה מחדש.** לכל יומן נשמר המיקום שממנו לא נקרא עדיין. שיחה
/// שגדלה בעשרה קילובייט מוסיפה עשרה קילובייט לאינדקס — לא מפענחת מגהבייטים
/// שכבר פוענחו. בלי זה, שיחה פעילה הייתה מייקרת כל חיפוש מחדש.
enum Index {

    static var dir: URL { Terminals.home.appendingPathComponent(".claude/peach-index") }
    private static var manifestURL: URL { dir.appendingPathComponent("manifest.json") }

    private static let lock = NSLock()
    private static func guarded<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private static var building = false
    private static var lastRefresh = Date.distantPast
    /// מצב הבנייה, להצגה: כמה יומנים נשארו.
    private(set) static var pending = 0

    /// מה נקרא עד כה מכל יומן: המיקום בבתים, וגודל־הקובץ שראינו.
    private struct Mark: Codable {
        var pos: Int
        var size: Int
        var project: String
    }

    private static func loadMarks() -> [String: Mark] {
        guard let data = try? Data(contentsOf: manifestURL),
              let marks = try? JSONDecoder().decode([String: Mark].self, from: data)
        else { return [:] }
        return marks
    }

    private static func saveMarks(_ marks: [String: Mark]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(marks) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    /// שם־הפרויקט של שיחה, לפי התיקייה שהיומן יושב בה.
    static func project(of sid: String) -> String {
        guarded { cachedProjects[sid] } ?? ""
    }
    private static var cachedProjects: [String: String] = [:]

    // MARK: - בנייה

    /// מרענן את האינדקס. בטוח לקרוא לו כמה שרוצים — הוא יוצא מיד אם רץ עכשיו
    /// או אם רוענן לפני רגע.
    static func refresh(force: Bool = false) {
        let go: Bool = guarded {
            if building { return false }
            if !force && Date().timeIntervalSince(lastRefresh) < 20 { return false }
            building = true
            lastRefresh = Date()
            return true
        }
        guard go else { return }
        defer { guarded { building = false; pending = 0 } }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var marks = loadMarks()
        var projects: [String: String] = [:]
        let logs = allLogs()
        var changed = 0

        guarded { pending = logs.count }
        for log in logs {
            let sid = (log.path as NSString).lastPathComponent
                .replacingOccurrences(of: ".jsonl", with: "")
            projects[sid] = log.project
            let mark = marks[sid] ?? Mark(pos: 0, size: 0, project: log.project)
            // קובץ שהתכווץ נכתב מחדש — האינדקס שלו כבר אינו תקף
            var start = mark.pos
            if log.size < mark.size { start = 0; try? FileManager.default.removeItem(at: shard(sid)) }
            if log.size == mark.size && start > 0 { guarded { pending -= 1 }; continue }

            let result = append(log: URL(fileURLWithPath: log.path), sid: sid, from: start)
            marks[sid] = Mark(pos: result, size: log.size, project: log.project)
            changed += 1
            guarded { pending -= 1 }
        }
        guarded { cachedProjects = projects }
        if changed > 0 { saveMarks(marks) }
    }

    /// קובצי־האינדקס, מהשיחה שנגעו בה לאחרונה לישנה ביותר.
    static func shardsByRecency() -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return items.filter { $0.pathExtension == "txt" }
            .map { url -> (String, Date) in
                let at = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return (url.path, at)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func shard(_ sid: String) -> URL {
        dir.appendingPathComponent(sid + ".txt")
    }

    /// קורא את היומן מהמיקום שנעצרנו בו, ומוסיף לאינדקס. מחזיר את המיקום החדש.
    private static func append(log: URL, sid: String, from start: Int) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return start }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(start))
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return start }

        // עוצרים בשורה השלמה האחרונה. שורה חתוכה תיקרא שוב בפעם הבאה,
        // ובלי זה היינו מפספסים אותה לתמיד.
        guard let lastBreak = data.lastIndex(of: 0x0A) else { return start }
        let usable = data[data.startIndex...lastBreak]

        var out = ""
        out.reserveCapacity(usable.count / 8)
        for line in usable.split(separator: 0x0A) {
            // בדיקת־בתים לפני פענוח: שורות פלט־כלים הן רוב הנפח, ואין בהן
            // מה לחפש. פענוח JSON שלהן היה עולה פי עשרה מכל השאר יחד.
            if contains(line, marker: toolMarker) { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = obj["message"] as? [String: Any] else { continue }
            if obj["isSidechain"] as? Bool == true { continue }
            let type = obj["type"] as? String
            guard type == "user" || type == "assistant" else { continue }

            var text = ""
            if let s = message["content"] as? String { text = s }
            else if let blocks = message["content"] as? [[String: Any]] {
                if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { continue }
                text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: " ")
            }
            // אותו ניקוי כמו בתצוגה: בלי זה האינדקס מתמלא בהודעות־מערכת,
            // וחיפוש מחזיר XML במקום מה שנאמר
            text = flatten(Transcript.withoutSystemBlocks(text))
            guard text.count > 1 else { continue }

            let stamp = Sessions.time(obj["timestamp"]).map { Int($0.timeIntervalSince1970) } ?? 0
            out += "\(stamp)\t\(type == "user" ? "y" : "c")\t\(text)\n"
        }

        if !out.isEmpty {
            let file = shard(sid)
            if let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(out.utf8))
                try? handle.close()
            } else {
                try? out.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        return start + usable.count
    }

    /// שורה באינדקס היא שורה אחת. ירידות־שורה ולשוניות בטקסט היו שוברות אותה.
    private static func flatten(_ text: String) -> String {
        var s = text
        for bad in ["\n", "\r", "\t"] { s = s.replacingOccurrences(of: bad, with: " ") }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static let toolMarker = Array("\"toolUseResult\"".utf8)

    /// סריקת־בתים על הפרוסה עצמה, בלי להעתיק אותה. שורת פלט־כלים יכולה
    /// לשקול מגהבייט, והעתקה שלה לכל בדיקה הייתה יקרה מהפענוח שרצינו לחסוך.
    private static func contains(_ slice: Data.SubSequence, marker: [UInt8]) -> Bool {
        let n = marker.count
        guard slice.count >= n else { return false }
        let first = marker[0]
        var i = slice.startIndex
        let last = slice.endIndex - n
        while i <= last {
            if slice[i] == first {
                var j = 1
                while j < n && slice[i + j] == marker[j] { j += 1 }
                if j == n { return true }
            }
            i += 1
        }
        return false
    }

    // MARK: - רשימת היומנים

    private struct Log { let path: String; let size: Int; let project: String }

    private static func allLogs() -> [Log] {
        let root = Terminals.home.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [Log] = []
        for folder in dirs {
            let project = projectName(folder.lastPathComponent)
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.fileSizeKey,
                                                         .contentModificationDateKey]) else { continue }
            for file in items where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey,
                                                                .contentModificationDateKey])
                out.append(Log(path: file.path, size: values?.fileSize ?? 0, project: project))
            }
        }
        return out
    }

    private static func projectName(_ folder: String) -> String {
        let parts = folder.split(separator: "-").filter { !$0.isEmpty }
        guard let last = parts.last else { return "" }
        return parts.count <= 2 ? Lang.t("בית", "home") : String(last)
    }
}
