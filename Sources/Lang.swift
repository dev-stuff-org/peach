import Foundation

/// שפת־הממשק. עברית היא ברירת־המחדל, ואנגלית היא מה שפותח את פיץ׳ לעולם.
///
/// ⛔ ‏**לא מערכת־תרגום, ובכוונה.** קובצי־מחרוזות של אפל דורשים מפתחות,
///    ומפתח הוא שם שצריך להמציא לכל מחרוזת ואז לזכור. כאן שתי הגרסאות
///    יושבות זו לצד זו באתר־השימוש — מי שמשנה טקסט רואה מיד את שתיהן,
///    ומחרוזת שנשכחה בולטת לעין במקום להישאר מפתח מת בקובץ צדדי.
///
/// ⚠ ‏**השפה נקבעת פעם אחת בהפעלה.** הדף נבנה כמחרוזת אחת ומוזרק פעם
///   אחת; החלפה חיה הייתה דורשת לבנות אותו מחדש באמצע. ⇒ שינוי־שפה
///   נשמר ומבקש הפעלה־מחדש, ואומר זאת.
enum Lang {

    /// ‏"he" · "en"
    private(set) static var code: String = load()

    static var isHebrew: Bool { code == "he" }
    /// כיוון־הכתיבה של הדף. אנגלית אינה רק תרגום — היא גם היפוך פריסה.
    static var dir: String { isHebrew ? "rtl" : "ltr" }

    /// שתי הגרסאות, זו לצד זו. ⇒ אין מפתחות, ואין מה לשכוח לעדכן.
    static func t(_ he: String, _ en: String) -> String { isHebrew ? he : en }

    // MARK: - שמירה

    private static let key = "peach.lang"

    /// ⛔ ‏**לא ״עברית לישראלים״.** לשון־המערכת אומרת מה המשתמש בחר לראות,
    ///    ואזור אומר איפה הוא נמצא — שני דברים שונים. מפתח ישראלי שמריץ
    ///    מק באנגלית רוצה ממשק באנגלית, ופיץ׳ שמכריח אותו לעברית נראה
    ///    כמו כלי ששכח שיש לו משתמשים.
    private static func load() -> String {
        // תפר־בדיקה: מאפשר לצייר מסך בשתי השפות בלי לגעת בהעדפות של המשתמש
        if let forced = ProcessInfo.processInfo.environment["PEACH_LANG"],
           forced == "he" || forced == "en" { return forced }
        if let saved = UserDefaults.standard.string(forKey: key),
           saved == "he" || saved == "en" { return saved }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("he") || preferred.hasPrefix("iw") ? "he" : "en"
    }

    /// מחליף ושומר. הקורא אחראי לומר למשתמש שצריך להפעיל מחדש.
    static func set(_ next: String) {
        guard next == "he" || next == "en", next != code else { return }
        code = next
        UserDefaults.standard.set(next, forKey: key)
    }
}
