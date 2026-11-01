import Foundation

/// מה שנקרא, ובאיזה מצב: האם הגענו לתחילת השיחה או שיש עוד מעליה.
struct Reading {
    let lines: [Line]
    let atStart: Bool
}

/// שורה אחת בשיחה, כפי שהיא מוצגת.
struct Line {
    /// ‏"you" המשתמש · "claude" המסוף · "tool" פעולה שנעשתה
    let role: String
    let text: String
    /// בשורת־פעולה: מה שהפעולה קיבלה — פקודה, נתיב, כתובת.
    /// שדה נפרד ולא צירוף לטקסט, כי הוא נקרא משמאל לימין גם כשיש בו עברית.
    let arg: String
    let time: Date
}

/// קריאת יומן־שיחה לתצוגה.
///
/// ברירת־המחדל היא הזנב, אבל **ההתחלה נגישה**: הדף מבקש עוד, והחלון גדל.
/// ⛔ קודם היה כאן "איש גם לא גולל לשם" — וזה היה שגוי. שיחה ארוכה נפתחה
///    באמצע, בלי שום דרך להגיע לראשה. נמדד מול צילום־מסך של המשתמש, 28.8.
enum Transcript {

    /// כמה **תורות־שיחה** אחרונות מוצגות — הודעות של המשתמש ושל המסוף.
    ///
    /// ⛔ ‏**נספרות הודעות, לא שורות.** קודם נספרו שורות, ובשיחה שמריצה מאה
    /// פקודות ברצף כל החלון התמלא בשורות־פעולה — מסך שלם בלי משפט אחד.
    static let turns = 24
    /// תקרת־ביטחון על סך־הכול, כדי ששיחה עמוסת־כלים לא תצייר אלפי שורות.
    static let ceiling = 500

    private static let lock = NSLock()
    private static func guarded<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
    /// יומן שלא זז אינו מפוענח שוב. בשיחה עמוסה הקובץ משתנה כל שנייה, ולכן
    /// המטמון הזה הוא ההבדל בין מסך חלק לבין פענוח מגהבייטים בכל פעימה.
    private static var cache: [String: (size: Int, modified: Date, result: Reading)] = [:]
    /// ⛔ **סולם־הזנב עלה כסף בכל סריקה.** ‏1 ואז 4 ואז 12 מגה־בתים זה
    ///    17 מגה שנקראים ומפוענחים כדי להציג עשרים שורות — **כל 1.5 שניות**.
    ///    ⇒ הזנב שהספיק נזכר, והקריאה הבאה מתחילה ממנו.
    private static var learned: [String: UInt64] = [:]

    /// כמה בתים מסוף היומן נקראים. תוצאות־כלים תופסות נפח עצום, ולכן זנב קבוע
    /// מכסה לפעמים שתי הודעות בלבד. מרחיבים עד שיש מספיק להציג.
    private static let tails: [UInt64] = [1_000_000, 4_000_000, 12_000_000]

    /// כמה שורות־תצוגה מותר לצייר. גדל עם החלון, אחרת בקשה ל"עוד" הייתה
    /// מוסיפה הודעות ומיד חותכת אותן בתקרה.
    private static func ceiling(for want: Int) -> Int { max(600, want * 14) }

    static func lines(sessionID: String) -> [Line] {
        read(sessionID: sessionID, want: turns).lines
    }

    /// ‏`want` — כמה **תורות־שיחה** להציג. גדל כשהדף מבקש להראות מוקדם יותר.
    static func read(sessionID: String, want: Int) -> Reading {
        guard let url = Sessions.transcriptURL(for: sessionID) else {
            return Reading(lines: [], atStart: true)
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return Reading(lines: [], atStart: true)
        }
        let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let modified = attrs[.modificationDate] as? Date ?? .distantPast
        let key = sessionID + "|" + String(want)
        if let hit = guarded({ cache[key] }), hit.size == fileSize, hit.modified == modified {
            return hit.result
        }

        // חלון גדול מבקש זנב גדול, ומרגע שרוצים הכול קוראים את כל הקובץ
        var ladder: [UInt64] = [1_000_000, 4_000_000, 12_000_000, 48_000_000]
        if want >= huge { ladder = [UInt64(max(fileSize, 1))] }
        if let known = guarded({ learned[sessionID] }) {
            ladder = ladder.filter { $0 >= known }
            if ladder.isEmpty { ladder = [UInt64(max(fileSize, 1))] }
        }

        var result = Reading(lines: [], atStart: true)
        for tail in ladder {
            result = read(url: url, tail: tail, want: want)
            let spoken = result.lines.filter { $0.role != "tool" }.count
            let enough = spoken >= want || result.atStart || UInt64(fileSize) <= tail
            if enough {
                guarded { learned[sessionID] = tail }
                break
            }
        }
        guarded {
            cache[key] = (fileSize, modified, result)
            if cache.count > 40 { cache.removeAll() }
        }
        return result
    }

    /// מעל זה — קוראים את היומן כולו.
    static let huge = 100_000

    /// The smallest window, on the same ladder as "show earlier", whose first
    /// line is at or before `epoch` — so a search hit at that time is loaded.
    static func want(reaching epoch: Double, sessionID: String) -> Int {
        var want = turns
        guard epoch > 0 else { return want }
        for w in [turns, 80, 250, 800, huge] {
            want = w
            let r = read(sessionID: sessionID, want: w)
            let first = r.lines.first?.time.timeIntervalSince1970 ?? 0
            if r.atStart || (first > 0 && first <= epoch - 1) { break }
        }
        return want
    }

    /// ⛔ **קוראים מהסוף אחורה ועוצרים.** קודם פוענח כל החלון ואז נחתך —
    ///    כלומר אלפי שורות פוענחו כדי להציג עשרים. עכשיו מפענחים רק עד
    ///    שיש מספיק, וזה ההבדל בין מעבר מיידי לשיחה לבין המתנה.
    private static func read(url: URL, tail: UInt64, want: Int) -> Reading {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Reading(lines: [], atStart: true)
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let clipped = size > tail
        try? handle.seek(toOffset: clipped ? size - tail : 0)
        let data = (try? handle.readToEnd()) ?? Data()

        var reversed: [Line] = []
        var spoken = 0
        var stoppedEarly = false
        let cap = ceiling(for: want)

        // ⛔ **החלון אינו הופך למחרוזות.** קודם נבנו כאן ארבעים אלף מחרוזות
        //    כדי לפענח מאה מהן; נמדד על יומן בן 34 מגה: 730 מילישניות לפתיחת
        //    שיחה, וזה כל ההבדל בין מעבר מיידי לבין המתנה מורגשת.
        //    ⇒ עוברים על גבולות־השורות מהסוף, ומפענחים רק את מה שנקרא.
        var end = data.endIndex
        while end > data.startIndex {
            if spoken >= want || reversed.count >= cap { stoppedEarly = true; break }
            // דילוג על ירידת־השורה שסוגרת את השורה הקודמת
            if data[end - 1] == 0x0A { end -= 1; continue }
            var start = end
            while start > data.startIndex && data[start - 1] != 0x0A { start -= 1 }
            // השורה הראשונה בחלון חתוכה באמצע ואינה JSON תקין
            if clipped && start == data.startIndex { break }
            let out = parse(row: data[start..<end])
            // נאסף הפוך, ולכן שורות של אותה הודעה נכנסות הפוך ומתיישרות בסוף
            reversed.append(contentsOf: out.reversed())
            spoken += out.filter { $0.role != "tool" }.count
            end = start
        }

        var lines = Array(reversed.reversed())
        if lines.count > cap { lines = Array(lines.suffix(cap)); stoppedEarly = true }
        return Reading(lines: collapse(lines), atStart: !stoppedEarly && !clipped)
    }

    /// שורת־יומן אחת → שורות־התצוגה שהיא מולידה. אפס, אחת, או הודעה
    /// ואחריה שורות־פעולה.
    ///
    /// ⛔ הופרדה מלולאת־הקריאה **בכוונה**: כשהיא הייתה בתוכה, כל `continue`
    ///    דילג גם על צבירת התוצאה, ושורה תקינה שנפלה על תנאי־סינון מאוחר
    ///    הייתה נעלמת בשקט.
    private static func parse(row: Data.SubSequence) -> [Line] {
        // ⛔ תוצאות־כלים הן רוב הנפח המוחלט ואינן יכולות להפוך לשורת־תצוגה:
        //    הודעת־משתמש שכולה `tool_result` מסוננת ממילא כמה שורות מכאן.
        //    ⇒ מדלגים **לפני** הפענוח, בדיוק כמו `Sessions.read`.
        //
        //    נמדד על שיחה בת 40 מגה: בחלון של 12 מגה יש 11.4 מגה טקסט,
        //    שמתוכם **447 קילובייט בלבד** הם הודעות אמיתיות — 96% מהפענוח
        //    היה זבל.
        if holds(row, marker: toolMarker) { return [] }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(row)) as? [String: Any] else { return [] }
        if obj["isSidechain"] as? Bool == true { return [] }
        if obj["isMeta"] as? Bool == true { return [] }
        let stamp = Sessions.time(obj["timestamp"]) ?? Date.distantPast

        // ⛔ ‏**הודעה שהמשתמש שולח בזמן שהמסוף עובד אינה הודעת־משתמש ביומן.**
        //    היא נכנסת לתור ונרשמת כרשומת־צירוף מסוג `queued_command`,
        //    בלי שדה `message` בכלל — ולכן הפענוח דילג עליה, והיא הופיעה
        //    במסוף אך נעלמה מפיץ׳. נמדד מול צילום־מסך של המשתמש, 27.8.
        if obj["type"] as? String == "attachment",
           let att = obj["attachment"] as? [String: Any],
           att["type"] as? String == "queued_command",
           (att["origin"] as? [String: Any])?["kind"] as? String == "human",
           let said = att["prompt"] as? String,
           let clean = human(said) {
            return [Line(role: "you", text: clean, arg: "", time: stamp)]
        }

        guard let message = obj["message"] as? [String: Any] else { return [] }
        let type = obj["type"] as? String
        var out: [Line] = []

        if type == "user" {
            if let text = message["content"] as? String {
                if let clean = human(text) { out.append(Line(role: "you", text: clean, arg: "", time: stamp)) }
            } else if let blocks = message["content"] as? [[String: Any]] {
                // הודעת־משתמש שכולה תוצאת־כלי אינה דבר שהמשתמש כתב
                if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return [] }
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: "\n")
                if let clean = human(text) { out.append(Line(role: "you", text: clean, arg: "", time: stamp)) }
            }
        } else if type == "assistant" {
            let blocks = message["content"] as? [[String: Any]] ?? []
            let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out.append(Line(role: "claude", text: text, arg: "", time: stamp)) }
            for block in blocks where block["type"] as? String == "tool_use" {
                let name = block["name"] as? String ?? ""
                out.append(Line(role: "tool",
                                text: Sessions.hebrewTool(name),
                                arg: toolArg(block["input"]),
                                time: stamp))
            }
        }
        return out
    }

    private static let toolMarker = Array("\"toolUseResult\"".utf8)

    /// סריקת־בתים על הפרוסה עצמה, בלי להעתיק אותה. שורת פלט־כלים יכולה
    /// לשקול מגהבייט, והעתקה שלה לכל בדיקה יקרה מהפענוח שרצינו לחסוך.
    private static func holds(_ slice: Data.SubSequence, marker: [UInt8]) -> Bool {
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

    /// אותה פעולה ברצף אינה שתי ידיעות. שורות־פעולה זהות עוקבות נדחסות לאחת.
    private static func collapse(_ lines: [Line]) -> [Line] {
        var out: [Line] = []
        for line in lines {
            if line.role == "tool", let last = out.last, last.role == "tool",
               last.text == line.text, last.arg == line.arg {
                continue
            }
            out.append(line)
        }
        return out
    }

    /// בלוקים שהמערכת מזריקה לתוך הודעת־המשתמש. הם אינם דבר שהמשתמש כתב.
    ///
    /// ‏**זו הייתה תקלה נראית:** הודעת־מערכת על סיום סוכן הוצגה בשיחה
    /// כאילו המשתמש אמר אותה, וההודעה האמיתית שלו נדחקה מהמסך.
    private static let systemTags = [
        "system-reminder", "task-notification", "command-name", "command-message",
        "command-args", "local-command-stdout", "local-command-stderr",
        "user-prompt-submit-hook", "budget-warning"
    ]

    /// קודי־מסוף שנדבקים להודעה: רצפי־בריחה, ודיווחי־עכבר מהצורה
    /// ‏`<65;62;30M`. הם נכנסים ליומן כשהמסוף שולח קוד־שליטה בזמן הקלדה,
    /// והם מופיעים על המסך כג׳יבריש בתוך משפט של המשתמש.
    static func withoutTerminalCodes(_ text: String) -> String {
        var out = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            // רצף־בריחה: מ-ESC ועד האות שסוגרת אותו
            if ch == "\u{1B}" {
                i += 1
                while i < chars.count, !("a"..."z").contains(chars[i]),
                      !("A"..."Z").contains(chars[i]) { i += 1 }
                i += 1
                continue
            }
            // דיווח־עכבר: "<" ואז ספרות ונקודות־פסיק ואז M או m
            if ch == "<" {
                var j = i + 1
                var digits = 0
                while j < chars.count, chars[j].isNumber || chars[j] == ";" {
                    if chars[j].isNumber { digits += 1 }
                    j += 1
                }
                if digits >= 3, j < chars.count, chars[j] == "M" || chars[j] == "m" {
                    i = j + 1
                    continue
                }
            }
            out.append(ch)
            i += 1
        }
        return out
    }

    /// טקסט בלי בלוקי־המערכת. משמש גם את האינדקס, כדי שחיפוש לא יחזיר
    /// הודעות שאיש לא כתב.
    static func withoutSystemBlocks(_ text: String) -> String {
        var s = text
        for tag in systemTags {
            let open = "<" + tag + ">"
            let close = "</" + tag + ">"
            // מסירים כל מופע, לא רק אחד בתחילת ההודעה — הזרקה יכולה לשבת
            // גם באמצע ואחרי הטקסט האנושי
            while let from = s.range(of: open) {
                if let to = s.range(of: close, range: from.upperBound..<s.endIndex) {
                    s.removeSubrange(from.lowerBound..<to.upperBound)
                } else {
                    // בלי סוגר — הכל מכאן והלאה הוא של המערכת
                    s.removeSubrange(from.lowerBound..<s.endIndex)
                }
            }
        }
        return withoutTerminalCodes(s)
    }

    /// טקסט של המשתמש אחרי הניקוי. ריק ⇐ אין מה להציג.
    static func human(_ text: String) -> String? {
        let clean = withoutSystemBlocks(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// מה שהפעולה קיבלה — הערך המשמעותי הראשון מתוך הקלט שלה.
    private static func toolArg(_ input: Any?) -> String {
        guard let dict = input as? [String: Any] else { return "" }
        for key in ["file_path", "path", "pattern", "command", "url", "skill", "description", "prompt"] {
            if let value = dict[key] as? String, !value.isEmpty {
                let one = value.replacingOccurrences(of: "\n", with: " ")
                return String(one.prefix(60))
            }
        }
        return ""
    }
}
