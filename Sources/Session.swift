import Foundation

/// מה שאפשר לדעת על השיחה שרצה במסוף, מתוך היומן שעל הדיסק.
struct SessionState {
    enum Mode: String { case working, waiting, quiet }
    let id: String
    let title: String
    /// תיקיית־העבודה המלאה
    let cwd: String
    /// שם התיקייה בלבד — זה מה שנקרא בעין
    let project: String
    let mode: Mode
    let lastEvent: Date
    let model: String
    /// טוקנים בחלון־ההקשר, כפי שדווחו בתשובה האחרונה
    let contextTokens: Int
    /// מה הכלי האחרון שהופעל, בעברית
    let activity: String
    /// המשפט האחרון שנאמר בשיחה
    let snippet: String
    /// כמה סוכני־רקע רצים עכשיו
    let agentsRunning: Int
}

/// קריאת יומני־השיחה. היומן הוא קובץ שורות־JSON, ואנחנו קוראים רק את הזנב שלו.
enum Sessions {

    private static let lock = NSLock()
    private static func guarded<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// שיחה שלא זזה אינה מפוענחת שוב. המפתח הוא גודל־הקובץ וזמן־השינוי יחד:
    /// עריכה שמשאירה את הגודל זהה עדיין מזיזה את הזמן.
    private static var cache: [String: (size: Int, modified: Date, state: SessionState)] = [:]
    /// מזהה־שיחה → מיקום היומן. חיפוש בכל תיקיות־הפרויקטים הוא יקר, ולכן נשמר.
    private static var located: [String: URL] = [:]

    static func state(id: String) -> SessionState? {
        guard !id.isEmpty, let url = transcriptURL(for: id) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let modified = attrs[.modificationDate] as? Date ?? .distantPast
        if let hit = guarded({ cache[id] }), hit.size == size, hit.modified == modified {
            return live(hit.state, url: url)
        }
        guard let fresh = read(url: url, id: id, modified: modified) else { return nil }
        guarded {
            cache[id] = (size, modified, fresh)
            if cache.count > 200 { cache.removeAll() }
        }
        return live(fresh, url: url)
    }

    /// ⛔ ‏**שיחה שסוכניה עובדים אינה ממתינה לך.**
    ///
    /// כשהעבודה עוברת לסוכני־רקע, היומן הראשי מפסיק לזוז — הסוכן כותב ליומן
    /// משלו. אחרי חצי דקה של שקט המסוף סומן "ממתין לך" בזמן שהוא באמצע
    /// עבודה, וזה בדיוק הרגע שבו הוא נראה פנוי ואינו.
    ///
    /// ⚠ ‏**וספירת־הסוכנים חייבת לחיות מחוץ למטמון.** המטמון ננעל על גודל
    /// היומן הראשי וזמן־השינוי שלו, ושניהם אינם זזים בזמן שהסוכנים עובדים —
    /// כלומר מצב שנקבע פעם אחת היה נשאר תקוע עד שהשיחה עצמה תזוז.
    private static func live(_ base: SessionState, url: URL) -> SessionState {
        let agents = runningAgents(next: url)
        // סוכן חי ⇒ השיחה עובדת, בלי קשר למה שנכתב לאחרונה ביומן הראשי
        if agents == 0 && agents == base.agentsRunning { return base }
        let mode: SessionState.Mode = agents > 0 ? .working : base.mode
        return SessionState(id: base.id, title: base.title, cwd: base.cwd, project: base.project,
                            mode: mode, lastEvent: base.lastEvent, model: base.model,
                            contextTokens: base.contextTokens,
                            activity: mode == .working && base.activity.isEmpty
                                ? (agents == 1 ? Lang.t("סוכן אחד עובד", "one agent working") : Lang.t("\(agents) סוכנים עובדים", "\(agents) agents working"))
                                : base.activity,
                            snippet: base.snippet, agentsRunning: agents)
    }

    /// היומן יושב תחת `~/.claude/projects/<תיקייה-מקודדת>/<מזהה>.jsonl`, והתיקייה
    /// נגזרת מתיקיית־העבודה — שאותה איננו יודעים מראש. לכן מחפשים לרוחב, פעם אחת.
    static func transcriptURL(for id: String) -> URL? {
        if let hit = guarded({ located[id] }), FileManager.default.fileExists(atPath: hit.path) {
            return hit
        }
        let root = Terminals.home.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return nil }
        for dir in dirs {
            let candidate = dir.appendingPathComponent(id + ".jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                guarded { located[id] = candidate }
                return candidate
            }
        }
        return nil
    }

    private static func read(url: URL, id: String, modified: Date) -> SessionState? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let tail: UInt64 = 300_000
        let clipped = size > tail
        try? handle.seek(toOffset: clipped ? size - tail : 0)
        let data = (try? handle.readToEnd()) ?? Data()

        // ⛔ ‏**החלון אינו הופך למחרוזות.** נמדד על 35 מסופים: בניית
        //    המחרוזות לכל הזנב, בכל פעימה, הייתה מהיקרים בהרכבת המדף.
        //    ⚠ והמטמון אינו עוזר — הוא ננעל על (גודל, זמן־שינוי), ובשיחה
        //    שרצה עכשיו שניהם זזים כל הזמן. ⇒ עוברים על גבולות־השורות
        //    ומפענחים רק את מה שאינו פלט־כלים.
        var lines: [Data.SubSequence] = []
        var at = data.startIndex
        var first = true
        while at < data.endIndex {
            var stop = at
            while stop < data.endIndex && data[stop] != 0x0A { stop += 1 }
            if !(first && clipped) && stop > at { lines.append(data[at..<stop]) }
            first = false
            at = stop < data.endIndex ? stop + 1 : stop
        }

        var lastEvent = modified
        var title = ""
        var custom = ""
        var cwd = ""
        var model = ""
        var context = 0
        var snippet = ""
        var tool = ""
        var lastKind = "?"

        for line in lines {
            // תוצאות־כלים הן רוב הנפח ואין בהן מה לקרוא — מדלגים לפני הפענוח
            if holds(line, toolMarker) { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if obj["isSidechain"] as? Bool == true { continue }
            if let t = obj["aiTitle"] as? String, !t.isEmpty { title = t }
            // A name given with /rename (or from Peach's list) beats the automatic one.
            if let t = obj["customTitle"] as? String, !t.isEmpty { custom = t }
            if let c = obj["cwd"] as? String { cwd = c }
            if let date = time(obj["timestamp"]) { lastEvent = date }

            // הודעה שנשלחה באמצע תור — ר׳ ההסבר ב-`Transcript`. היא הדבר
            // האחרון שנאמר, ולכן היא שורת־המשנה במדף.
            if obj["type"] as? String == "attachment",
               let att = obj["attachment"] as? [String: Any],
               att["type"] as? String == "queued_command",
               (att["origin"] as? [String: Any])?["kind"] as? String == "human",
               let said = att["prompt"] as? String {
                snippet = plain(said)
                continue
            }

            let type = obj["type"] as? String
            guard let message = obj["message"] as? [String: Any] else { continue }

            if type == "assistant" {
                if let m = message["model"] as? String { model = m }
                if let usage = message["usage"] as? [String: Any] {
                    let sum = (usage["input_tokens"] as? Int ?? 0)
                        + (usage["cache_read_input_tokens"] as? Int ?? 0)
                        + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                    if sum > 0 { context = sum }
                }
                let blocks = message["content"] as? [[String: Any]] ?? []
                let hasTool = blocks.contains { $0["type"] as? String == "tool_use" }
                if let name = blocks.last(where: { $0["type"] as? String == "tool_use" })?["name"] as? String {
                    tool = name
                }
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: " ")
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    snippet = plain(text)
                }
                lastKind = hasTool ? "tool" : (text.isEmpty ? lastKind : "answer")
            } else if type == "user" {
                let content = message["content"]
                if content is String { lastKind = "human" }
                else if let arr = content as? [[String: Any]] {
                    lastKind = arr.contains { $0["type"] as? String == "tool_result" } ? "result" : "human"
                }
            }
        }

        let age = Date().timeIntervalSince(lastEvent)
        let mode: SessionState.Mode
        // הודעת־טקסט אינה סוף התור: המסוף כותב משפט וממשיך לעבוד.
        // ‏"ממתין לך" נקבע רק אחרי חצי דקה של שקט אמיתי.
        if lastKind == "answer" {
            mode = age < 30 ? .working : (age > 6 * 3600 ? .quiet : .waiting)
        } else {
            mode = age < 150 ? .working : .quiet
        }

        return SessionState(id: id,
                            title: custom.isEmpty ? title : custom,
                            cwd: cwd,
                            project: cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent,
                            mode: mode,
                            lastEvent: lastEvent,
                            model: shortModel(model),
                            contextTokens: context,
                            activity: mode == .working ? hebrewTool(tool) : "",
                            snippet: String(snippet.prefix(160)),
                            agentsRunning: runningAgents(next: url))
    }

    private static let toolMarker = Array("\"toolUseResult\"".utf8)

    /// סריקת־בתים על הפרוסה עצמה, בלי להעתיק אותה למחרוזת.
    private static func holds(_ slice: Data.SubSequence, _ needle: [UInt8]) -> Bool {
        let n = needle.count
        guard slice.count >= n else { return false }
        let firstByte = needle[0]
        var i = slice.startIndex
        let last = slice.endIndex - n
        while i <= last {
            if slice[i] == firstByte {
                var j = 1
                while j < n && slice[i + j] == needle[j] { j += 1 }
                if j == n { return true }
            }
            i += 1
        }
        return false
    }

    /// סימני־המרקדאון הם רעש על לוח־מכשירים: כוכביות, גרשי־קוד וכותרות אינם
    /// אומרים דבר בשורה בת שורה אחת, והם שוברים את הרשת המונוספייסית.
    private static func plain(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\n", with: " ")
        // כוכבית בודדת וקו־תחתון חיים בתוך נתיבים ומזהים — הסרתם מדביקה מילים
        // זו לזו. מסירים רק את הסימנים שאין להם שימוש אחר בשורה קצרה.
        for marker in ["**", "###", "##", "`"] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// יומני סוכני־הרקע יושבים בתיקייה על שם השיחה, לצד היומן שלה.
    private static func runningAgents(next transcript: URL) -> Int {
        let dir = transcript.deletingPathExtension().appendingPathComponent("subagents")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        return items.filter { url in
            guard url.pathExtension == "jsonl" else { return false }
            let at = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return Date().timeIntervalSince(at) < 120
        }.count
    }

    static func hebrewTool(_ name: String) -> String {
        switch name {
        case "Bash": return Lang.t("מריץ פקודה", "running a command")
        case "Read": return Lang.t("קורא קובץ", "reading a file")
        case "Write": return Lang.t("כותב קובץ", "writing a file")
        case "Edit", "MultiEdit", "NotebookEdit": return Lang.t("עורך קוד", "editing code")
        case "Grep", "Glob": return Lang.t("מחפש בקוד", "searching the code")
        case "Task", "Agent": return Lang.t("מפעיל סוכן", "starting an agent")
        case "Workflow": return Lang.t("מריץ תזמור", "running a workflow")
        case "WebFetch", "WebSearch": return Lang.t("מחפש ברשת", "searching the web")
        case "TodoWrite", "TaskCreate", "TaskUpdate": return Lang.t("מעדכן משימות", "updating tasks")
        case "Skill": return Lang.t("טוען סקיל", "loading a skill")
        case "Artifact": return Lang.t("מפרסם תוצר", "publishing an artifact")
        case "": return Lang.t("חושב", "thinking")
        default:
            if name.hasPrefix("mcp__claude-in-chrome") { return Lang.t("עובד בדפדפן", "working in the browser") }
            if name.hasPrefix("mcp__computer-use") { return Lang.t("עובד על המסך", "working on screen") }
            if name.hasPrefix("mcp__") { return Lang.t("פונה למערכת חיצונית", "calling an outside system") }
            return name
        }
    }

    private static func shortModel(_ m: String) -> String {
        if m.contains("opus") { return Lang.t("אופוס", "Opus") }
        if m.contains("sonnet") { return Lang.t("סונט", "Sonnet") }
        if m.contains("haiku") { return Lang.t("הייקו", "Haiku") }
        if m.contains("fable") { return Lang.t("פייבל", "Fable") }
        return ""
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func time(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }
}
