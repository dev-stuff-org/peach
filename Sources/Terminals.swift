import Foundation

/// מסוף אחד שפתוח כרגע — תהליך קלוד חי שיושב על התקן־מסוף.
struct Terminal {
    /// ‏"/dev/ttys011"
    let tty: String
    /// ‏"011" — מספר־העמדה, מה שנקרא בעין
    let slot: String
    let pid: Int
    /// כמה זמן התהליך רץ, בשניות
    let uptime: TimeInterval
    /// מזהה־השיחה שרשומה על המסוף הזה, אם יש
    let sessionID: String
    /// כותרת חלון־המסוף כפי שהמערכת מכירה אותה — ריק אם אין רשות־אוטומציה
    let windowTitle: String
    /// Claude Code itself says this terminal is blocked on the user
    /// (a question or a permission prompt). From ~/.claude/sessions/<pid>.json.
    /// nil when there is no record (older Claude Code).
    var waiting: Bool? = nil
    /// A background session (`claude --bg`): its short job id, else "".
    /// It runs on a tty with no Terminal window; `claude attach <id>` opens a
    /// window that views it, and when one is open `tty` is that window's.
    var jobId: String = ""
    /// Background and no window open right now.
    var windowless: Bool = false
    /// Claude Code's own status word from sessions/<pid>.json: "busy" ·
    /// "idle" · "waiting" — "" when there is no record.
    var status: String = ""
    /// The name Claude Code holds for the session (/rename), "" if none.
    var recordName: String = ""
}

/// גילוי המסופים הפתוחים, והפעולות עליהם.
///
/// המקור הראשי הוא רשימת־התהליכים: תהליך `claude` שיושב על `ttys` הוא מסוף פתוח.
/// זו קריאה שאינה דורשת שום הרשאה, ולכן היא לעולם לא מתרוקנת בשקט.
/// שם־החלון ופעולת־ההקפצה מגיעים מאוטומציית־המערכת, שדורשת אישור — ולכן הם
/// שכבת־העשרה בלבד. בלעדיהם הרשימה עדיין מלאה ונכונה.
enum Terminals {

    // MARK: - גילוי

    /// ⛔ **נקרא שלוש פעמים בכל סריקה** — מהמדף, מהשיחה וממסך־הצריכה —
    ///    וכל קריאה היא הפעלת `ps` על כל התהליכים במכונה. נמדד: 194 מילישניות
    ///    לקריאה, כלומר כמעט שש־מאיות שנייה בכל פעימה של שנייה וחצי, ובעיקר
    ///    **עיכוב מורגש בכל לחיצה** על שורה במדף.
    ///    ⇒ התוצאה נשמרת לשנייה. רשימת־התהליכים אינה משתנה מהר יותר מזה.
    private static var openCache: [Terminal] = []
    private static var openStamp = Date.distantPast

    /// ⛔ Measured 7.10: a listing cost 1–3 s (two whole-Mac `ps` runs plus
    ///    a Terminal query) and was kept for one second, so nearly every
    ///    1.5 s refresh paid for it again — and a click waited for that.
    /// The last listing whatever its age — for opening a conversation, where
    /// a list from a few seconds ago is as good and waiting for a new one is not.
    static func recent() -> [Terminal] {
        let have: [Terminal] = guarded { openCache }
        return have.isEmpty ? open() : have
    }

    static func open() -> [Terminal] {
        if let fresh: [Terminal] = guarded({
            Date().timeIntervalSince(openStamp) < 2.5 && !openCache.isEmpty ? openCache : nil
        }) { return fresh }
        let found = discover()
        guarded { openCache = found; openStamp = Date() }
        return found
    }

    private static func discover() -> [Terminal] {
        let registry = ttyToSession()
        let official = pidToSession()
        let titles = windowTitles()
        var out: [Terminal] = []
        // One `ps` for both needs: the process (first word of args) and,
        // for `claude attach` viewers, the job it views.
        guard let listing = shell("/bin/ps", ["-axo", "pid=,tty=,etime=,args="]) else { return [] }
        // ⛔ Reported 3.10: terminal 001 "doesn't open and doesn't work". It
        //    was a background session (`claude --bg`): alive, waiting for an
        //    answer, on a tty with no Terminal window — so nothing Peach does
        //    through a window could reach it, and the row never said why.
        //    `claude attach <id>` opens a window that views it (a separate
        //    process). Viewer processes are not rows of their own; their tty
        //    becomes the background session's window.
        var viewers: [String: String] = [:]           // jobId → viewer tty
        var viewerPids: Set<Int> = []
        for line in listing.split(separator: "\n") {
            let p = line.split(separator: " ", omittingEmptySubsequences: true)
            guard p.count >= 5, let pid = Int(p[0]), p[1].hasPrefix("ttys"),
                  let at = p.firstIndex(of: "attach"), at + 1 < p.count,
                  p[3].hasSuffix("claude") else { continue }
            viewers[String(p[at + 1])] = "/dev/" + p[1]
            viewerPids.insert(pid)
        }
        for line in listing.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            // ⛔ The process name is not stable: a native install shows
            //    ".../claude/versions/2.1.274", an npm one shows "node".
            //    Measured 3.10: one live console here was invisible for that
            //    reason. A pid with an official session record is a console.
            guard parts.count >= 4, let pid = Int(parts[0]), !viewerPids.contains(pid) else { continue }
            let comm = String(parts[3])
            guard official[pid] != nil || comm.hasSuffix("claude")
                    || comm.contains("/claude/versions/") else { continue }
            let short = String(parts[1])
            guard short.hasPrefix("ttys") else { continue }
            let dev = "/dev/" + short
            // ⛔ The official record wins. The tty registry is written by a hook
            //    that exists only on the user's Mac — on another MacBook it is
            //    empty, so every terminal had no session and Peach showed no
            //    conversations at all (reported 3.10). It also goes stale on
            //    /clear and on resume, where the official record follows.
            let mine = official[pid]
            let job = mine?.job ?? ""
            // A background session viewed in a window answers on that window.
            let shown = job.isEmpty ? dev : (viewers[job] ?? dev)
            let shownShort = String(shown.dropFirst(5))
            var term = Terminal(tty: shown,
                                slot: String(shownShort.dropFirst(4)),
                                pid: pid,
                                uptime: seconds(fromETime: String(parts[2])),
                                // A background session's tty is reused; only its record names it.
                                sessionID: mine?.id ?? (job.isEmpty ? registry[dev] ?? "" : ""),
                                windowTitle: titles[shown] ?? "",
                                waiting: mine?.waiting)
            term.jobId = job
            term.windowless = !job.isEmpty && viewers[job] == nil
            term.status = mine?.status ?? ""
            term.recordName = mine?.name ?? ""
            out.append(term)
        }
        onScan?()
        return out.sorted { $0.slot < $1.slot }
    }

    /// ‏"20:58:46" או "12:30" או "3-04:12:07" → שניות.
    /// היממות מתווספות **אחרי** צבירת השעות; חיבורן לתוך הצבירה היה מכפיל אותן ב-60.
    private static func seconds(fromETime raw: String) -> TimeInterval {
        var days = 0.0
        var rest = raw
        if let dash = rest.firstIndex(of: "-") {
            days = Double(rest[rest.startIndex..<dash]) ?? 0
            rest = String(rest[rest.index(after: dash)...])
        }
        var clock = 0.0
        for unit in rest.split(separator: ":") { clock = clock * 60 + (Double(unit) ?? 0) }
        return days * 86400 + clock
    }

    // MARK: - רישום־המסופים

    /// Claude Code keeps ~/.claude/sessions/<pid>.json for every live
    /// process: its current session id, and whether it waits on the user.
    /// This is the product's own record — present on any Mac, no hook needed.
    private static func pidToSession() -> [Int: (id: String, waiting: Bool, job: String, status: String, name: String)] {
        let dir = home.appendingPathComponent(".claude/sessions")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [:] }
        var out: [Int: (id: String, waiting: Bool, job: String, status: String, name: String)] = [:]
        for file in items where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["sessionId"] as? String, !id.isEmpty else { continue }
            let pid = (obj["pid"] as? Int) ?? Int(file.deletingPathExtension().lastPathComponent) ?? -1
            let waiting = obj["status"] as? String == "waiting"
            let job = obj["kind"] as? String == "bg" ? (obj["jobId"] as? String ?? "") : ""
            out[pid] = (id, waiting, job, obj["status"] as? String ?? "", obj["name"] as? String ?? "")
        }
        return out
    }

    /// ‏`~/.claude/ttys/<מזהה-שיחה>` מכיל את התקן־המסוף. הכיוון שאנחנו צריכים הפוך,
    /// ומסוף אחד מארח שיחות רבות לאורך הזמן — לכן הרשומה **החדשה ביותר** מנצחת.
    private static func ttyToSession() -> [String: String] {
        let dir = home.appendingPathComponent(".claude/ttys")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [:] }
        var best: [String: (id: String, at: Date)] = [:]
        for file in items {
            guard let dev = try? String(contentsOf: file, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), dev.hasPrefix("/dev/") else { continue }
            let stamp = (try? file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let id = file.lastPathComponent
            if let have = best[dev], have.at >= stamp { continue }
            best[dev] = (id, stamp)
        }
        return best.mapValues { $0.id }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Called after each process listing and each screen scan. The app sets
    /// it to StateFeed.poke; the tools that compile this file leave it nil.
    static var onScan: (() -> Void)?

    // MARK: - שכבת־ההעשרה: אוטומציית־המערכת

    private static var titleCache: [String: String] = [:]
    private static var titleStamp = Date.distantPast
    /// הגילוי רץ בחוט־רקע — המטמון המשותף חייב נעילה.
    /// ‏`withLock` של הספרייה דורש מערכת חדשה יותר מרצפת־הבנייה, ולכן עוטפים ידנית.
    private static let lock = NSLock()
    private static func guarded<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// שמות חלונות־המסוף. נקרא אחת לעשר שניות — כל קריאה היא הפעלת־תסריט מלאה.
    static func windowTitles() -> [String: String] {
        let fresh: [String: String]? = guarded {
            Date().timeIntervalSince(titleStamp) < 10 ? titleCache : nil
        }
        if let fresh { return fresh }
        guarded { titleStamp = Date() }
        let script = """
        tell application "Terminal"
          set out to ""
          repeat with i from 1 to (count of windows)
            try
              set out to out & (tty of tab 1 of window i as text) & tab & (name of window i as text) & linefeed
            end try
          end repeat
          return out
        end tell
        """
        guard let raw = osascript(script, timeout: 4) else { return guarded { titleCache } }
        var found: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            found[parts[0]] = clean(parts[1])
        }
        guarded { titleCache = found }
        return found
    }

    // MARK: - בוררים שפתוחים על המסך

    /// בורר חי, כפי שהוא נראה **על המסך** ולא כפי שנרשם ביומן.
    struct Picker {
        let tty: String
        /// שורת־השאלה כפי שנגרדה מהמסך. ריקה כשלא הצלחנו לקרוא אותה.
        let question: String
        /// האפשרויות כפי שהן על המסך, עם **הספרה שהבורר מצפה לה**.
        /// ⛔ הספרה נלקחת מהמסך ואינה מחושבת. מספור מחושב שנופל בשורה
        ///    אחת שולח את המשתמש לתשובה אחרת לגמרי.
        let options: [Option]
        /// What the session said right above the question — the prose that
        /// explains it. Scraped from the screen, because the transcript does
        /// not hold it yet while the question is open (measured 3.10).
        var context: String = ""
        /// The option number the picker's cursor (❯) sits on right now.
        var cursor: Int = 1
        /// "Type something." — the free-text row's number, when the picker has one.
        var freeRow: Int = 0
        /// A multiSelect question: options carry "[ ]" / "[✔]" boxes, Enter
        /// toggles one, and the row under "Type something" ("Next"/"Submit")
        /// moves on.
        var multi: Bool = false
        /// The "Review your answers / Ready to submit your answers?" screen a
        /// multi-question (or multiSelect) form ends on. It has NO footer, so
        /// the footer test alone never saw it (measured 10.10).
        var review: Bool = false
        /// multiSelect: the option numbers already ticked ("[✔]").
        var checked: Set<String> = []
        /// The lines between the picker's top rule and its question, as on
        /// screen: a permission prompt's "Bash command / rm x / …", or an
        /// AskUserQuestion form's header chips ("☐ Fruit", "←  ☒ A  ☐ B  →").
        var body: [String] = []
    }

    struct Option {
        let n: String
        let label: String
        let detail: String
    }

    /// ⛔ ‏**היומן אינו אות חי.** קלוד־קוד אינו מוסיף הודעה ברגע שנוצרה —
    ///    הוא מרוקן את החוצץ בפרצים, ובתור ארוך ורצוף שום דבר אינו נוחת
    ///    לדיסק. נמדד ‏30.8: בורר היה פתוח על המסך **56 דקות** בזמן שהיומן
    ///    לא הכיל אותו כלל, ובאותו רגע עוד שני מסופים היו במצב זהה.
    ///    ⇒ כל מי שקורא רק את היומן עיוור בדיוק לשאלות שממתינות הכי הרבה.
    ///
    /// ⇒ המסך הוא מקור־האמת ל**קיום** השאלה; היומן נשאר מקור־האמת ל**תוכן**
    ///   שלה — האפשרויות, הכותרות והמזהה, שבלעדיהם אי־אפשר לענות.
    ///
    /// ⚠ ‏**החתימה חייבת להיות המלאה.** ‏"Enter to select" לבדו מופיע בכל
    ///   מסוף שסתם הדפיס את המחרוזת — נמדד על מסוף שהריץ פקודת־בדיקה
    ///   שהכילה אותה, והזיהוי הנאיבי החזיר בורר־רפאים.
    private static var pickerCache: [Picker] = []
    private static var pickerStamp = Date.distantPast
    private static var pickerWorks = false

    /// Terminals whose screen Terminal.app showed in the last scan. A console
    /// running elsewhere — the Claude desktop app, iTerm — is not among them,
    /// and its screen can neither confirm nor contradict anything.
    private static var pickerTTYs: Set<String> = []
    static func screenShows(_ tty: String) -> Bool { guarded { pickerTTYs.contains(tty) } }
    /// Terminal.app window id per tty, from the same scan.
    private static var windowIDs: [String: Int] = [:]
    static func windowID(_ tty: String) -> Int { guarded { windowIDs[tty] ?? 0 } }
    /// The last scan as it stands — never starts a new one. For the state
    /// feed, which must add no scanning of its own.
    static func cachedPickers() -> (list: [Picker], readable: Bool, at: Date) {
        guarded { (pickerCache, pickerWorks, pickerStamp) }
    }

    static func pickers(fresh: Bool = false) -> (list: [Picker], readable: Bool) {
        if !fresh, let cached: ([Picker], Bool) = guarded({
            Date().timeIntervalSince(pickerStamp) < 1.5 ? (pickerCache, pickerWorks) : nil
        }) { return (cached.0, cached.1) }

        // ⛔ ‏`repeat with w in windows` מחזיר **כלום** עבור `contents`.
        //    חייבים אינדקס. ובנוסף, חלון אחד לפחות זורק ‎-10000 — בלי try
        //    לכל חלון בנפרד כל הסריקה נופלת ומחזירה אפס, שנראה בדיוק כמו
        //    ״אין שאלות״ ושולח אותנו לחפש באג במקום הלא־נכון.
        let script = """
        tell application "Terminal"
          set out to ""
          repeat with i from 1 to (count of windows)
            try
              set out to out & "<<T>>" & (tty of selected tab of window i as text) & "|W|" & (id of window i as text) & linefeed
              set out to out & (contents of selected tab of window i as text) & linefeed
            end try
          end repeat
          return out
        end tell
        """
        guard let raw = osascript(script, timeout: 4), !raw.isEmpty else {
            // הסריקה לא רצה — אין רשות־אוטומציה, או שהמסוף לא ענה.
            // ⇒ מחזירים "לא ניתן לקריאה", ולא "אין בוררים".
            guarded { pickerStamp = Date(); pickerCache = []; pickerWorks = false }
            return ([], false)
        }
        var found: [Picker] = []
        var shown: Set<String> = []
        var ids: [String: Int] = [:]
        for chunk in raw.components(separatedBy: "<<T>>").dropFirst() {
            var lines = chunk.components(separatedBy: "\n")
            guard !lines.isEmpty else { continue }
            let head = lines.removeFirst().components(separatedBy: "|W|")
            let dev = head[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard dev.hasPrefix("/dev/") else { continue }
            shown.insert(dev)
            if head.count > 1, let wid = Int(head[1].trimmingCharacters(in: .whitespaces)) { ids[dev] = wid }
            if let picker = parsePicker(lines, tty: dev) { found.append(picker) }
        }
        guarded { pickerStamp = Date(); pickerCache = found; pickerWorks = true; pickerTTYs = shown; windowIDs = ids }
        onScan?()
        return (found, true)
    }

    /// The live picker on one console's screen, or nil. Pure — the screen
    /// text in, the picker out — so tools/pick can run it on a saved screen.
    static func parsePicker(_ lines: [String], tty: String) -> Picker? {
        if let review = scrapeReview(lines, tty: tty) { return review }
        // ⛔ Measured 10.10: a long footer wraps — "… · Esc to" / "cancel" —
        //    and neither half passed the test, so the picker vanished from
        //    Peach. Each line is judged together with the next one.
        guard let foot = lines.indices.last(where: { i in
            isPickerFooter((lines[i] + (i + 1 < lines.count ? " " + lines[i + 1] : ""))
                .replacingOccurrences(of: " +", with: " ", options: .regularExpression))
        }) else { return nil }
        // A footer far above the bottom is scrollback from a picker that
        // already closed, not a live one.
        let below = lines[(foot + 1)...].filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard below.count <= 3 else { return nil }
        let got = scrapePicker(lines, before: foot)
        guard !got.options.isEmpty else { return nil }
        var picker = Picker(tty: tty, question: got.question, options: got.options)
        picker.cursor = got.cursor
        picker.freeRow = got.freeRow
        picker.multi = got.multi
        picker.checked = got.checked
        picker.context = scrapeContext(lines, above: got.top)
        picker.body = scrapeBody(lines, question: got.qLine)
        return picker
    }

    /// שורת־הרגל של הבורר, בשלמותה. שלושת החלקים יחד — לא אחד מהם.
    ///
    /// ⛔ Measured 3.10: tool-permission prompts ("Do you want to proceed?")
    ///    end in "Esc to cancel · Tab to amend" with no "navigate", so the old
    ///    three-part test skipped every one of them. Any footer that offers
    ///    cancel is a picker; the caller still requires numbered options.
    private static func isPickerFooter(_ line: String) -> Bool {
        let low = line.lowercased()
        // ⛔ Measured 10.10 on a throwaway plan-mode session: the plan approval
        //    ("Would you like to proceed? · 1. Yes, and use auto mode · …")
        //    ends in "ctrl+g to edit in Vim · <plan file>", with no "Esc to
        //    cancel" — so Peach never saw it, and the user had nothing to click.
        if low.contains("ctrl+g to edit") { return true }
        guard low.contains("esc to cancel") || low.contains("esc to exit") else { return false }
        return low.contains("enter to") || low.contains("navigate") || low.contains("tab to amend")
            || low.contains("·")
    }

    /// The prose the session wrote just above the picker, as on screen.
    ///
    /// Claude Code marks each block with "⏺". Tool calls look like
    /// "⏺ Name(…)" or "⏺ Agent …"; those are skipped. The nearest prose blocks
    /// above the picker are what the question is about.
    private static func scrapeContext(_ lines: [String], above top: Int) -> String {
        var blocks: [String] = []
        var current: [String] = []
        var i = min(top, lines.count) - 1
        var scanned = 0
        while i >= 0 && scanned < 300 && blocks.count < 2 {
            let raw = lines[i]
            scanned += 1
            i -= 1
            let t = raw.trimmingCharacters(in: .whitespaces)
            // The user's own prompt line ("❯ …" at column 0) is where this
            // turn began. Prose above it belongs to an earlier turn — and an
            // earlier question's subject (measured 10.10: "the post stays
            // unpublished" was read as the context of a fruit question).
            if raw.hasPrefix("❯ ") { break }
            if t.hasPrefix("⏺") {
                let body = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
                current.insert(body, at: 0)
                while current.last == "" { current.removeLast() }
                let tool = body.range(of: "^[A-Za-z_][A-Za-z0-9_ .:-]*\\(", options: .regularExpression) != nil
                let noise = tool || body.hasPrefix("Agent \"") || body.hasPrefix("Remote Control")
                    || body.hasPrefix("Update(") || body.hasPrefix("Read(")
                if !noise { blocks.insert(current.joined(separator: "\n"), at: 0) }
                current.removeAll()
                continue
            }
            // Blank lines sit inside a message; agent pings sit between blocks.
            if t.isEmpty { if !current.isEmpty { current.insert("", at: 0) }; continue }
            if t.hasPrefix("›") || t.hasPrefix("─") { continue }
            // Tool summaries ("Read 1 file, ran 1 shell command") are not prose.
            if t.range(of: "^(Read|Called|Ran|ran|Wrote|Searched|Listed|Edited|Updated) [0-9]",
                       options: .regularExpression) != nil { continue }
            // Continuation lines are indented; anything else ends the block.
            if raw.hasPrefix("  ") && !t.hasPrefix("⎿") && !t.hasPrefix("Called ") && !t.hasPrefix("…") {
                current.insert(t, at: 0)
            } else {
                current.removeAll()
            }
        }
        // ⛔ `contents` is the visible screen only (measured: 42 lines). A
        //    long message starts above it, so its "⏺" is never seen. What is
        //    visible is still the part right above the question — keep it.
        if blocks.isEmpty, i < 0, !current.isEmpty {
            blocks = ["… " + current.joined(separator: "\n")]
        }
        let text = blocks.joined(separator: "\n\n")
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(2500))
    }

    /// השאלה עצמה, מלמעלה לשורת־הרגל. הבורר בנוי כך:
    ///   ‏<שאלה> · 1. אפשרות · 2. אפשרות · … · שורת־רגל
    /// ⇒ עולים עד האפשרות הראשונה, ולוקחים את השורה המלאה שמעליה.
    /// השאלה **והאפשרויות**, מלמעלה לשורת־הרגל. הבורר בנוי כך:
    ///
    ///     <שאלה>
    ///     ❯ 1. תווית          ← החץ מסמן את הנבחרת כרגע
    ///          הסבר
    ///       2. תווית
    ///       …
    ///       5. Type something.
    ///       6. Chat about this
    ///     Enter to select · … · Esc to cancel
    ///
    /// ⛔ ‏**שתי האחרונות אינן אפשרויות שאפשר ללחוץ.** נמדד חי: בחירה
    ///    ב-"Type something" סוגרת את השאלה מיד ובלי טקסט, כי המקש
    ///    שמנווט אליה הוא גם זה שמאשר. ⇒ הן נקראות ולא נמסרות.
    private static func scrapePicker(_ lines: [String], before foot: Int)
        -> (question: String, options: [Option], top: Int, cursor: Int, freeRow: Int,
            multi: Bool, checked: Set<String>, qLine: Int) {
        var cursor = 1
        var freeRow = 0
        var multi = false
        var checked: Set<String> = []
        let low = max(0, foot - 60)
        let box = CharacterSet(charactersIn: "─━│┃┌┐└┘├┤┬┴┼╭╮╰╯═║ \t")
        var opts: [Option] = []
        var details: [String] = []
        var firstOption: Int?

        var i = foot - 1
        while i >= low {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: box)
                       .trimmingCharacters(in: CharacterSet(charactersIn: "❯➤> "))
            if t.isEmpty { i -= 1; continue }
            // שורת־אפשרות: מספר, נקודה, ואז תווית
            if let dot = t.firstIndex(of: "."),
               t.distance(from: t.startIndex, to: dot) <= 2,
               case let num = String(t[t.startIndex..<dot]),
               !num.isEmpty, num.allSatisfy({ $0.isNumber }) {
                var label = String(t[t.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                // multiSelect rows read "[ ] Apple" / "[✔] Apple" (measured 10.10).
                // Without stripping the box, "[ ] Type something" was offered
                // as a clickable answer and the free-text row went unnoticed.
                if let mark = label.range(of: "^\\[[^\\]]{0,2}\\] *", options: .regularExpression) {
                    if label[mark].contains(where: { $0 != "[" && $0 != "]" && $0 != " " }) { checked.insert(num) }
                    label.removeSubrange(mark)
                    multi = true
                }
                if raw.contains("❯") { cursor = Int(num) ?? 1 }
                // The plan prompt's free-text row is "Tell Claude what to change".
                let free = label.hasPrefix("Type something") || label.hasPrefix("Tell Claude what to change")
                if free { freeRow = Int(num) ?? 0 }
                let skip = free || label.hasPrefix("Chat about this")
                if !skip {
                    // ההסברים נאספו בדרך למעלה, ולכן הם הפוכים
                    opts.append(Option(n: num, label: label,
                                       detail: details.reversed().joined(separator: " ")))
                }
                details.removeAll()
                if num == "1" { firstOption = i; break }
                i -= 1
                continue
            }
            details.append(t)
            i -= 1
        }
        opts.reverse()

        // והשאלה עצמה — השורה המלאה הראשונה מעל אפשרות אחת
        var question = ""
        var top = firstOption ?? foot
        var qLine = -1
        if let start = firstOption {
            var j = start - 1
            while j >= low {
                let bare = lines[j].trimmingCharacters(in: box)
                if !bare.isEmpty && !bare.hasPrefix("❯") && bare.count > 1 {
                    question = bare; top = j; qLine = j
                    // A question wrapped over two or three lines ("… Would you
                    // like to" / "proceed?"): take the lines above it too, up
                    // to a rule, a blank, or a form's header chips.
                    var u = j - 1
                    while u >= low && u > j - 3 {
                        let up = lines[u].trimmingCharacters(in: box)
                        if up.isEmpty || up.contains("─") || up.contains("╌")
                            || up.contains("☐") || up.contains("☒") || up.contains("✔") || up.contains("←") { break }
                        question = up + " " + question; top = u; u -= 1
                    }
                    question = String(question.prefix(400))
                    break
                }
                j -= 1
            }
            // The picker sits under a rule line; the prose above it starts there.
            var k = top - 1
            while k >= low && k > top - 6 {
                if lines[k].contains("────") { top = k; break }
                k -= 1
            }
        }
        return (question, opts, top, cursor, freeRow, multi, checked, qLine)
    }

    /// The lines between the nearest rule above the question and the
    /// question itself — a permission prompt's subject, or a form's chips.
    private static func scrapeBody(_ lines: [String], question q: Int) -> [String] {
        guard q > 0 else { return [] }
        var k = q - 1
        let floor = max(0, q - 30)
        while k >= floor && !lines[k].contains("────") { k -= 1 }
        guard k >= floor else { return [] }
        return lines[(k + 1)..<q]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(300)) }
    }

    /// The review screen a multi-question or multiSelect form ends on:
    ///
    ///     Review your answers
    ///      ● Pick a fruit
    ///        → Banana
    ///     Ready to submit your answers?
    ///     ❯ 1. Submit answers
    ///       2. Cancel
    ///
    /// ⛔ Reported 10.10 ("the answer I chose stays in the terminal and cannot
    ///    be sent"), measured the same day on a throwaway session: this screen
    ///    has no "Esc to cancel" footer, so the picker scan skipped it. The
    ///    answers sat there waiting for one Enter, and Peach showed nothing
    ///    to press. It is a picker like any other; its context is the summary.
    private static func scrapeReview(_ lines: [String], tty: String) -> Picker? {
        guard let ready = lines.lastIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("Ready to submit your answers")
        }) else { return nil }
        var opts: [Option] = []
        var cursor = 1
        var last = ready
        for i in (ready + 1)..<min(lines.count, ready + 6) {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "❯➤> "))
            guard let dot = t.firstIndex(of: "."), t.distance(from: t.startIndex, to: dot) <= 2 else {
                if t.isEmpty { continue } else { break }
            }
            let num = String(t[t.startIndex..<dot])
            guard !num.isEmpty, num.allSatisfy({ $0.isNumber }) else { break }
            if lines[i].contains("❯") { cursor = Int(num) ?? 1 }
            opts.append(Option(n: num, label: String(t[t.index(after: dot)...]).trimmingCharacters(in: .whitespaces), detail: ""))
            last = i
        }
        // Live only when it is the bottom of the screen, not scrollback.
        let below = lines[(last + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard below.count <= 3, opts.contains(where: { isSubmit($0.label) }) else { return nil }
        var summary: [String] = []
        if let head = lines[..<ready].lastIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("Review your answers")
        }) {
            summary = lines[(head + 1)..<ready]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        var p = Picker(tty: tty, question: Lang.t("לשלוח את התשובות?", "Ready to submit your answers?"), options: opts)
        p.cursor = cursor
        p.review = true
        p.context = summary.joined(separator: "\n")
        return p
    }

    /// ‏"user — ✳ שם השיחה — claude — 157×41" → "שם השיחה".
    static func clean(_ title: String) -> String {
        var s = title
        for prefix in ["user — ", "user - "] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        while let first = s.first, "✳⠂⠐⠈⠠⢀⡀⠄*· ".contains(first) { s.removeFirst() }
        for suffix in ["— caffeinate ◂ claude", "— claude", "◂ claude"] {
            if let r = s.range(of: suffix) { s = String(s[..<r.lowerBound]) }
        }
        if let r = s.range(of: "—[ ]*[0-9]+×[0-9]+[ ]*$", options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// מקפיץ את חלון־המסוף לחזית. זו הפעולה שמחזירה את המשתמש לעבודה עצמה.
    @discardableResult
    static func raise(tty: String) -> Bool {
        let script = """
        tell application "Terminal"
          repeat with i from 1 to (count of windows)
            try
              if (tty of tab 1 of window i as text) is "\(escape(tty))" then
                set index of window i to 1
                activate
                return "ok"
              end if
            end try
          end repeat
          return "no"
        end tell
        """
        if osascript(script)?.hasPrefix("ok") == true { return true }
        // No window holds this tty: a background session. Open one for it.
        if let bg = open().first(where: { $0.tty == tty && !$0.jobId.isEmpty }) {
            return spawnClaude(cwd: home.path, args: ["attach", bg.jobId]).isEmpty
        }
        return false
    }

    /// מזריק שורת־טקסט לתוך המסוף, ואז שולח אנטר בנפרד.
    ///
    /// ‏**שתי פעולות ולא אחת:** המסוף מפרש טקסט שנכנס בבת־אחת כהדבקה, והשורה
    /// נשארת מוקלדת בלי להישלח. האנטר הנפרד הוא מה שהופך "נכתב" ל"נשלח".
    ///
    /// שורות חדשות נדחסות לרווח — אנטר באמצע היה שולח את ההודעה באמצעה.
    @discardableResult
    static func send(_ text: String, tty: String) -> Bool {
        let one = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !one.isEmpty else { return false }
        guard inject(one, tty: tty) else { return false }
        // ⛔ Measured 3.10: a long line followed by Enter 0.25 s later stayed
        //    in the input box, unsent — terminal 008 showed the user's message
        //    sitting there while Peach had already dropped it as "sent".
        //    ⇒ Wait, then ask Claude Code's own record whether the session
        //      started working; press Enter again only if it did not.
        //    A busy session gives no status change to watch, so the input line
        //    on screen is checked too: the message still sitting there means
        //    the Enter was swallowed.
        let pid = open().first { $0.tty == tty }?.pid
        let wasIdle = pid.map { status(pid: $0) == "idle" } ?? false
        // ⛔ The input box scrolls: a long line shows only its END. Measured
        //    3.10 on a relay test — the start was off-screen, so the check
        //    said "not stuck" while the whole request sat unsent.
        let probe = String(one.suffix(24))
        for attempt in 0..<4 {
            for _ in 0..<4 {
                Thread.sleep(forTimeInterval: 0.6)
                if wasIdle, let pid, status(pid: pid) != "idle" { return true }
                if let stuck = stillTyped(probe, tty: tty), !stuck { return true }
            }
            if attempt < 3 { _ = inject("", tty: tty) }
        }
        return false
    }

    /// Is this text still sitting in the console's input line? nil when the
    /// screen cannot be read (not a Terminal.app window, or no permission).
    /// The input line is the last "❯" line above the bottom rule.
    static func stillTyped(_ probe: String, tty: String) -> Bool? {
        let script = """
        tell application "Terminal"
          repeat with i from 1 to (count of windows)
            try
              if (tty of selected tab of window i as text) is "\(escape(tty))" then return contents of selected tab of window i
            end try
          end repeat
          return "<<none>>"
        end tell
        """
        guard let screen = osascript(script, timeout: 4), screen != "<<none>>" else { return nil }
        let lines = screen.components(separatedBy: "\n")
        guard let prompt = lines.lastIndex(where: { $0.hasPrefix("❯") }) else { return false }
        // The input can wrap over several lines, up to the next rule.
        var box = ""
        var i = prompt
        while i < lines.count && !lines[i].contains("────") { box += lines[i]; i += 1 }
        let flat = box.replacingOccurrences(of: " ", with: "")
        return flat.contains(probe.replacingOccurrences(of: " ", with: ""))
    }

    /// Claude Code's own record of a process: "idle" · "busy" · "waiting".
    static func status(pid: Int) -> String {
        let url = home.appendingPathComponent(".claude/sessions/\(pid).json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return obj["status"] as? String ?? ""
    }

    // MARK: - Answering a picker

    /// ⛔ Reported 10.10: "after choosing an option in Peach, the answer sometimes
    ///    stays in the terminal and cannot be sent." Measured the same day on a
    ///    throwaway Claude Code 2.1.296 session driven through a pty:
    ///
    ///    · `do script` ALWAYS appends a Return: the bytes that reach the
    ///      console are "2\r" in one chunk (logged raw from a throwaway window).
    ///    · In a one-question picker the digit selects and submits, and the
    ///      extra Return is dropped — which is why it usually worked.
    ///    · In a multi-question form the digit answers question 1 and moves to
    ///      question 2, and the extra Return then answers question 2 with
    ///      whatever the cursor sits on. The user's second click went to the wrong
    ///      question, or to nothing.
    ///    · The form then ends on "Review your answers · Ready to submit your
    ///      answers? · 1. Submit answers" — a screen with NO "Esc to cancel"
    ///      footer, so Peach did not see it as a question. The answers sat
    ///      there, unsent, with nothing in Peach to press.
    ///
    /// ⇒ The answer is given the way the picker reads it: arrows from where
    ///   the cursor is to the chosen row, and the Return that `do script` adds
    ///   anyway is the one and only "select". Then the screen is read until the
    ///   picker has moved on; a review screen that our answer opened is
    ///   submitted; and a picker that did not move gets the Return once more.
    ///   All verified on the throwaway session: single, multi-question,
    ///   multiSelect, and multiSelect inside a multi-question form.

    /// What identifies "the same picker" across two screen reads.
    static func signature(_ p: Picker) -> String {
        (p.review ? "R|" : "Q|") + p.question + "|" + p.options.map { $0.label }.joined(separator: "|")
    }

    /// The picker on this console's screen right now (no cache), and whether
    /// the screen could be read at all.
    static func livePicker(_ tty: String) -> (picker: Picker?, seen: Bool) {
        let scan = pickers(fresh: true)
        return (scan.list.first { $0.tty == tty }, scan.readable && screenShows(tty))
    }

    /// Arrow keys from row `from` to row `to`, then `text`. `do script` adds
    /// the Return itself — that Return is the select.
    private static func injectMoves(from: Int, to: Int, text: String = "", tty: String) -> Bool {
        let steps = to - from
        let arrow = steps >= 0 ? "[B" : "[A"
        var parts = Array(repeating: "e & \"\(arrow)\"", count: abs(steps))
        parts.append("\"\(escape(text))\"")
        let script = """
        set e to (ASCII character 27)
        tell application "Terminal"
          repeat with i from 1 to (count of windows)
            try
              if (tty of tab 1 of window i as text) is "\(escape(tty))" then
                do script (\(parts.joined(separator: " & "))) in tab 1 of window i
                return "ok"
              end if
            end try
          end repeat
          return "no"
        end tell
        """
        return osascript(script)?.hasPrefix("ok") == true
    }

    /// The row under "Type something" in a multiSelect question: "Next" in a
    /// form with more questions, "Submit" in a lone one.
    private static func moveOnRow(_ p: Picker) -> Int {
        (p.freeRow > 0 ? p.freeRow : (p.options.compactMap { Int($0.n) }.max() ?? 0)) + 1
    }

    /// Consoles Peach is typing an answer into right now (and for 3 s
    /// after). The pickers our own answer opens on the way — the next
    /// question of a form, its review screen — are not news to anyone.
    private static var answeringUntil: [String: Date] = [:]
    static func answering(_ tty: String) -> Bool { guarded { (answeringUntil[tty] ?? .distantPast) > Date() } }
    private static func markAnswering(_ tty: String, _ on: Bool) {
        guarded { answeringUntil[tty] = on ? .distantFuture : Date().addingTimeInterval(3) }
    }

    /// The review screen's "send" row, in whatever order it is drawn
    /// ("Submit answers", "Submit", "Submit anyway").
    static func isSubmit(_ label: String) -> Bool { label.lowercased().hasPrefix("submit") }

    /// Why the last answer to this console was not sent — shown to the user with
    /// the "not sent" notice, instead of a guess. Reported 10.10: "Peach
    /// doesn't always send answers", and the notice always blamed a missing
    /// permission, whatever the real cause was.
    private static var failures: [String: String] = [:]
    static func failure(_ tty: String) -> String { guarded { failures[tty] ?? "" } }
    private static func fail(_ tty: String, _ he: String, _ en: String) -> Bool {
        guarded { failures[tty] = Lang.t(he, en) }
        return false
    }

    /// The picker once the screen has stopped changing: two reads in a row
    /// with the same question, options and cursor. ⛔ A read taken while the
    /// picker is still being drawn shows half the options or a stale cursor,
    /// and the arrows counted from it land on the wrong row.
    static func stablePicker(_ tty: String, want: ((Picker) -> Bool)? = nil) -> (picker: Picker?, seen: Bool) {
        var last = livePicker(tty)
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = livePicker(tty)
            guard now.seen else { return now }
            if let a = last.picker, let b = now.picker, signature(a) == signature(b), a.cursor == b.cursor,
               want?(b) ?? true { return now }
            last = now
        }
        return last
    }

    /// Chooses option `n` in the picker open on this console.
    static func choose(_ n: String, tty: String) -> Bool {
        markAnswering(tty, true)
        defer { markAnswering(tty, false) }
        guarded { failures[tty] = nil }
        guard let target = Int(n) else { return fail(tty, "תשובה לא תקינה", "Invalid answer") }
        let now = stablePicker(tty) { $0.options.contains(where: { $0.n == n }) }
        guard now.seen else {
            // The screen cannot be read (not a Terminal.app window, or no
            // permission): the cursor is unknown, so the digit is all we have.
            return inject(n, tty: tty) ? true : fail(tty, "לא הצלחתי להגיע לחלון־המסוף", "Could not reach the terminal window")
        }
        // ⛔ A readable screen with no such picker: whatever we type would
        //    land in the prompt line and sit there. Say "not sent" instead.
        guard let p = now.picker else {
            return fail(tty, "השאלה כבר לא פתוחה במסוף — אולי נענתה או בוטלה שם", "The question is no longer open in the terminal — it may have been answered or cancelled there")
        }
        guard p.options.contains(where: { $0.n == n }) else {
            return fail(tty, "במסוף פתוחה עכשיו שאלה אחרת — לא שלחתי כדי לא לענות עליה בטעות", "A different question is open in the terminal now — not sent, so as not to answer it by mistake")
        }
        let before = signature(p)
        if p.multi {
            // Tick the option (unless it already is), then "Next"/"Submit".
            var at = p.cursor
            if !p.checked.contains(n) {
                guard injectMoves(from: p.cursor, to: target, tty: tty) else { return false }
                at = target
                Thread.sleep(forTimeInterval: 0.5)
                if let again = livePicker(tty).picker, signature(again) == before { at = again.cursor }
            }
            guard injectMoves(from: at, to: moveOnRow(p), tty: tty) else { return fail(tty, "לא הצלחתי להקליד בחלון־המסוף", "Could not type into the terminal window") }
            return settle(tty: tty, before: before, review: false) { cur in
                injectMoves(from: cur.cursor, to: moveOnRow(cur), tty: tty)
            }
        }
        guard injectMoves(from: p.cursor, to: target, tty: tty) else { return fail(tty, "לא הצלחתי להקליד בחלון־המסוף", "Could not type into the terminal window") }
        return settle(tty: tty, before: before, review: p.review) { cur in
            injectMoves(from: cur.cursor, to: target, tty: tty)
        }
    }

    /// Answers an open picker in the console's own free-text row.
    ///
    /// ⛔ Pressing the free-text row's digit submits it at once, empty —
    ///    measured again 3.10: "User declined to answer questions". So does
    ///    arrowing to it and pressing Enter. What works, measured the same day
    ///    on a throwaway session (Hebrew included): arrow down to the row,
    ///    type the text, Enter — all in one input stream, the way a person
    ///    does it. The arrow count comes from where the cursor sits now.
    static func answerFree(_ text: String, tty: String) -> Bool {
        markAnswering(tty, true)
        defer { markAnswering(tty, false) }
        guarded { failures[tty] = nil }
        let one = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !one.isEmpty else { return fail(tty, "התשובה ריקה", "The answer is empty") }
        // A picker caught mid-draw may not show its free-text row yet.
        let now = stablePicker(tty) { $0.freeRow > 0 }
        guard let p = now.picker else {
            return fail(tty, "השאלה כבר לא פתוחה במסוף — אולי נענתה או בוטלה שם", "The question is no longer open in the terminal — it may have been answered or cancelled there")
        }
        // ⛔ Measured 10.10 on a throwaway session: in a multi-select question
        //    the typed text lands in the row unticked, and the next Return
        //    declined the whole form ("User declined to answer questions").
        //    No key sequence was found that is safe, so it is not attempted.
        guard !p.multi else {
            return fail(tty, "בשאלה עם בחירה מרובה אי־אפשר לשלוח טקסט חופשי מכאן — לסמן אפשרויות, או לכתוב במסוף", "Free text cannot be sent from here in a multi-select question — tick options, or type it in the terminal")
        }
        guard p.freeRow > 0 else {
            return fail(tty, "לשאלה הזאת אין שורה לטקסט חופשי — לבחור אחת האפשרויות", "This question has no free-text row — pick one of the options")
        }
        guard injectMoves(from: p.cursor, to: p.freeRow, text: one, tty: tty) else { return fail(tty, "לא הצלחתי להקליד בחלון־המסוף", "Could not type into the terminal window") }
        // ⛔ Reported 3.10: the text reached the free-text row but the Enter
        //    was swallowed, as with long messages. Retry is Enter alone, and
        //    only while our text is still visibly sitting in that row.
        let mark = String(one.prefix(12)).replacingOccurrences(of: " ", with: "")
        // ⛔ The typed text replaces "Type something." in the row, so the row
        //    shows up as a new option and the plain signature "changed" — a
        //    swallowed Enter looked like a sent answer. The free row is left
        //    out of the comparison.
        let free = String(p.freeRow)
        let key: (Picker) -> String = { q in
            signature(Picker(tty: q.tty, question: q.question, options: q.options.filter { $0.n != free }))
                + (q.review ? "|R" : "")
        }
        return settle(tty: tty, before: key(p), review: false, key: key) { _ in
            guard let screen = screenText(tty: tty),
                  screen.replacingOccurrences(of: " ", with: "").contains(mark) else { return false }
            return inject("", tty: tty)
        }
    }

    /// Waits for the picker to move on after an answer was keyed in.
    ///
    /// Done is: the picker left the screen, or a different question took its
    /// place. When our answer opened the review screen ("Ready to submit your
    /// answers?"), it is submitted here — the user clicked to send, not to review.
    /// A picker that did not change gets `retry` once, judged on a fresh read
    /// taken right before it, so a slow redraw does not earn a second Enter.
    private static func settle(tty: String, before: String, review: Bool,
                               key: (Picker) -> String = signature,
                               retry: (Picker) -> Bool) -> Bool {
        var retried = false
        var submitted = false
        let start = Date()
        while Date().timeIntervalSince(start) < 9 {
            Thread.sleep(forTimeInterval: 0.5)
            let now = livePicker(tty)
            guard now.seen else { return true }            // cannot judge — trust it
            guard let cur = now.picker else { return true } // answered, picker gone
            if key(cur) != before {
                guard cur.review, !review, !submitted,
                      let submit = cur.options.first(where: { isSubmit($0.label) }),
                      let row = Int(submit.n) else { return true }
                submitted = true
                guard injectMoves(from: cur.cursor, to: row, tty: tty) else { return false }
                return settle(tty: tty, before: signature(cur), review: true, retry: { c in
                    injectMoves(from: c.cursor, to: row, tty: tty)
                })
            }
            if !retried && Date().timeIntervalSince(start) > 2.5 {
                retried = true
                // ⛔ Never a blind second key: a fresh, stable read must still
                //    show the same question, or the Return could land on a
                //    permission prompt that has just replaced it.
                guard let again = stablePicker(tty).picker, key(again) == before else { continue }
                _ = retry(again)
            }
        }
        return fail(tty, "הקלדתי את התשובה, אבל השאלה עדיין פתוחה במסוף אחרי 9 שניות", "The answer was typed, but the question is still open in the terminal after 9 seconds")
    }

    /// Names the Terminal.app window itself. The window belongs to Terminal,
    /// not to the conversation, so this works at once even while the session
    /// is busy or waiting on a question — measured 3.10, and it holds after
    /// Claude Code sets its own title.
    @discardableResult
    static func setWindowTitle(_ name: String, tty: String) -> Bool {
        let script = """
        tell application "Terminal"
          repeat with i from 1 to (count of windows)
            try
              if (tty of tab 1 of window i as text) is "\(escape(tty))" then
                set custom title of tab 1 of window i to "\(escape(name))"
                set title displays custom title of tab 1 of window i to true
                return "ok"
              end if
            end try
          end repeat
          return "no"
        end tell
        """
        return osascript(script)?.hasPrefix("ok") ?? false
    }

    /// Closes the Terminal window that holds this tty, once nothing runs in it.
    static func closeWindow(tty: String) {
        let script = """
        tell application "Terminal"
          repeat with i from (count of windows) to 1 by -1
            try
              if (tty of tab 1 of window i as text) is "\(escape(tty))" then close window i saving no
            end try
          end repeat
        end tell
        """
        _ = osascript(script)
    }

    /// Closes the window holding this tty only when that is its single tab —
    /// never another conversation sharing the window. True when closed.
    @discardableResult
    static func closeLoneWindow(tty: String) -> Bool {
        let script = """
        tell application "Terminal"
          repeat with i from (count of windows) to 1 by -1
            try
              if (count of tabs of window i) is 1 and (tty of tab 1 of window i as text) is "\(escape(tty))" then
                close window i saving no
                return "ok"
              end if
            end try
          end repeat
          return "no"
        end tell
        """
        return osascript(script)?.hasPrefix("ok") == true
    }

    /// The visible screen of one console, or nil when it cannot be read.
    static func screenText(tty: String) -> String? {
        let script = """
        tell application "Terminal"
          repeat with i from 1 to (count of windows)
            try
              if (tty of selected tab of window i as text) is "\(escape(tty))" then return contents of selected tab of window i
            end try
          end repeat
          return "<<none>>"
        end tell
        """
        guard let s = osascript(script, timeout: 4), s != "<<none>>" else { return nil }
        return s
    }

    /// לוחץ מקש אחד בבורר שפתוח במסוף — ספרה, ותו לא.
    ///
    /// ⛔ ‏**זו אינה `send`.** ‏`send` שולחת אנטר **פעמיים**, כי טקסט ארוך
    /// נכנס כהדבקה ונשאר מוקלד בלי להישלח. בבורר האנטר הראשון כבר בוחר —
    /// והשני נחת על השאלה הבאה. נמדד חי: ספרה עם אנטר כפול על
    /// ‏"Type something" פתחה שורת־טקסט ומיד שלחה אותה ריקה, והמסוף רשם
    /// ‏"User declined to answer questions".
    @discardableResult
    static func press(_ key: String, tty: String) -> Bool {
        let one = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !one.isEmpty else { return false }
        return inject(one, tty: tty)
    }

    /// One raw keystroke batch, no Enter of its own — "" sends just Enter.
    static func typeOnly(_ text: String, tty: String) -> Bool {
        inject(text.replacingOccurrences(of: "\n", with: " "), tty: tty)
    }

    private static func inject(_ text: String, tty: String) -> Bool {
        let script = """
        tell application "Terminal"
          repeat with i from 1 to (count of windows)
            try
              if (tty of tab 1 of window i as text) is "\(escape(tty))" then
                do script "\(escape(text))" in tab 1 of window i
                return "ok"
              end if
            end try
          end repeat
          return "no"
        end tell
        """
        return osascript(script)?.hasPrefix("ok") ?? false
    }

    // MARK: - הרצה

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// פותח חלון־מסוף חדש ומפעיל בו שיחת־קלוד.
    ///
    /// ⛔ ‏**דרך `cx` ולא דרך `claude` ישירות.** ‏`cx` מקצה את מזהה־השיחה
    ///    **לפני** ההפעלה ורושם אותו לרשומת־החלונות. חלון שנפתח מתוך סשן
    ///    אחר יורש את מזהה־ההורה בסביבה, והסביבה משקרת — נמדד 17.8:
    ///    שישה חלונות דיווחו אותו מזהה. בלי הרישום הזה המסוף החדש היה
    ///    מופיע במדף בלי שיחה, או גרוע מזה — עם השיחה של מישהו אחר.
    ///
    /// ⚠ ‏**האישור עצמו נשאר אצל המשתמש.** מצב־עקיפת־ההרשאות נפתח במסך־אישור
    ///   שהוא בורר, ופיץ׳ אינו יכול לענות לבורר. לכן מקפיצים את החלון —
    ///   הוא נפתח מולו, והתשובה שם.
    static func spawn(cwd: String, bypass: Bool) -> String {
        let folder = cwd.isEmpty ? home.path : cwd
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir),
              isDir.boolValue else {
            return Lang.t("התיקייה לא נמצאה — ", "Folder not found — ") + folder
        }
        // מרכאות בודדות סביב הנתיב, ומרכאה בתוך הנתיב נסגרת ונפתחת מחדש
        let quoted = "'" + folder.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "cd " + quoted + " && cx"
            + (bypass ? " --dangerously-skip-permissions" : "")
        let script = """
        tell application "Terminal"
          activate
          do script "\(escape(command))"
        end tell
        return "ok"
        """
        guard let answer = osascript(script), answer == "ok" else {
            return Lang.t("פתיחת המסוף נכשלה — בדרך כלל חסר אישור אוטומציה: ", "Opening the terminal failed — usually a missing automation permission: ")
                 + Lang.t("הגדרות המערכת ← פרטיות ואבטחה ← אוטומציה ← פיץ׳ ← מסוף.", "System Settings → Privacy & Security → Automation → Peach → Terminal.")
        }
        return ""
    }

    /// The `claude` command. Peach starts from Finder with a bare PATH, so the
    /// usual install places are checked directly.
    static func claudePath() -> String? {
        let candidates = [
            home.appendingPathComponent(".local/bin/claude").path,
            home.appendingPathComponent(".claude/local/claude").path,
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Opens a new Terminal window running `claude` with these arguments.
    ///
    /// No permission flag is passed: the session starts in the user's default
    /// mode (settings.json), so nothing waits on a confirmation picker —
    /// which an automatic continuation could never answer.
    /// Works without `cx`, so it works on any Mac.
    static func spawnClaude(cwd: String, args: [String]) -> String {
        let folder = cwd.isEmpty ? home.path : cwd
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir),
              isDir.boolValue else {
            return Lang.t("התיקייה לא נמצאה — ", "Folder not found — ") + folder
        }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let binary = claudePath() ?? "claude"
        let command = "unset CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION; cd " + q(folder)
            + " && " + q(binary) + " " + args.map(q).joined(separator: " ")
        let script = """
        tell application "Terminal"
          activate
          do script "\(escape(command))"
        end tell
        return "ok"
        """
        guard let answer = osascript(script), answer == "ok" else {
            return Lang.t("פתיחת המסוף נכשלה — בדרך כלל חסר אישור אוטומציה.", "Opening the terminal failed — usually a missing automation permission.")
        }
        return ""
    }

    /// ⛔ Reported 7.10: "clicking a conversation doesn't open it, or takes a
    ///    whole minute". Every refresh asks Terminal for its window names, and
    ///    an Apple-event to a busy Terminal waits up to two minutes by default
    ///    — with the click queued behind it. ⇒ A question to Terminal that
    ///    has not answered in four seconds is dropped; the last answer stands.
    ///    Only reads take the limit: a send cut halfway could leave text typed
    ///    without its Enter.
    private static func osascript(_ script: String, timeout: TimeInterval = 0) -> String? {
        shell("/usr/bin/osascript", ["-e", script], timeout: timeout)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shell(_ path: String, _ args: [String], timeout: TimeInterval = 0) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        var killer: DispatchWorkItem?
        if timeout > 0 {
            let k = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: k)
            killer = k
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer?.cancel()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
