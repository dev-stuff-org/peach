import Foundation

/// שאלה פתוחה אחת שממתינה למשתמש.
struct Ask {
    let id: String
    /// דחיפות לפי הסימן בכותרת: 🔴 🟠 🟡 🟢
    let urgency: String
    let title: String
    /// מי שואל, מתי, וכמה עולה לענות
    let asker: String
    let since: String
    let cost: String
    let body: String
    let answer: String
    /// טווח־השורות של הפריט בקובץ, לכתיבה חזרה
    let from: Int
    let to: Int
}

/// קריאה וכתיבה של קובץ־השאלות היחיד.
///
/// **קובץ אחד, ואין שני.** זה כלל עומד של המשתמש: כל שיחה כותבת לשם, והוא עונה
/// שם. המסך הזה הוא רק חלון אל אותו קובץ — הוא אינו מאגר נוסף.
enum Asks {

    static var file: URL {
        Paths.questionsFile
    }

    private static let marks = ["🔴", "🟠", "🟡", "🟢"]

    static func all() -> [Ask] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: "\n")

        var heads: [Int] = []
        for (i, line) in lines.enumerated() where line.hasPrefix("## ") { heads.append(i) }

        var out: [Ask] = []
        for (n, head) in heads.enumerated() {
            let stop = n + 1 < heads.count ? heads[n + 1] : lines.count
            if let ask = parse(lines: lines, from: head, to: stop) { out.append(ask) }
        }
        // הדחוף למעלה, ובתוך אותה דחיפות — לפי הסדר בקובץ
        return out.enumerated().sorted { a, b in
            let ra = marks.firstIndex(of: a.element.urgency) ?? 9
            let rb = marks.firstIndex(of: b.element.urgency) ?? 9
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    private static func parse(lines: [String], from head: Int, to stop: Int) -> Ask? {
        var title = String(lines[head].dropFirst(3)).trimmingCharacters(in: .whitespaces)

        var urgency = ""
        for mark in marks where title.hasPrefix(mark) {
            urgency = mark
            title = String(title.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
        }

        var id = ""
        if title.hasPrefix("["), let close = title.firstIndex(of: "]") {
            id = String(title[title.index(after: title.startIndex)..<close])
            title = String(title[title.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        guard !id.isEmpty else { return nil }

        var asker = "", since = "", cost = ""
        var bodyLines: [String] = []
        var answerLines: [String] = []
        var inAnswer = false

        for i in (head + 1)..<stop {
            let line = lines[i]
            let bare = line.trimmingCharacters(in: .whitespaces)

            if bare.hasPrefix(Lang.t("תשובה:", "Answer:")) || bare.hasPrefix(Lang.t("**תשובה:**", "**Answer:**")) {
                inAnswer = true
                let tail = bare.replacingOccurrences(of: Lang.t("**תשובה:**", "**Answer:**"), with: "")
                    .replacingOccurrences(of: Lang.t("תשובה:", "Answer:"), with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty { answerLines.append(tail) }
                continue
            }
            // קו־ההפרדה בין פריטים אינו חלק מהתשובה
            if inAnswer {
                if bare.hasPrefix("---") { inAnswer = false; continue }
                answerLines.append(line)
                continue
            }

            if bare.contains(Lang.t("**מבקש:**", "**Asked by:**")) || bare.contains(Lang.t("**עלות-הענייה:**", "**Cost to answer:**")) {
                asker = value(in: bare, after: Lang.t("**מבקש:**", "**Asked by:**"))
                since = value(in: bare, after: Lang.t("**מאז:**", "**Since:**"))
                cost = value(in: bare, after: Lang.t("**עלות-הענייה:**", "**Cost to answer:**"))
                continue
            }
            bodyLines.append(line)
        }

        return Ask(id: id,
                   urgency: urgency.isEmpty ? "🟡" : urgency,
                   title: title,
                   asker: asker, since: since, cost: cost,
                   body: bodyLines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                   answer: answerLines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                   from: head, to: stop)
    }

    /// ערך אחד משורת־המטא, שכולה מופרדת בנקודות.
    private static func value(in line: String, after key: String) -> String {
        guard let at = line.range(of: key) else { return "" }
        let rest = line[at.upperBound...]
        let cut = rest.range(of: " · ")
        let value = cut == nil ? String(rest) : String(rest[..<cut!.lowerBound])
        return value.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - כתיבת תשובה

    /// כותב תשובה לשאלה. מחזיר הודעת־שגיאה ריקה אם הצליח.
    ///
    /// הכתיבה מחליפה את גוש־התשובה של אותו פריט בלבד, ומשאירה את כל השאר
    /// בדיוק כפי שהוא — שיחות אחרות כותבות לאותו קובץ באותו רגע.
    static func answer(id: String, text: String) -> String {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else {
            return Lang.t("לא הצלחתי לקרוא את קובץ־השאלות", "Could not read the questions file")
        }
        var lines = raw.components(separatedBy: "\n")
        guard let ask = all().first(where: { $0.id == id }) else { return Lang.t("השאלה לא נמצאה", "Question not found") }

        var mark = -1
        for i in ask.from..<min(ask.to, lines.count) {
            let bare = lines[i].trimmingCharacters(in: .whitespaces)
            if bare.hasPrefix(Lang.t("תשובה:", "Answer:")) || bare.hasPrefix(Lang.t("**תשובה:**", "**Answer:**")) { mark = i; break }
        }
        let stamped = Lang.t("תשובה: ", "Answer: ") + text.replacingOccurrences(of: "\n", with: " ")
        if mark >= 0 {
            var cut = mark + 1
            while cut < min(ask.to, lines.count) { cut += 1 }
            lines.replaceSubrange(mark..<cut, with: [stamped, ""])
        } else {
            lines.insert(contentsOf: ["", stamped], at: min(ask.to, lines.count))
        }

        return Documents.write(file.path, text: lines.joined(separator: "\n"))
    }
}
