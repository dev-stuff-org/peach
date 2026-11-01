import Foundation

/// חיפוש בכל השיחות — על האינדקס, לא על היומנים.
///
/// לפני האינדקס: שלוש שניות לשאילתה, בכל פעם מחדש, על 1.4 ג'יגה־בתים של
/// יומנים שרובם פלט־כלים. אחרי: סריקה על כמה עשרות מגהבייטים של טקסט־שיחה
/// בלבד. אותו כלי־סריקה, אוכלוסייה קטנה בשני סדרי־גודל.
enum Search {

    /// תקרת־תוצאות. חיפוש שמחזיר אלף שורות אינו תשובה.
    private static let results = 60

    static func run(_ query: String) -> [[String: Any]] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        Index.refresh()

        // סורקים מהשיחות העדכניות לישנות, ועוצרים ברגע שיש מספיק.
        // מילה נפוצה כמו "מרץ" מופיעה בכל יומן; בלי העצירה היא הייתה מחזירה
        // אלפי שורות ולוקחת ארבע שניות — יותר מהמצב שבאנו לתקן.
        let shards = Index.shardsByRecency()
        var out: [[String: Any]] = []
        var seen = Set<String>()
        var at = 0

        // המנה הראשונה קטנה — לרוב היא מספיקה ואז לא נגענו בשאר בכלל.
        // אם לא הספיקה, השאר נסרק בקריאה אחת: כל הפעלת־תהליך נוספת עולה
        // יותר מהסריקה עצמה על אינדקס בגודל הזה.
        var take = 60
        while at < shards.count && out.count < results {
            let batch = Array(shards[at..<min(at + take, shards.count)])
            at += take
            take = shards.count
            var args = ["-a", "-i", "-F", "-m", "12", "--", needle]
            args.append(contentsOf: batch)
            guard let raw = Terminals.shell("/usr/bin/grep", args) else { continue }
            collect(raw, needle: needle.lowercased(), into: &out, seen: &seen)
        }

        // החדש למעלה. מי שמחפש משהו שאמר, אמר אותו לאחרונה.
        let flat = out.sorted { ($0["sort"] as? Double ?? 0) > ($1["sort"] as? Double ?? 0) }
        return group(flat)
    }

    /// כמה שורות מוצגות מכל שיחה. מעבר לזה זו אותה שיחה שחוזרת על עצמה.
    private static let perChat = 3
    /// ⛔ ‏**וכמה שיחות בכלל.** ‏95 כרטיסים אינם תוצאה אלא ערימה, ופענוח
    ///    השם של כל אחת מהן עלה ארבע שניות. שתים־עשרה נקראות במבט.
    private static let chatCeiling = 12

    /// ⛔ ‏**רשימה שטוחה של ציטוטים אינה ניתנת לפענוח.** אותה שיחה חוזרת
    ///    חמש פעמים, אין לה שם, ואי־אפשר לדעת על מה ללחוץ. ⇒ מקבצים לפי
    ///    שיחה, נותנים לה את **השם** שלה, ומראים שלוש שורות לכל היותר.
    private static func group(_ flat: [[String: Any]]) -> [[String: Any]] {
        var order: [String] = []
        var byChat: [String: [[String: Any]]] = [:]
        for hit in flat {
            let sid = hit["sid"] as? String ?? ""
            if byChat[sid] == nil { order.append(sid) }
            byChat[sid, default: []].append(hit)
        }
        return order.prefix(chatCeiling).map { sid in
            let hits = byChat[sid] ?? []
            let session = Sessions.state(id: sid)
            var name = session?.title ?? ""
            if name.isEmpty { name = session?.project ?? "" }
            if name.isEmpty { name = Index.project(of: sid) }
            if name.isEmpty { name = Lang.t("שיחה ללא שם", "untitled conversation") }
            return [
                "sid": sid,
                "title": name,
                "project": Index.project(of: sid),
                "when": hits.first?["when"] as? String ?? "",
                "sort": hits.first?["sort"] as? Double ?? 0,
                "total": hits.count,
                "hits": Array(hits.prefix(perChat))
            ]
        }
    }

    private static func collect(_ raw: String, needle: String,
                                into out: inout [[String: Any]], seen: inout Set<String>) {
        for row in raw.split(separator: "\n") {
            guard let cut = row.range(of: ".txt:") else { continue }
            let sid = String(row[..<cut.lowerBound]).components(separatedBy: "/").last ?? ""
            let line = String(row[cut.upperBound...])

            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let text = String(fields[2])
            guard let range = text.range(of: needle, options: .caseInsensitive) else { continue }

            let key = sid + "|" + text.prefix(40)
            if seen.contains(key) { continue }
            seen.insert(key)

            let pad = 70
            let start = text.index(range.lowerBound, offsetBy: -pad, limitedBy: text.startIndex)
                ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: pad, limitedBy: text.endIndex)
                ?? text.endIndex
            let epoch = Double(fields[0]) ?? 0

            out.append([
                "sid": sid,
                "project": Index.project(of: sid),
                "role": fields[1] == "y" ? "you" : "claude",
                "when": epoch > 0 ? short.string(from: Date(timeIntervalSince1970: epoch)) : "",
                "sort": epoch,
                "before": (start > text.startIndex ? "…" : "") + String(text[start..<range.lowerBound]),
                "hit": String(text[range]),
                "after": String(text[range.upperBound..<end]) + (end < text.endIndex ? "…" : "")
            ])
        }
    }

    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d.M HH:mm"
        return f
    }()
}
