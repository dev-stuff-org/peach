import Foundation

/// אפשרות אחת בשאלה שנשאלה במסוף.
struct AskChoice {
    let label: String
    let detail: String
}

/// שאלה בודדת. שאלת־מסוף אחת יכולה לשאת כמה שאלות בבת־אחת.
struct AskPart {
    let question: String
    let header: String
    let multi: Bool
    let choices: [AskChoice]
}

/// שאלה שנשאלה במסוף ועדיין ממתינה לתשובה.
struct PendingQuestion {
    let sid: String
    let toolID: String
    /// ‏"ask" — שאלה עם אפשרויות · "plan" — אישור תוכנית
    let kind: String
    let parts: [AskPart]
    /// גוף התוכנית, כשזו בקשת־אישור
    let plan: String
    let since: Date
    /// The session's own words right before the question — what it is about.
    var context: String = ""
}

/// איתור שאלה פתוחה מתוך יומן־השיחה.
///
/// ‏**למה זה בכלל אפשרי מבחוץ:** כששיחה שואלת, היא כותבת ליומן בלוק
/// ‏`tool_use` ואז נעצרת. התשובה נכנסת אחר־כך כ-`tool_result` הנושא את אותו
/// מזהה. ⇒ שאלה פתוחה היא בלוק־שאלה **שהמזהה שלו אינו מופיע שוב** אחריו.
///
/// ⛔ ‏**לא נשענים על הגיל.** שאלה יכולה לחכות שעות ועדיין להיות פתוחה,
/// ושאלה שנענתה מיד עדיין צעירה. הראיה היחידה היא המזהה.
enum Questions {

    private static let lock = NSLock()
    private static func guarded<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
    private static var cache: [String: (size: Int, modified: Date, ask: PendingQuestion?)] = [:]

    /// כמה בתים מסוף היומן נקראים. שאלה יושבת בסוף מעצם הגדרתה.
    private static let tail: UInt64 = 2_000_000

    private static let askMarker  = Array("\"AskUserQuestion\"".utf8)
    private static let planMarker = Array("\"ExitPlanMode\"".utf8)
    private static let useMarker  = Array("\"tool_use\"".utf8)

    /// סריקת־בתים על הפרוסה עצמה, בלי להעתיק אותה למחרוזת.
    private static func holds(_ slice: Data.SubSequence, _ needle: [UInt8]) -> Bool {
        let n = needle.count
        guard slice.count >= n else { return false }
        let first = needle[0]
        var i = slice.startIndex
        let last = slice.endIndex - n
        while i <= last {
            if slice[i] == first {
                var j = 1
                while j < n && slice[i + j] == needle[j] { j += 1 }
                if j == n { return true }
            }
            i += 1
        }
        return false
    }

    static func pending(sessionID: String) -> PendingQuestion? {
        guard !sessionID.isEmpty, let url = Sessions.transcriptURL(for: sessionID) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let modified = attrs[.modificationDate] as? Date ?? .distantPast
        if let hit = guarded({ cache[sessionID] }), hit.size == size, hit.modified == modified {
            return hit.ask
        }
        let fresh = read(url: url, sid: sessionID)
        guarded {
            cache[sessionID] = (size, modified, fresh)
            if cache.count > 200 { cache.removeAll() }
        }
        trace(sid: sessionID, size: size, modified: modified, ask: fresh)
        return fresh
    }

    /// ⛔ ‏**מבחוץ אי־אפשר להבחין בין ״לא נשאלה שאלה״ לבין ״נשאלה ולא
    ///    נראתה״.** המשתמש דיווח על שאלה שהמתינה 37 דקות ולא הופיעה במסך;
    ///    הפרסר הוכח נכון על אותו קובץ בדיוק, כלומר הכשל במקום אחר —
    ///    ובלי רישום אין דרך לדעת אם `pending` בכלל נקראה לשיחה ההיא.
    ///
    /// ⇒ נרשמת **רק תזוזה**: הופעה, היעלמות, או החלפת־שאלה. שיחה שקטה
    ///   אינה כותבת דבר, ולכן זה נשאר זול גם על 35 מסופים בכל פעימה.
    private static var seen: [String: String] = [:]
    private static let traceURL = Terminals.home.appendingPathComponent(".claude/peach-asks.log")

    private static func trace(sid: String, size: Int, modified: Date, ask: PendingQuestion?) {
        let now = ask.map { $0.kind + ":" + $0.toolID } ?? "-"
        let moved: Bool = guarded {
            let was = seen[sid]
            if was == now { return false }
            seen[sid] = now
            if seen.count > 400 { seen.removeAll() }
            // ⇒ ראייה ראשונה של שיחה שקטה אינה תזוזה. בלי התנאי הזה כל
            //   הפעלה הייתה פותחת בשורה לכל מסוף פתוח, והיומן היה רועש
            //   בדיוק במקום שבו הוא אמור להיות דליל ונקרא.
            return !(was == nil && now == "-")
        }
        guard moved else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(sid) size=\(size) mtime=\(Int(modified.timeIntervalSince1970)) ask=\(now)\n"
        guard let bytes = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: traceURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: bytes)
        } else {
            try? bytes.write(to: traceURL)
        }
    }

    /// כל השאלות הפתוחות במסופים הפתוחים, הדחוף־ביותר ראשון.
    static func all(for terminals: [Terminal]) -> [(term: Terminal, ask: PendingQuestion)] {
        terminals.compactMap { term in
            guard let ask = pending(sessionID: term.sessionID) else { return nil }
            return (term, ask)
        }.sorted { $0.ask.since > $1.ask.since }
    }

    /// ⛔ ‏**נקרא מהסוף אחורה, ועוצר על הראשון שנמצא.**
    ///
    /// קודם נבנה כאן חלון של שני מגה־בתים למחרוזות, לכל מסוף, **בכל
    /// פעימה**. נמדד על 35 מסופים: זה היה הפריט היקר ביותר בהרכבת המדף —
    /// יותר מכל שאר הרכיבים יחד. ⚠ והמטמון אינו עוזר: הוא ננעל על
    /// (גודל, זמן־שינוי), ובשיחה שרצה עכשיו שניהם זזים כל הזמן, כלומר
    /// הוא **לעולם אינו נפגע**. ⇒ זה מה שהאט את החזרה למדף.
    ///
    /// השאלה שמעניינת היא תמיד האחרונה, והיא כמעט תמיד בסוף היומן.
    private static func read(url: URL, sid: String) -> PendingQuestion? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let clipped = size > tail
        try? handle.seek(toOffset: clipped ? size - tail : 0)
        let data = (try? handle.readToEnd()) ?? Data()

        var candidate: (id: String, kind: String, input: [String: Any], at: Date)?
        var after = data.endIndex

        var end = data.endIndex
        while end > data.startIndex {
            if data[end - 1] == 0x0A { end -= 1; continue }
            var begin = end
            while begin > data.startIndex && data[begin - 1] != 0x0A { begin -= 1 }
            if clipped && begin == data.startIndex { break }
            let row = data[begin..<end]
            end = begin

            // בדיקת־בתים לפני פענוח: רוב השורות אינן שאלה כלל
            guard holds(row, askMarker) || holds(row, planMarker) else { continue }
            guard holds(row, useMarker) else { continue }
            // ⛔ שאלה של סוכן־רקע אינה שאלה למשתמש — הסוכן עונה לעצמו
            guard let obj = try? JSONSerialization.jsonObject(with: Data(row)) as? [String: Any],
                  obj["isSidechain"] as? Bool != true,
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { continue }
            for block in blocks where block["type"] as? String == "tool_use" {
                let name = block["name"] as? String ?? ""
                guard name == "AskUserQuestion" || name == "ExitPlanMode" else { continue }
                guard let id = block["id"] as? String else { continue }
                candidate = (id, name == "ExitPlanMode" ? "plan" : "ask",
                             block["input"] as? [String: Any] ?? [:],
                             Sessions.time(obj["timestamp"]) ?? Date())
            }
            // האחרון אחורה הוא האחרון בזמן ⇒ אין למה להמשיך
            if candidate != nil { after = begin; break }
        }

        guard let hit = candidate else { return nil }
        let context = prose(before: after, in: data)
        // המזהה חוזר אחרי הבלוק ⇒ נענתה. סריקת־בתים אחת על מה שאחריו.
        let tailSlice = data[after..<data.endIndex]
        if holds(tailSlice, Array("\"tool_use_id\":\"\(hit.id)\"".utf8))
            || holds(tailSlice, Array("\"tool_use_id\": \"\(hit.id)\"".utf8)) {
            return nil
        }

        if hit.kind == "plan" {
            // The plan text, or the plan file when the call carried only its path.
            var plan = hit.input["plan"] as? String ?? ""
            if plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let path = hit.input["planFilePath"] as? String,
               path.hasPrefix(Terminals.home.appendingPathComponent(".claude/plans").path),
               let text = try? String(contentsOfFile: path, encoding: .utf8) {
                plan = text
            }
            return PendingQuestion(sid: sid, toolID: hit.id, kind: "plan",
                                   parts: [], plan: plan, since: hit.at, context: context)
        }

        let raw = hit.input["questions"] as? [[String: Any]] ?? []
        let parts: [AskPart] = raw.map { q in
            let choices = (q["options"] as? [[String: Any]] ?? []).map {
                AskChoice(label: $0["label"] as? String ?? "",
                          detail: $0["description"] as? String ?? "")
            }
            return AskPart(question: q["question"] as? String ?? "",
                           header: q["header"] as? String ?? "",
                           multi: q["multiSelect"] as? Bool ?? false,
                           choices: choices)
        }.filter { !$0.question.isEmpty }
        guard !parts.isEmpty else { return nil }
        return PendingQuestion(sid: sid, toolID: hit.id, kind: "ask",
                               parts: parts, plan: "", since: hit.at, context: context)
    }

    private static let textMarker = Array("\"text\"".utf8)
    private static let promptMarker = Array("\"type\":\"user\"".utf8)

    /// The nearest assistant prose above the question block, walking back
    /// until the turn's own prompt. Only the main thread counts.
    private static func prose(before limit: Data.Index, in data: Data) -> String {
        var end = limit
        var rows = 0
        while end > data.startIndex && rows < 400 {
            if data[end - 1] == 0x0A { end -= 1; continue }
            var begin = end
            while begin > data.startIndex && data[begin - 1] != 0x0A { begin -= 1 }
            let row = data[begin..<end]
            end = begin
            rows += 1
            guard holds(row, textMarker) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(row)) as? [String: Any],
                  obj["isSidechain"] as? Bool != true,
                  let message = obj["message"] as? [String: Any] else { continue }
            if obj["type"] as? String == "user" {
                // A real prompt ends the turn; tool results do not.
                if message["content"] is String { break }
                let blocks = message["content"] as? [[String: Any]] ?? []
                if blocks.contains(where: { $0["type"] as? String == "text" }) { break }
                continue
            }
            guard obj["type"] as? String == "assistant",
                  let blocks = message["content"] as? [[String: Any]] else { continue }
            let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(2000)) }
        }
        return ""
    }
}
