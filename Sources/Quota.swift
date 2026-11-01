import Foundation

/// המכסה של המנוי: כמה מתוכה נצרך בחלון־חמש־השעות ובשבוע, ומתי היא נאפסת.
///
/// ⛔ ‏**המספר הזה אינו קיים על הדיסק ואי־אפשר לגזור אותו מהיומנים.** רק
///    השרת יודע מה התקרה. לכן דוגם נפרד — `~/.claude/bin/peach-quota.sh`,
///    שמותקן כמשימת־רקע כל שלוש דקות — מביא אותו וכותב אותו לקובץ, ופיץ׳
///    ממשיך לקרוא דיסק בלבד: בלי רשת, בלי אסימון, בלי מחסן־מפתחות.
///
/// ⚠ ‏**מספר ישן שמוצג כעכשיו הוא שקר.** לכל קריאה מצורף גיל, והמסך אומר
///    בפירוש כשהדגימה התיישנה.
enum Quota {

    struct Row {
        let kind: String
        let label: String
        let percent: Int
        let severity: String
        let resets: Date?
        let active: Bool
    }

    struct Reading {
        let rows: [Row]
        let fetched: Date?
        let error: String
        /// שניות מאז הדגימה
        var age: TimeInterval { fetched.map { Date().timeIntervalSince($0) } ?? .infinity }
        /// דגימה שגילה מעל רבע שעה כבר אינה מתארת את עכשיו
        var stale: Bool { age > 900 }
        var missing: Bool { fetched == nil }
    }

    static var file: URL {
        Terminals.home.appendingPathComponent(".claude/peach-spend/quota.json")
    }

    static func read() -> Reading {
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Reading(rows: [], fetched: nil, error: "")
        }
        let fetched = (obj["fetched"] as? Double).map { Date(timeIntervalSince1970: $0) }
        if let error = obj["error"] as? String, !error.isEmpty {
            return Reading(rows: [], fetched: fetched, error: error)
        }
        let raw = obj["limits"] as? [[String: Any]] ?? []
        let rows: [Row] = raw.compactMap { item in
            guard let kind = item["kind"] as? String else { return nil }
            let scope = (item["scope"] as? [String: Any])?["model"] as? [String: Any]
            let model = scope?["display_name"] as? String ?? ""
            return Row(kind: kind,
                       label: hebrew(kind: kind, model: model),
                       percent: item["percent"] as? Int ?? 0,
                       severity: item["severity"] as? String ?? "normal",
                       resets: stamp(item["resets_at"]),
                       active: item["is_active"] as? Bool ?? false)
        }
        return Reading(rows: rows, fetched: fetched, error: "")
    }

    private static func hebrew(kind: String, model: String) -> String {
        switch kind {
        case "session":       return Lang.t("חלון חמש שעות", "five-hour window")
        case "weekly_all":    return Lang.t("השבוע — הכול", "this week — all")
        case "weekly_scoped": return model.isEmpty
                                     ? Lang.t("השבוע — דגם", "this week — model")
                                     : Lang.t("השבוע — ", "this week — ") + model
        case "weekly_opus":   return Lang.t("השבוע — אופוס", "this week — Opus")
        case "weekly_sonnet": return Lang.t("השבוע — סונט", "this week — Sonnet")
        default:              return kind
        }
    }

    private static func stamp(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return Sessions.time(s)
    }

    /// כמה נשאר עד האיפוס, בשפה שנקראת במבט.
    static func until(_ date: Date?) -> String {
        guard let date else { return "" }
        let left = date.timeIntervalSinceNow
        if left <= 0 { return Lang.t("נאפס", "reset") }
        let hours = Int(left) / 3600
        let minutes = (Int(left) % 3600) / 60
        if hours >= 48 { return "\(hours / 24)" + Lang.t(" ימים", "d") }
        if hours >= 1 { return String(format: Lang.t("%d:%02d שע׳", "%d:%02dh"), hours, minutes) }
        return "\(minutes)" + Lang.t(" דק׳", "m")
    }

    static func payload() -> [String: Any] {
        let reading = read()
        return [
            "rows": reading.rows.map { row -> [String: Any] in
                [
                    "label": row.label,
                    "percent": row.percent,
                    "severity": row.severity,
                    "active": row.active,
                    "at": row.resets.map { Spend.clock($0) } ?? "",
                    "until": until(row.resets)
                ]
            },
            "error": reading.error,
            "missing": reading.missing,
            "stale": reading.stale,
            "age": Int(reading.age.isFinite ? reading.age : 0)
        ]
    }
}
