import Foundation

/// תוצר אחד — קובץ שנוצר תוך כדי עבודה.
struct Work {
    let path: String
    let name: String
    /// ‏"מסמך" · "עמוד" · "תמונה" · "טבלה" · "קוד" · "נייר"
    let kind: String
    /// הפרויקט שהקובץ יושב בו, כפי שהמשתמש מכיר אותו
    let project: String
    let modified: Date
    let size: Int
}

/// סריקת התוצרים תחת תיקיית־קלוד.
///
/// **הסריקה רדודה בכוונה.** עומק חמש מכסה את כל מה שהמשתמש באמת פותח, ואינו
/// נכנס לתיקיות־בנייה שמכילות אלפי קבצים שאיש לא יצר ביד. נמדד: כשלושת
/// אלפים קבצים בשלוש מאיות השנייה.
enum Works {

    private static var root: URL { Paths.workRoot }
    private static let depth = 5
    private static let ceiling = 500

    /// תיקיות שאין בהן תוצרים — רק תוצרי־לוואי של כלים.
    private static let skipDirs: Set<String> = [
        ".git", "node_modules", "build", "dist", "vendor", "__pycache__",
        ".netlify", "backups", ".venv", "Sources", "worktrees"
    ]

    /// ⇒ המילה נגזרת פעם אחת מהשפה הפעילה, ולא בכל שורה שמצוירת.
    private static var kinds: [String: String] {
        let doc   = Lang.t("מסמך", "doc")
        let page  = Lang.t("עמוד", "page")
        let image = Lang.t("תמונה", "image")
        let table = Lang.t("טבלה", "table")
        let paper = Lang.t("נייר", "paper")
        let code  = Lang.t("קוד", "code")
        return [
        "md": doc, "txt": doc, "markdown": doc,
        "html": page, "htm": page,
        "png": image, "jpg": image, "jpeg": image,
        "gif": image, "webp": image, "svg": image,
        "csv": table, "tsv": table, "xlsx": table,
        "pdf": paper, "docx": paper, "pages": paper,
        "py": code, "js": code, "swift": code, "sh": code,
        "php": code, "css": code, "json": code
        ]
    }

    private static let lock = NSLock()
    private static var cache: [Work] = []
    private static var stamp = Date.distantPast

    /// The newest files, for the outputs screen — a list one reads.
    static func all() -> [Work] {
        Array(everything().prefix(ceiling))
    }

    /// Every file under the root, newest first, for the finder — a list one
    /// searches. Reported 7.10: a draft from three weeks ago was simply not
    /// in the newest 500, so no filter could ever find it.
    static func everything() -> [Work] {
        lock.lock()
        let fresh = Date().timeIntervalSince(stamp) < 20 ? cache : nil
        lock.unlock()
        if let fresh { return fresh }

        var found: [Work] = []
        walk(root, at: 0, into: &found)
        let sorted = found.sorted { $0.modified > $1.modified }
        lock.lock(); cache = sorted; stamp = Date(); lock.unlock()
        return sorted
    }

    static func row(_ w: Work) -> [String: Any] { Panel.workRow(w) }

    /// The path below ~/Documents/claude — what the finder matches words against.
    static func relative(_ path: String) -> String {
        path.hasPrefix(root.path + "/") ? String(path.dropFirst(root.path.count + 1)) : path
    }

    /// The folder a file sits in, below the root; empty at the root itself.
    static func folder(_ path: String) -> String {
        let rel = relative(path)
        let dir = (rel as NSString).deletingLastPathComponent
        return dir
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d.M.yy"
        return f
    }()

    private static func walk(_ dir: URL, at level: Int, into out: inout [Work]) {
        guard level <= depth else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey,
                                                  .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return }

        for item in items {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey,
                                                            .contentModificationDateKey,
                                                            .fileSizeKey])
            if values?.isDirectory == true {
                guard !skipDirs.contains(item.lastPathComponent) else { continue }
                walk(item, at: level + 1, into: &out)
                continue
            }
            let ext = item.pathExtension.lowercased()
            guard let kind = kinds[ext] else { continue }
            out.append(Work(path: item.path,
                            name: item.lastPathComponent,
                            kind: kind,
                            project: project(of: item),
                            modified: values?.contentModificationDate ?? .distantPast,
                            size: values?.fileSize ?? 0))
        }
    }

    /// שם־הפרויקט הוא התיקייה שמתחת לשורש. תיקיית־האוסף "פרויקטים" אינה
    /// שם של שום דבר, ולכן יורדים בה עוד רמה.
    private static func project(of file: URL) -> String {
        let full = file.deletingLastPathComponent().path
        let base = root.path
        guard full.hasPrefix(base) else { return "" }
        let rest = String(full.dropFirst(base.count)).split(separator: "/").map(String.init)
        guard let first = rest.first else { return Lang.t("שורש", "root") }
        if first == Lang.t("פרויקטים", "projects"), rest.count > 1 { return rest[1] }
        return first
    }
}
