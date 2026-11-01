import Foundation

/// מונה־צריכה: כמה נשרף בכל שיחה, ומה חלקה בסך־הכול.
///
/// ⛔ ‏**אין כאן דולרים.** המשתמש במנוי, ומחיר־הרשימה אינו מה שהוא משלם —
///    מספר כזה נראה מדיד והוא בדיוני. המשקל הפנימי (מחיר־רשימה) נשאר
///    **רק** ככלי־השוואה בין דגמים: פלט של אופוס אינו שווה לפלט של הייקו,
///    ובלי משקל כלשהו "מי צרך יותר" הוא שאלה שאין לה תשובה. מה שמוצג הוא
///    **חלק־מהצריכה באחוזים** וטוקנים — שניהם נמדדים ואינם מתחזים לכסף.
///
/// **למה מצטבר ולא נסרק מחדש.** היומנים שוקלים כמעט שלושה ג'יגה־בתים. סריקה
/// מלאה בכל פתיחה הייתה לוקחת דקה, ולכן לכל יומן נשמר המיקום שממנו לא נקרא
/// עדיין — בדיוק כמו באינדקס־החיפוש.
///
/// ⛔ **שורת־שימוש אחת מופיעה כמה פעמים.** תשובה אחת של המודל נכתבת ליומן
///    בכמה שורות — אחת לכל בלוק־תוכן — וכולן נושאות את **אותו** מונה־שימוש.
///    נמדד על יומן אחד: ‏733 שורות עם שימוש מול 489 תשובות אמיתיות, כלומר
///    ניפוח של פי 1.5. לכן סופרים לפי `message.id` ולא לפי שורה.
///    ⚠ החזרות תמיד רצופות (נמדד: אפס מזהים שנחתכים באמצע), ולכן מספיק לזכור
///      את המזהה האחרון — גם מעבר לגבול של קריאה מצטברת.
enum Spend {

    // MARK: - מבנה

    struct Counters: Codable {
        var input = 0
        var output = 0
        /// כתיבה למטמון בתוקף חמש דקות
        var write5 = 0
        /// כתיבה למטמון בתוקף שעה
        var write1h = 0
        var read = 0
        var calls = 0

        mutating func add(_ other: Counters) {
            input += other.input; output += other.output
            write5 += other.write5; write1h += other.write1h
            read += other.read; calls += other.calls
        }
    }

    struct SessionSpend: Codable {
        var project = ""
        /// סך־הכול מאז ומתמיד, לפי דגם
        var models: [String: Counters] = [:]
        /// לפי יום ולפי דגם — נגזם לארבעה־עשר ימים
        var daily: [String: [String: Counters]] = [:]
        /// חותמת התנועה האחרונה
        var last: Double = 0
    }

    private struct Mark: Codable {
        var pos: Int
        var size: Int
        /// מזהה־התשובה האחרון שנספר, כדי שהחזרות לא ייספרו שוב אחרי גבול־קריאה
        var lastMsg: String
    }

    private struct Store: Codable {
        var marks: [String: Mark] = [:]
        var sessions: [String: SessionSpend] = [:]
        /// סדרה גלובלית לפי שעה — ‏"yyyy-MM-dd HH" → דגם → מונים.
        /// ⇒ חלון־הפעילות של חמש שעות והשוואה בין שבועות אינם ניתנים לחישוב
        ///   מדליים יומיים. שלושה שבועות אחורה מספיקים לשניהם.
        var hours: [String: [String: Counters]] = [:]
    }

    // MARK: - מחירון

    /// דולרים למיליון טוקנים: קלט, פלט.
    /// כתיבה למטמון היא פי 1.25 מהקלט לחמש דקות ופי 2 לשעה; קריאה היא עשירית.
    private static func rate(_ model: String) -> (input: Double, output: Double) {
        let m = model.lowercased()
        if m.contains("fable") || m.contains("mythos") { return (10, 50) }
        if m.contains("opus")   { return (5, 25) }
        if m.contains("sonnet") { return m.contains("4-6") ? (3, 15) : (2, 10) }
        if m.contains("haiku")  { return (1, 5) }
        // דגם שאיננו מכירים מתומחר כאופוס — עדיף להעריך גבוה מלהציג אפס
        return (5, 25)
    }

    /// משקל־השוואה בין דגמים, לא מחיר. ר׳ ההסבר בראש הקובץ.
    static func cost(model: String, _ c: Counters) -> Double {
        let r = rate(model)
        let inputSide = Double(c.input) * r.input
            + Double(c.write5) * r.input * 1.25
            + Double(c.write1h) * r.input * 2.0
            + Double(c.read) * r.input * 0.1
        return (inputSide + Double(c.output) * r.output) / 1_000_000
    }

    static func cost(_ models: [String: Counters]) -> Double {
        models.reduce(0) { $0 + cost(model: $1.key, $1.value) }
    }

    static func hebrewModel(_ m: String) -> String {
        let s = m.lowercased()
        if s.contains("fable")  { return Lang.t("פייבל", "Fable") }
        if s.contains("mythos") { return Lang.t("מיתוס", "Mythos") }
        if s.contains("opus")   { return Lang.t("אופוס", "Opus") }
        if s.contains("sonnet") { return Lang.t("סונט", "Sonnet") }
        if s.contains("haiku")  { return Lang.t("הייקו", "Haiku") }
        return m
    }

    // MARK: - מצב

    private static let lock = NSLock()
    private static func guarded<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private static var store = Store()
    private static var loaded = false
    private static var building = false
    private static var lastRefresh = Date.distantPast
    /// כמה יומנים נותרו בבנייה הנוכחית. אפס ⇐ מוכן.
    private(set) static var pending = 0
    /// האם הבנייה הראשונה הסתיימה פעם אחת
    private(set) static var everBuilt = false

    private static var dir: URL { Terminals.home.appendingPathComponent(".claude/peach-spend") }
    private static var storeURL: URL { dir.appendingPathComponent("spend.json") }

    // MARK: - קריאה החוצה

    /// ⛔ **הקוראים טוענים בעצמם.** בלי זה, כל קריאה לפני שהרענון הראשון
    ///    הסתיים מחזירה אפס — כלומר המדף נפתח עם "אין צריכה" למשך חצי דקה,
    ///    וזה נראה כמו תקלה ולא כמו טעינה. הקובץ כבר על הדיסק; אין סיבה
    ///    לחכות לסריקה כדי לקרוא אותו.
    private static func ensureLoaded() {
        if guarded({ loaded }) { return }
        load()
    }

    /// חלקה של שיחה בצריכת **היום**, באחוזים, ומה נשרף בה — טוקני־פלט.
    /// ⇒ שיעור, לא סכום: זה מה שנקרא בשורה אחת ואינו מתחזה לחיוב.
    static func session(_ sid: String) -> (share: Double, output: Int) {
        ensureLoaded()
        let today = dayKey(Date())
        return guarded {
            var all = 0.0
            var mine = 0.0
            var output = 0
            for (id, entry) in store.sessions {
                guard let day = entry.daily[today] else { continue }
                let weight = cost(day)
                all += weight
                if id == sid {
                    mine = weight
                    for (_, c) in day { output += c.output }
                }
            }
            return (all > 0 ? mine / all : 0, output)
        }
    }

    /// הצריכה בטווח־שעות סגור. משמש את חלון־חמש־השעות של המכסה: השרת אומר
    /// מה **האחוז**, והסדרה השעתית אומרת מה נשרף בו בפועל.
    static func window(from: Date, to: Date) -> [String: Any] {
        ensureLoaded()
        let snapshot = guarded { store }
        var byModel: [String: Counters] = [:]
        var hour = from
        while hour <= to {
            if let bucket = snapshot.hours[hourKey(hour)] {
                for (m, c) in bucket { byModel[m, default: Counters()].add(c) }
            }
            hour = hour.addingTimeInterval(3600)
        }
        var sum = Counters()
        for (_, c) in byModel { sum.add(c) }
        return ["output": sum.output, "calls": sum.calls]
    }

    /// כל מה שהמסך צריך.
    static func board(live: [String: String]) -> [String: Any] {
        ensureLoaded()
        let snapshot = guarded { store }
        let today = dayKey(Date())
        let week = Set((0..<7).map { dayKey(Date().addingTimeInterval(-Double($0) * 86400)) })

        func slice(_ pick: (SessionSpend) -> [String: Counters]) -> [String: Any] {
            var byModel: [String: Counters] = [:]
            var rows: [[String: Any]] = []
            for (sid, s) in snapshot.sessions {
                let models = pick(s)
                guard !models.isEmpty else { continue }
                for (m, c) in models { byModel[m, default: Counters()].add(c) }
                let money = cost(models)
                guard money > 0 else { continue }
                var total = Counters()
                for (_, c) in models { total.add(c) }
                rows.append([
                    "sid": sid,
                    "project": s.project,
                    "title": live[sid] ?? s.project,
                    "open": live[sid] != nil,
                    "weight": money,
                    "out": total.output,
                    "calls": total.calls,
                    "model": hebrewModel(models.max { cost(model: $0.key, $0.value)
                        < cost(model: $1.key, $1.value) }?.key ?? "")
                ])
            }
            rows.sort { ($0["weight"] as? Double ?? 0) > ($1["weight"] as? Double ?? 0) }
            var sum = Counters()
            for (_, c) in byModel { sum.add(c) }
            let money = cost(byModel)
            // ⇒ הפילוח מוצג לפי **משפחה**. שני מזהי־אופוס הם שתי שורות "אופוס"
            //   בזו אחר זו, וזה נקרא כטעות ולא כפירוט.
            var family: [String: (cost: Double, out: Int)] = [:]
            for (id, c) in byModel {
                let name = hebrewModel(id)
                let mine = cost(model: id, c)
                family[name] = ((family[name]?.cost ?? 0) + mine,
                                (family[name]?.out ?? 0) + c.output)
            }
            let models: [[String: Any]] = family.map { pair in
                ["name": pair.key, "out": pair.value.out,
                 "share": money > 0 ? pair.value.cost / money : 0]
            }.sorted { ($0["share"] as? Double ?? 0) > ($1["share"] as? Double ?? 0) }
            // ⇒ המשקל נשאר למיון בלבד; מה שמוצג הוא חלק־מהחלון
            for i in rows.indices {
                rows[i]["share"] = money > 0 ? (rows[i]["weight"] as? Double ?? 0) / money : 0
                rows[i]["weight"] = nil
            }
            return ["input": sum.input, "output": sum.output,
                    "read": sum.read, "write": sum.write5 + sum.write1h,
                    "calls": sum.calls, "sessions": Array(rows.prefix(40)), "models": models]
        }

        // עמודה ליום, ארבעה־עשר ימים אחורה — הישן משמאל
        var bars: [[String: Any]] = []
        for back in stride(from: 13, through: 0, by: -1) {
            let date = Date().addingTimeInterval(-Double(back) * 86400)
            let key = dayKey(date)
            var byModel: [String: Counters] = [:]
            for (_, s) in snapshot.sessions {
                guard let day = s.daily[key] else { continue }
                for (m, c) in day { byModel[m, default: Counters()].add(c) }
            }
            var sum = Counters()
            for (_, c) in byModel { sum.add(c) }
            bars.append(["day": shortDay(date), "weight": cost(byModel),
                         "output": sum.output, "today": key == today])
        }

        return [
            "building": pending,
            "ready": everBuilt || !snapshot.marks.isEmpty,
            "logs": snapshot.marks.count,
            "today": slice { $0.daily[today] ?? [:] },
            "week": slice { s in
                var out: [String: Counters] = [:]
                for (day, models) in s.daily where week.contains(day) {
                    for (m, c) in models { out[m, default: Counters()].add(c) }
                }
                return out
            },
            "all": slice { $0.models },
            "bars": bars
        ]
    }

    // MARK: - בנייה

    static func refresh(force: Bool = false) {
        let go: Bool = guarded {
            if building { return false }
            if !force && Date().timeIntervalSince(lastRefresh) < 30 { return false }
            building = true
            lastRefresh = Date()
            return true
        }
        guard go else { return }
        defer { guarded { building = false; pending = 0; everBuilt = true } }

        if !guarded({ loaded }) { load() }
        var local = guarded { store }
        let logs = allLogs()
        guarded { pending = logs.count }
        var changed = false

        for log in logs {
            defer { guarded { pending -= 1 } }
            let mark = local.marks[log.key] ?? Mark(pos: 0, size: 0, lastMsg: "")
            var start = mark.pos
            var lastMsg = mark.lastMsg
            // קובץ שהתכווץ נכתב מחדש — מה שנספר ממנו כבר אינו תקף
            if log.size < mark.size {
                start = 0
                lastMsg = ""
                if var old = local.sessions[log.sid] { old.models = [:]; old.daily = [:]
                    local.sessions[log.sid] = old }
            }
            if log.size == mark.size && start > 0 { continue }

            let result = harvest(url: URL(fileURLWithPath: log.path), from: start, lastMsg: lastMsg)
            local.marks[log.key] = Mark(pos: result.pos, size: log.size, lastMsg: result.lastMsg)
            if !result.rows.isEmpty {
                var entry = local.sessions[log.sid] ?? SessionSpend()
                if entry.project.isEmpty { entry.project = log.project }
                for row in result.rows {
                    entry.models[row.model, default: Counters()].add(row.counters)
                    entry.daily[row.day, default: [:]][row.model, default: Counters()].add(row.counters)
                    local.hours[row.hour, default: [:]][row.model, default: Counters()].add(row.counters)
                    entry.last = max(entry.last, row.at)
                }
                local.sessions[log.sid] = entry
            }
            changed = true
        }

        if changed {
            prune(&local)
            guarded { store = local }
            save(local)
        }
    }

    /// יומן ישן שומר את הסיכום שלו, אבל לא את הפירוט היומי — אחרת הקובץ תופח
    /// בלי גבול ולא נקרא ממנו דבר.
    private static func prune(_ s: inout Store) {
        let floor = hourKey(Date().addingTimeInterval(-21 * 86400))
        s.hours = s.hours.filter { $0.key >= floor }
        let keep = Set((0..<14).map { dayKey(Date().addingTimeInterval(-Double($0) * 86400)) })
        for (sid, var entry) in s.sessions {
            let before = entry.daily.count
            entry.daily = entry.daily.filter { keep.contains($0.key) }
            if entry.daily.count != before { s.sessions[sid] = entry }
        }
    }

    private struct Row {
        let model: String
        let day: String
        let hour: String
        let at: Double
        let counters: Counters
    }

    /// קורא את היומן מהמקום שנעצרנו בו ומחזיר את השורות החדשות.
    private static func harvest(url: URL, from start: Int,
                                lastMsg: String) -> (pos: Int, lastMsg: String, rows: [Row]) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (start, lastMsg, []) }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(start))
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return (start, lastMsg, []) }
        guard let lastBreak = data.lastIndex(of: 0x0A) else { return (start, lastMsg, []) }
        let usable = data[data.startIndex...lastBreak]

        var rows: [Row] = []
        var seen = lastMsg
        // ⇒ סריקה אחת על כל המקטע במקום בדיקה לכל שורה. תשעים אחוז מהנפח הוא
        //   פלט־כלים, וסימן־השימוש כלל אינו מופיע בו.
        for line in lines(containing: marker, in: usable) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            let id = message["id"] as? String ?? ""
            // אותה תשובה, שורה נוספת — כבר נספרה
            if !id.isEmpty && id == seen { continue }
            seen = id
            let model = message["model"] as? String ?? ""
            // ‏"<synthetic>" הוא הודעה שהמסוף עצמו הרכיב, ולא קריאה למודל
            guard !model.isEmpty, !model.hasPrefix("<") else { continue }
            var c = Counters()
            c.input = usage["input_tokens"] as? Int ?? 0
            c.output = usage["output_tokens"] as? Int ?? 0
            c.read = usage["cache_read_input_tokens"] as? Int ?? 0
            let creation = usage["cache_creation"] as? [String: Any]
            c.write1h = creation?["ephemeral_1h_input_tokens"] as? Int ?? 0
            c.write5 = creation?["ephemeral_5m_input_tokens"] as? Int ?? 0
            // יומן ישן אינו מפרק את הכתיבה לפי תוקף — הכול נחשב כחמש דקות
            if creation == nil { c.write5 = usage["cache_creation_input_tokens"] as? Int ?? 0 }
            c.calls = 1
            guard c.output > 0 || c.input > 0 || c.read > 0 || c.write5 > 0 || c.write1h > 0 else { continue }
            let at = Sessions.time(obj["timestamp"]) ?? Date()
            rows.append(Row(model: model, day: dayKey(at), hour: hourKey(at),
                            at: at.timeIntervalSince1970, counters: c))
        }
        return (start + usable.count, seen, rows)
    }

    private static let marker = Array("\"output_tokens\"".utf8)

    /// כל השורות במקטע שיש בהן את הסימן, בלי לפצל את המקטע לשורות מראש.
    private static func lines(containing needle: [UInt8],
                             in slice: Data.SubSequence) -> [Data.SubSequence] {
        var out: [Data.SubSequence] = []
        let n = needle.count
        guard slice.count >= n else { return out }
        let first = needle[0]
        var i = slice.startIndex
        let limit = slice.endIndex - n
        while i <= limit {
            guard slice[i] == first else { i += 1; continue }
            var j = 1
            while j < n && slice[i + j] == needle[j] { j += 1 }
            guard j == n else { i += 1; continue }
            var start = i
            while start > slice.startIndex && slice[start - 1] != 0x0A { start -= 1 }
            var end = i + n
            while end < slice.endIndex && slice[end] != 0x0A { end += 1 }
            out.append(slice[start..<end])
            // דילוג לסוף השורה: מופע שני באותה שורה אינו שורה נוספת
            i = end
        }
        return out
    }

    // MARK: - רשימת היומנים

    private struct Log {
        let path: String
        let key: String
        let sid: String
        let size: Int
        let project: String
    }

    /// כל היומנים — גם של השיחות עצמן וגם של סוכני־הרקע שלהן. סוכן נזקף
    /// לשיחה שהפעילה אותו, שאם לא כן העבודה היקרה ביותר נעלמת מהמניין.
    ///
    /// ⛔ ‏**הקינון עמוק משתי רמות.** סוכן רגיל יושב ב-`<שיחה>/subagents/x.jsonl`,
    ///    אבל סוכן שרץ בתוך תזמור יושב ב-`<שיחה>/subagents/workflows/<ריצה>/agent-x.jsonl`.
    ///    נמדד: מתוך 717 יומנים, 33 היו בעומק הזה — וסריקה של שתי רמות בלבד
    ///    החמיצה אותם בשקט. דווקא הם התזמורים, כלומר העבודה היקרה ביותר.
    ///    ⇒ סורקים לעומק, ותולים כל יומן על התיקייה שהוא יושב תחתיה.
    private static func allLogs() -> [Log] {
        let root = Terminals.home.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [Log] = []
        for folder in dirs {
            let project = projectName(folder.lastPathComponent)
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for item in items {
                if item.pathExtension == "jsonl" {
                    let sid = item.deletingPathExtension().lastPathComponent
                    let size = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    out.append(Log(path: item.path,
                                   key: folder.lastPathComponent + "/" + item.lastPathComponent,
                                   sid: sid, size: size, project: project))
                    continue
                }
                // תיקייה על שם שיחה: כל יומן שמתחתיה, בכל עומק, שייך לה
                let sid = item.lastPathComponent
                guard let walk = FileManager.default.enumerator(
                    at: item, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
                for case let kid as URL in walk where kid.pathExtension == "jsonl" {
                    let size = (try? kid.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    out.append(Log(path: kid.path,
                                   key: folder.lastPathComponent + "/" + sid + "/"
                                        + relative(kid, under: item),
                                   sid: sid, size: size, project: project))
                }
            }
        }
        return out
    }

    /// נתיב יחסי לתיקיית־השיחה, כדי ששני סוכנים בשם זהה בתזמורים שונים
    /// לא ידרסו זה את סימן־הקריאה של זה.
    private static func relative(_ url: URL, under base: URL) -> String {
        let full = url.standardizedFileURL.path
        let root = base.standardizedFileURL.path + "/"
        return full.hasPrefix(root) ? String(full.dropFirst(root.count)) : url.lastPathComponent
    }

    private static func projectName(_ folder: String) -> String {
        let parts = folder.split(separator: "-").filter { !$0.isEmpty }
        guard let last = parts.last else { return "" }
        return parts.count <= 2 ? Lang.t("בית", "home") : String(last)
    }

    // MARK: - שמירה

    private static func load() {
        guarded { loaded = true }
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(Store.self, from: data) else { return }
        guarded { store = decoded }
    }

    private static func save(_ s: Store) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - תאריכים

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let hourFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH"
        return f
    }()
    private static let clockFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let shortFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d.M"
        return f
    }()

    /// ⛔ מנעול נפרד. `dayKey` נקרא גם מתוך `guarded`, ו-`NSLock` אינו רקורסיבי —
    ///    נעילה על אותו מנעול הייתה תוקעת את האפליקציה בשקט.
    private static let clockLock = NSLock()

    private static func dayKey(_ date: Date) -> String {
        clockLock.lock(); defer { clockLock.unlock() }
        return dayFormat.string(from: date)
    }

    private static func shortDay(_ date: Date) -> String {
        clockLock.lock(); defer { clockLock.unlock() }
        return shortFormat.string(from: date)
    }

    private static func hourKey(_ date: Date) -> String {
        clockLock.lock(); defer { clockLock.unlock() }
        return hourFormat.string(from: date)
    }

    static func clock(_ date: Date) -> String {
        clockLock.lock(); defer { clockLock.unlock() }
        return clockFormat.string(from: date)
    }

    private static func hourDate(_ key: String) -> Date? {
        clockLock.lock(); defer { clockLock.unlock() }
        return hourFormat.date(from: key)
    }
}
