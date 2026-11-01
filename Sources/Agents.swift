import Foundation

/// סוכן־רקע אחד, כפי שאפשר לראות אותו מהדיסק.
struct Agent {
    let id: String
    /// מזהה השיחה שהפעילה אותו
    let sid: String
    let chat: String
    let kind: String
    let task: String
    let model: String
    let started: Date
    let updated: Date
    let running: Bool
    let bytes: Int
    /// עומק־קינון: סוכן שהפעיל סוכן
    let depth: Int
    /// מה הסוכן עושה **עכשיו**, בעברית — הכלי האחרון שהפעיל
    let doing: String
    /// המשפט האחרון שאמר
    let say: String
    /// טוקנים בחלון־ההקשר שלו, כפי שדווחו בתשובה האחרונה
    let context: Int
    /// כמה פעולות עשה עד כה
    let steps: Int
}

/// איסוף סוכני־הרקע של השיחות. הם היחידים שעובדים כשהמסוף שקט, ולכן
/// חיווי "דומם" בלי לראות אותם הוא חיווי משקר.
enum Agents {

    /// סוכן נחשב רץ אם היומן שלו זז בשתי הדקות האחרונות.
    private static let liveWindow: TimeInterval = 120
    /// כמה סוכנים אחרונים מוצגים.
    private static let ceiling = 60

    /// ⛔ הסדר כאן הוא כל ההבדל, ולכן אסור להפוך אותו בחזרה.
    ///
    /// ‏**קודם בודקים אם יש סוכנים בכלל, ורק אז מחשבים כותרת.** הכותרת מגיעה
    /// מ-`Sessions.state`, שקורא ומפענח 300 קילובייט מזנב־היומן; קריאה
    /// לתיקייה שאינה קיימת עולה כלום.
    ///
    /// ‏**נמדד 25.8.2026 על המכונה של המשתמש:** ‏106 שיחות רשומות, ומתוכן
    /// ל-**31 בלבד** יש תיקיית־סוכנים. הסדר ההפוך פיענח 300 קילובייט עבור
    /// כל 106 — כ-**21 מגה בכל רענון**, שרובו המוחלט עבור שיחות שאין להן
    /// ולו סוכן אחד. ⚠ ומטמון־המצב ננעל על (גודל, זמן־שינוי), כלומר בשיחות
    /// שרצות עכשיו הוא **לעולם אינו נפגע** והעבודה חוזרת כל פעימה.
    /// ⇒ זה מה שהפך את פאנל־הסוכנים מ"תוספת" ל"האפליקציה לא נפתחת".
    static func all(for terminals: [Terminal]) -> [Agent] {
        var out: [Agent] = []
        for term in terminals where !term.sessionID.isEmpty {
            guard let log = Sessions.transcriptURL(for: term.sessionID) else { continue }
            let folder = log.deletingPathExtension().appendingPathComponent("subagents")
            // אין תיקייה ⇒ אין סוכנים ⇒ אין סיבה לפענח מגהבייט בשביל כותרת
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
                  names.contains(where: { $0.hasSuffix(".jsonl") }) else { continue }
            let title = Sessions.state(id: term.sessionID)?.title ?? term.windowTitle
            out.append(contentsOf: inFolder(folder,
                                            sid: term.sessionID,
                                            chat: title.isEmpty ? Lang.t("מסוף ", "terminal ") + term.slot : title))
        }
        return Array(out.sorted { $0.updated > $1.updated }.prefix(ceiling))
    }

    private static func inFolder(_ dir: URL, sid: String, chat: String) -> [Agent] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey,
                                                  .creationDateKey, .fileSizeKey]) else { return [] }
        return items.filter { $0.pathExtension == "jsonl" }.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey,
                                                           .creationDateKey, .fileSizeKey])
            let updated = values?.contentModificationDate ?? .distantPast
            let meta = metadata(url)
            // ⇒ מה שהסוכן עושה עכשיו נקרא רק ממי שרץ. סוכן שסיים אינו עושה
            //   דבר, ופענוח הזנב שלו הוא עבודה על מסך שאיש לא מסתכל בו.
            let alive = Date().timeIntervalSince(updated) < liveWindow
            let pulse = alive ? beat(url) : (doing: "", say: "", context: 0, steps: 0)
            return Agent(id: url.deletingPathExtension().lastPathComponent
                            .replacingOccurrences(of: "agent-", with: ""),
                         sid: sid,
                         chat: chat,
                         kind: meta.kind,
                         task: meta.task,
                         model: meta.model,
                         started: values?.creationDate ?? updated,
                         updated: updated,
                         running: Date().timeIntervalSince(updated) < liveWindow,
                         bytes: values?.fileSize ?? 0,
                         depth: meta.depth,
                         doing: pulse.doing,
                         say: pulse.say,
                         context: pulse.context,
                         steps: pulse.steps)
        }
    }

    /// ‏**מה קורה בסוכן ברגע זה** — נקרא מזנב היומן שלו, כמו בשיחה עצמה.
    ///
    /// ⛔ ‏**רק זנב.** יומן של סוכן שרץ שעה שוקל עשרות מגה־בתים, וכאן צריך
    ///    את חמש השורות האחרונות בלבד. ⚠ ותוצאות־כלים מדולגות לפני הפענוח,
    ///    כמו בכל שאר הקריאות כאן — הן רוב הנפח ואין בהן מה להציג.
    private static func beat(_ log: URL)
        -> (doing: String, say: String, context: Int, steps: Int) {
        guard let handle = try? FileHandle(forReadingFrom: log) else {
            return ("", "", 0, 0)
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let tail: UInt64 = 400_000
        try? handle.seek(toOffset: size > tail ? size - tail : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        var rows = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        if size > tail && !rows.isEmpty { rows.removeFirst() }

        var doing = ""
        var say = ""
        var context = 0
        var steps = 0
        for row in rows {
            if row.contains("\"toolUseResult\"") { continue }
            guard let d = row.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any] else { continue }
            if let usage = message["usage"] as? [String: Any] {
                let sum = (usage["input_tokens"] as? Int ?? 0)
                    + (usage["cache_read_input_tokens"] as? Int ?? 0)
                    + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                if sum > 0 { context = sum }
            }
            let blocks = message["content"] as? [[String: Any]] ?? []
            for block in blocks where block["type"] as? String == "tool_use" {
                doing = Sessions.hebrewTool(block["name"] as? String ?? "")
                steps += 1
            }
            let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                say = String(text.replacingOccurrences(of: "\n", with: " ").prefix(150))
                // תשובה שאין אחריה כלי היא סוכן שחושב או מסכם
                doing = ""
            }
        }
        if doing.isEmpty && say.isEmpty { doing = Lang.t("חושב", "thinking") }
        return (doing, say, context, steps)
    }

    /// הסוכנים ה**רצים** של שיחה אחת. זה מה שמוצג בתוך מסך־השיחה.
    static func live(sessionID: String) -> [Agent] {
        guard !sessionID.isEmpty, let log = Sessions.transcriptURL(for: sessionID) else { return [] }
        let folder = log.deletingPathExtension().appendingPathComponent("subagents")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              names.contains(where: { $0.hasSuffix(".jsonl") }) else { return [] }
        return inFolder(folder, sid: sessionID, chat: "")
            .filter { $0.running }
            .sorted { $0.started < $1.started }
    }

    /// קובץ־המטא שלצד יומן־הסוכן. אינו משתנה אחרי היצירה, ולכן נשמר לתמיד.
    private static let lock = NSLock()
    private static var cache: [String: (kind: String, task: String, model: String, depth: Int)] = [:]

    private static func metadata(_ log: URL)
        -> (kind: String, task: String, model: String, depth: Int) {
        lock.lock()
        let hit = cache[log.path]
        lock.unlock()
        if let hit { return hit }

        var value: (kind: String, task: String, model: String, depth: Int) = (Lang.t("סוכן", "agent"), "", "", 0)
        let metaURL = log.deletingPathExtension().appendingPathExtension("meta.json")
        if let data = try? Data(contentsOf: metaURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            value = (kind: obj["agentType"] as? String ?? Lang.t("סוכן", "agent"),
                     task: obj["description"] as? String ?? "",
                     model: model(obj["model"] as? String ?? ""),
                     depth: obj["spawnDepth"] as? Int ?? 0)
        }
        lock.lock(); cache[log.path] = value; lock.unlock()
        return value
    }

    private static func model(_ m: String) -> String {
        if m.contains("opus") { return Lang.t("אופוס", "Opus") }
        if m.contains("sonnet") { return Lang.t("סונט", "Sonnet") }
        if m.contains("haiku") { return Lang.t("הייקו", "Haiku") }
        if m.contains("fable") { return Lang.t("פייבל", "Fable") }
        return m
    }
}
