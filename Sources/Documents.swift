import Foundation
import AppKit
import PDFKit

/// קריאה וכתיבה של מסמכי־טקסט שנפתחים בתוך השיחה.
///
/// שמירה היא הפעולה המסוכנת היחידה באפליקציה — כל השאר קורא בלבד. לכן היא
/// כותבת דרך קובץ־ביניים ורק אז מחליפה, ושומרת גיבוי אחד לצד המקור. קובץ
/// שנחתך באמצע כתיבה הוא הדרך לאבד עבודה של המשתמש.
enum Documents {

    /// גודל מרבי לפתיחה. מסמך של מגהבייטים אינו מה שקוראים בתוך שיחה,
    /// והדפדפן היה נתקע עליו.
    private static let ceiling = 2_000_000

    static func read(_ path: String) -> (text: String, error: String) {
        let url = URL(fileURLWithPath: expand(path))
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ("", Lang.t("הקובץ לא נמצא", "File not found"))
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size]
                    as? NSNumber)?.intValue ?? 0
        guard size <= ceiling else { return ("", Lang.t("הקובץ גדול מדי לפתיחה כאן", "File too large to open here")) }
        guard let data = try? Data(contentsOf: url) else { return ("", Lang.t("אין הרשאת קריאה", "No read permission")) }
        return (String(decoding: data, as: UTF8.self), "")
    }

    /// כותב, ומחזיר הודעת־שגיאה ריקה אם הצליח.
    static func write(_ path: String, text: String) -> String {
        let url = URL(fileURLWithPath: expand(path))
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Lang.t("הקובץ לא נמצא — פיץ׳ שומר רק על קובץ קיים", "File not found — Peach only saves over a file that exists")
        }
        // The page hands back text with LF only (a textarea normalises CRLF)
        // and Documents.read decoded leniently. Writing that as-is would
        // rewrite every line of a CRLF file, or replace undecodable bytes.
        var text = text
        if let old = try? Data(contentsOf: url) {
            guard String(data: old, encoding: .utf8) != nil else {
                return Lang.t("הקובץ אינו UTF-8 תקין — שמירה הייתה משחיתה אותו", "The file is not valid UTF-8 — saving would corrupt it")
            }
            if old.range(of: Data("\r\n".utf8)) != nil && !text.contains("\r") {
                text = text.replacingOccurrences(of: "\n", with: "\r\n")
            }
            if old.starts(with: [0xEF, 0xBB, 0xBF]) && !text.hasPrefix("\u{FEFF}") {
                text = "\u{FEFF}" + text
            }
        }
        // גיבוי אחד לצד המקור, לפני שנוגעים בו
        let backup = url.appendingPathExtension("gib")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)

        do {
            // כתיבה אטומית: הקובץ המקורי מוחלף רק אחרי שהחדש נכתב במלואו
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return Lang.t("השמירה נכשלה: ", "Save failed: ") + error.localizedDescription
        }
        return ""
    }

    static let textKinds = ["md", "txt", "csv", "json", "swift", "py", "sh", "js",
                            "css", "html", "yml", "yaml", "log", "applescript"]
    static let imageKinds = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "bmp"]

    /// ‏"md" מסמך שמרונדר · "text" טקסט גולמי · "image" תמונה ·
    /// ‏"pdf" מסמך שמרונדר לתמונות · "other" לא נפתח כאן.
    static func kind(of path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "md" || ext == "markdown" { return "md" }
        if ext == "pdf" { return "pdf" }
        if imageKinds.contains(ext) { return "image" }
        if textKinds.contains(ext) { return "text" }
        return "other"
    }

    /// תמונה כתוכן־מוטמע. הדף אינו יכול לטעון קובץ מקומי בעצמו — מדיניות
    /// האבטחה של מנוע־הדפדפן חוסמת זאת — ולכן התמונה נשלחת אליו מוטמעת.
    /// נשלחת רק כשנפתחת: הטמעה של כל צילום בכל ציור הייתה מגהבייטים לפעימה.
    static func asset(_ path: String) -> [String: Any] {
        let full = expand(path)
        let what = kind(of: full)
        let size = ((try? FileManager.default.attributesOfItem(atPath: full))?[.size]
                    as? NSNumber)?.intValue ?? 0
        var out: [String: Any] = ["path": path, "kind": what, "size": size,
                                  "name": (full as NSString).lastPathComponent]
        guard FileManager.default.fileExists(atPath: full) else {
            out["error"] = Lang.t("הקובץ לא נמצא", "File not found")
            return out
        }
        // ⛔ ‏**הדף אינו יכול להציג PDF בעצמו.** תוסף־ה-PDF של מנוע־הדפדפן
        //    אינו רץ על דף שנטען כמחרוזת, וכתובת־נתונים בתוך מסגרת נחסמת.
        //    ⇒ מרנדרים את העמודים לתמונות בצד סוויפט ושולחים אותן כמו כל
        //      תמונה אחרת. זה גם מה שהמשתמש באמת רוצה: לראות, לא להוריד.
        if what == "pdf" {
            guard let doc = PDFDocument(url: URL(fileURLWithPath: full)) else {
                out["error"] = Lang.t("הקובץ אינו נקרא כ-PDF", "The file does not read as a PDF")
                return out
            }
            out["pages"] = doc.pageCount
            var shots: [String] = []
            var weight = 0
            for index in 0..<min(doc.pageCount, pdfPageCeiling) {
                guard let page = doc.page(at: index),
                      let shot = render(page: page) else { continue }
                weight += shot.count
                // ⚠ תקרה על המשקל, לא רק על מספר העמודים: עמוד סרוק שוקל
                //   פי עשרה מעמוד־טקסט, ושלושה כאלה היו חונקים את הדף.
                if weight > 7_000_000 { break }
                shots.append("data:image/jpeg;base64," + shot.base64EncodedString())
            }
            if shots.isEmpty { out["error"] = Lang.t("לא הצלחתי לצייר את העמודים", "Could not render the pages") }
            out["shots"] = shots
            return out
        }
        if what == "image" {
            guard size <= 12_000_000 else { out["error"] = Lang.t("התמונה גדולה מדי", "Image too large"); return out }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: full)) else {
                out["error"] = Lang.t("אין הרשאת קריאה", "No read permission"); return out
            }
            out["src"] = "data:" + mime(full) + ";base64," + data.base64EncodedString()
            return out
        }
        guard size <= 600_000 else { out["error"] = Lang.t("הקובץ גדול מדי לתצוגה כאן", "File too large to display here"); return out }
        let read = self.read(full)
        if !read.error.isEmpty { out["error"] = read.error } else { out["text"] = read.text }
        return out
    }

    /// כמה עמודים מוצגים בכרטיס. מסמך בן ארבעים עמודים אינו נפרש בשיחה —
    /// לזה יש "פתיחה בחוץ".
    static let pdfPageCeiling = 4

    /// עמוד → תמונה. הרוחב נבחר כדי שטקסט של מכתב יהיה קריא בלי להגדיל,
    /// והדחיסה כדי ששלושה עמודים לא ישקלו יותר מצילום־מסך אחד.
    ///
    /// ⛔ ‏**לא דרך `NSImage.lockFocus`.** הוא מצייר לפי צפיפות־המסך, ועל מסך
    ///    רשתית יצא עמוד ברוחב 2480 פיקסלים במקום 1240 — פי ארבעה בשטח,
    ///    ‏682 קילובייט לעמוד במקום כמאתיים. נמדד. ⇒ מפת־סיביות בגודל מפורש.
    private static func render(page: PDFPage) -> Data? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let target: CGFloat = 1400
        let scale = min(target / box.width, 3)
        let pixelsWide = Int((box.width * scale).rounded())
        let pixelsHigh = Int((box.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                         // ⚠ ‏24 סיביות בלי ערוץ־שקיפות אינו הקשר־ציור
                                         //   נתמך; בלי ערוץ רביעי הציור פשוט אינו קורה
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 32) else { return nil }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.setFillColor(NSColor.white.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -box.origin.x, y: -box.origin.y)
        page.draw(with: .mediaBox, to: cg)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }

    private static func mime(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "png":  return "image/png"
        case "gif":  return "image/gif"
        case "webp": return "image/webp"
        case "svg":  return "image/svg+xml"
        case "heic": return "image/heic"
        case "bmp":  return "image/bmp"
        default:     return "image/jpeg"
        }
    }

    /// תיקיית־הנחיתה של מה שמדביקים או גוררים לתוך השיחה.
    static var dropbox: URL {
        Terminals.home.appendingPathComponent(".claude/peach-drops")
    }

    /// שומר תמונה או קובץ שהגיעו מהדפדפן, ומחזיר את הנתיב שאפשר לשלוח למסוף.
    ///
    /// ‏**המסוף מקבל נתיב, לא תמונה.** קלוד־קוד קורא קובץ מהדיסק בעצמו, ולכן
    /// הדבקה נכונה היא: לכתוב את הבתים לקובץ, ולהכניס את שמו לשורת־ההקלדה.
    static func stash(base64: String, name: String) -> String {
        guard let data = Data(base64Encoded: base64) else { return "" }
        try? FileManager.default.createDirectory(at: dropbox, withIntermediateDirectories: true)
        let safe = clean(name)
        let url = dropbox.appendingPathComponent(stamp() + "-" + safe)
        do { try data.write(to: url) } catch { return "" }
        return url.path
    }

    /// שם־קובץ שלא ישבור שורת־פקודה ולא יברח מהתיקייה.
    private static func clean(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        var out = ""
        for ch in base {
            if ch == "/" || ch == "\\" || ch == "\"" || ch == "\u{0}" { continue }
            out.append(ch == " " ? "-" : ch)
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Lang.t("קובץ", "file") : String(trimmed.prefix(60))
    }

    private static let stamper: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private static func stamp() -> String { stamper.string(from: Date()) }

    /// ‏"~/Documents/x.md" → נתיב מלא.
    static func expand(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return Terminals.home.path + String(path.dropFirst())
    }

    /// ‏"/Users/me/Documents/x.md" → "~/Documents/x.md"
    static func shorten(_ path: String) -> String {
        let home = Terminals.home.path
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }

    /// נתיבי־מסמך שמופיעים בתוך טקסט. אלה שהופכים לקישור בשיחה.
    ///
    /// הסורק אינו ביטוי רגולרי אלא מעבר על מילים: נתיב עברי עם רווח לא היה
    /// נתפס בתבנית, ובדיוק שם יושבים המסמכים של המשתמש.
    static func paths(in text: String) -> [String] {
        var found: [String] = []
        for raw in text.split(whereSeparator: { " \n\t\"'`()[]{}<>,;".contains($0) }) {
            var word = String(raw)
            while let last = word.last, ".:!?".contains(last) { word.removeLast() }
            guard word.hasPrefix("/") || word.hasPrefix("~/") else { continue }
            guard kind(of: word) != "other" else { continue }
            guard FileManager.default.fileExists(atPath: expand(word)) else { continue }
            if !found.contains(word) { found.append(word) }
        }
        return found
    }
}
