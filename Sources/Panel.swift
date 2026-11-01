import Foundation

/// הרכבת השורות שהמסך מצייר: מסוף פתוח + השיחה שרצה בו.
enum Panel {

    /// המדף מסודר לפי מה שקורה, לא לפי מספר־העמדה: קודם מי שעובד, אחריו מי
    /// שממתין לך, ובסוף הדוממים — ובתוך כל קבוצה, האחרון שזז ראשון.
    ///
    /// הסדר הקבוע לפי מספר היה נכון למדף־מכשירים ושגוי כאן: השיחה שאתה עובד
    /// בה ברגע זה נחתה בתחתית המסך, ודווקא היא זו שמסתכלים עליה.
    private static func rank(_ state: String) -> Int {
        switch state {
        // שאלה חוסמת מסוף שלם עד שעונים לה, ולכן היא הראשונה במדף
        case "ask":  return 0
        case "run":  return 1
        case "wait": return 2
        case "muted": return 4
        default:     return 3
        }
    }

    // MARK: - שאלות שנשאלו במסופים

    /// שאלה פתוחה בצורה שהדף יודע לצייר.
    static func askPayload(_ ask: PendingQuestion, tty: String) -> [String: Any] {
        var out: [String: Any] = [
            "id": ask.toolID,
            "sid": ask.sid,
            "tty": tty,
            "kind": ask.kind,
            "since": age(since: ask.since, fallback: 0),
            "context": ask.context
        ]
        if ask.kind == "plan" {
            out["head"] = Lang.t("אישור תוכנית", "Plan approval")
            out["plan"] = ask.plan
            // ⛔ No buttons from the transcript alone. These used to be a fixed
            //    "1 Yes, start · 2 No, let's talk" — and on 2.1.312 digit 2 is
            //    "Yes, manually approve edits": "No" would have approved the plan.
            //    The digits exist only on the screen; without it, the card says
            //    where to answer and the page offers to open the terminal.
            out["parts"] = [[
                "question": Lang.t("התוכנית ממתינה לאישור במסוף", "The plan is waiting for approval in the terminal"),
                "header": Lang.t("תוכנית", "plan"),
                "multi": false,
                "free": 0,
                "choices": [] as [[String: Any]]
            ]]
            return out
        }
        out["head"] = ask.parts.first?.header ?? Lang.t("שאלה", "question")
        // ⛔ הבורר שבמסוף ממוספר, והמקש שנשלח הוא **הספרה** ולא התווית.
        //    נמדד חי: הזרקת "2" בחרה בכחול, והתשובה נחתה ביומן. הזרקת
        //    התווית עצמה הייתה נוחתת כטקסט־חופשי — כלומר תשובה אחרת.
        //    ⚠ ומיד אחרי האפשרויות יושבת "Type something", ולכן
        //    מספר־הטקסט־החופשי הוא מספר האפשרויות ועוד אחת.
        out["parts"] = ask.parts.map { part in
            [
                "question": part.question,
                "header": part.header,
                "multi": part.multi,
                "free": part.choices.count + 1,
                "choices": part.choices.enumerated().map {
                    ["label": $0.element.label, "detail": $0.element.detail, "n": "\($0.offset + 1)"]
                }
            ] as [String: Any]
        }
        return out
    }

    /// כל השאלות שממתינות במסופים הפתוחים — התור שנפתח ב-⌘I.
    /// Taken down by hand and unchanged since ⇒ it is not "asking you"
    /// anywhere: not in the strip, not in the queue, not in the counters.
    static func muted(_ term: Terminal, card: [String: Any]?) -> Bool {
        let q = (card?["parts"] as? [[String: Any]])?.first?["question"] as? String ?? ""
        let stamp = Muted.stamp(event: Sessions.state(id: term.sessionID)?.lastEvent, ask: q)
        return Muted.isMuted(term.sessionID, stamp: stamp)
    }

    static func liveAsks() -> [[String: Any]] {
        Terminals.open().compactMap { term in
            guard var row = liveAsk(term), !muted(term, card: row) else { return nil }
            row["slot"] = term.slot
            let session = Sessions.state(id: term.sessionID)
            row["title"] = title(term: term, session: session)
            row["path"] = short(session?.cwd ?? "")
            return row
        }
    }

    /// מי שואל אותך **במסוף אחר**, בזמן שאתה קורא שיחה.
    ///
    /// ⛔ ‏**נמדד, ‏30.8:** שאלה נפתחה ב-10:12:36 ופיץ׳ הבחין בה ב-10:17:05 —
    ///    ‏**ארבע דקות ו-29 שניות** שבהן היא הייתה פתוחה ובלתי־נראית. הסיבה
    ///    אינה בפרסר ואינה במטמון: שניהם נבדקו והם תקינים. הסיבה היא ש-
    ///    ‏`units()` כלל אינו מחושב כשיש שיחה פתוחה, ולכן אף שאלה במסוף אחר
    ///    אינה **נשאלת** — לא נשאלת ולא נענית, פשוט לא מחושבת.
    ///    ⇒ מי שיושב בתוך שיחה עיוור לכל השאר, כל עוד הוא שם.
    ///
    /// ⭑ זו הרשימה הרזה בכוונה: רק מי ששואל, בלי מצב, בלי צריכה ובלי
    ///   כותרות. העלות היא קריאת־זנב אחת למסוף, ורובן נחסכות במטמון.
    /// שאלה שרואים על המסך ואין לה עדיין שורה ביומן.
    ///
    /// ⭑ ‏**זו אינה גרסה מדוללת — זה אותו כרטיס בדיוק.** האפשרויות והספרות
    ///   נקראות מהמסך, ופיץ׳ עונה לבורר בשליחת ספרה. ⇒ לחיצה כאן עונה
    ///   באמת, בלי לפתוח את המסוף.
    ///
    /// ⛔ הספרה נלקחת **מהמסך** ואינה מחושבת מהסדר. מספור מחושב שנופל
    ///    בשורה אחת בוחר תשובה אחרת לגמרי.
    static func screenAsk(_ p: Terminals.Picker, tty: String) -> [String: Any] {
        [
            "id": "",
            "sid": "",
            "tty": tty,
            "kind": "ask",
            "since": "",
            "unwritten": true,
            "context": p.context,
            "head": Lang.t("שואל אותך", "asking you"),
            "freeRow": p.freeRow,
            "parts": [[
                "question": p.question.isEmpty
                    ? Lang.t("שאלה פתוחה במסוף", "A question is open in the terminal")
                    : p.question,
                "header": Lang.t("שאלה", "question"),
                "multi": p.multi,
                "free": 0,
                "choices": p.options.map {
                    ["label": $0.label, "detail": $0.detail, "n": $0.n] as [String: Any]
                }
            ]] as [[String: Any]]
        ]
    }

    static func alerts(excluding sid: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for term in Terminals.open() where term.sessionID != sid {
            guard let card = liveAsk(term), !muted(term, card: card) else { continue }
            let part = (card["parts"] as? [[String: Any]])?.first
            var head = part?["header"] as? String ?? ""
            if head.isEmpty || card["unwritten"] as? Bool == true { head = card["head"] as? String ?? "" }
            let text = card["kind"] as? String == "plan"
                ? Lang.t("מבקש אישור לתוכנית", "asking to approve a plan")
                : (part?["question"] as? String ?? "")
            out.append([
                "sid": term.sessionID, "tty": term.tty, "slot": term.slot,
                "head": head, "question": text
            ])
        }
        return out
    }

    /// The one question a terminal is asking right now, as a card.
    ///
    /// ⛔ Measured 3.10: of 58 questions asked over five days the transcript
    ///    held 6 while they were open. Claude Code writes the question block
    ///    — and the prose above it — only once it is answered. And a question
    ///    abandoned a week ago (session resumed elsewhere) stays "open" in the
    ///    transcript forever: terminal 020 showed a 27.9 question while its
    ///    screen asked a different one, and a click would have sent a digit to
    ///    the wrong picker.
    ///    ⇒ The screen decides. The transcript is used only when the screen
    ///      cannot be read, or to enrich a card that the screen confirms.
    static func liveAsk(_ term: Terminal) -> [String: Any]? {
        guard var card = resolveAsk(term) else { return nil }
        // Answer buttons type into a window; a background session has none.
        if term.windowless { card["windowless"] = true }
        // Files named in the explanation (a preview image, a draft) open inside
        // the card. Reported 3.10: conversation 20 described a post preview
        // and named its image, and the card showed only the file's name as text.
        card["paths"] = Documents.paths(in: card["context"] as? String ?? "")
        return card
    }

    private static func resolveAsk(_ term: Terminal) -> [String: Any]? {
        let scan = Terminals.pickers()
        let ask = Questions.pending(sessionID: term.sessionID)
        // ⛔ Reported 3.10 (terminal 004, inside the Claude desktop app): the
        //    transcript held the question, but there is no Terminal.app screen
        //    to read, so the screen-first rule drew an empty card. Where the
        //    screen cannot be seen, it is not a witness.
        let visible = scan.readable && Terminals.screenShows(term.tty)
        guard visible, let seen = scan.list.first(where: { $0.tty == term.tty }) else {
            // The screen shows no picker for this terminal (or cannot be read,
            // or the terminal lives outside Terminal.app). Claude Code's own
            // record is then the judge: a transcript question in a terminal
            // that is not waiting is stale, and a waiting terminal with no
            // readable picker still asks — say so, and offer to open it.
            switch term.waiting {
            case .some(false): return nil
            case .some(true):
                // A transcript question is trusted only when the screen cannot
                // contradict it; otherwise it may be last week's.
                if !visible, let ask { return askPayload(ask, tty: term.tty) }
            case .none:
                // No official record: the old behaviour — transcript if the
                // screen is unreadable, nothing if the screen says no picker.
                guard !visible, let ask else { return nil }
                return askPayload(ask, tty: term.tty)
            }
            return screenAsk(Terminals.Picker(tty: term.tty, question: "", options: []), tty: term.tty)
        }
        // ⛔ Reported 28.10: "Peach can't read plan mode". The screen held the
        //    plan prompt and Peach drew it as a bare question — two "Yes"
        //    buttons and no plan. The buttons and their digits come from the
        //    screen; the plan itself only from the transcript.
        if StateFeed.isPlan(seen) {
            var card = screenAsk(seen, tty: term.tty)
            card["kind"] = "plan"
            card["head"] = Lang.t("אישור תוכנית", "Plan approval")
            if let ask, ask.kind == "plan" {
                card["id"] = ask.toolID
                card["sid"] = ask.sid
                card["since"] = age(since: ask.since, fallback: 0)
                card["plan"] = ask.plan
                if !ask.context.isEmpty { card["context"] = ask.context }
            }
            return card
        }
        if let ask, ask.kind == "ask", let first = ask.parts.first,
           !seen.question.isEmpty, first.question.hasPrefix(String(seen.question.prefix(30))) {
            var card = askPayload(ask, tty: term.tty)
            if (card["context"] as? String ?? "").isEmpty { card["context"] = seen.context }
            card["freeRow"] = seen.freeRow
            return card
        }
        return screenAsk(seen, tty: term.tty)
    }

    /// מיפוי התקן־מסוף ⇐ טקסט־השאלה, מסריקת־המסך. ריק כשאין רשות־אוטומציה.
    private static func onScreen() -> [String: Terminals.Picker] {
        let scan = Terminals.pickers()
        guard scan.readable else { return [:] }
        var map: [String: Terminals.Picker] = [:]
        for p in scan.list { map[p.tty] = p }
        return map
    }

    static func units() -> [[String: Any]] {
        let terms = Terminals.open()
        let rows = terms.map { term in
            let session = Sessions.state(id: term.sessionID)
            let mode = session?.mode ?? .quiet
            var row: [String: Any] = [
                "tty": term.tty,
                "sid": term.sessionID,
                "slot": term.slot,
                "state": code(mode),
                "stateLabel": label(mode),
                "title": title(term: term, session: session),
                "say": say(mode: mode, session: session),
                "path": short(session?.cwd ?? ""),
                "age": age(since: session?.lastEvent, fallback: term.uptime),
                "model": session?.model ?? "",
                "agents": session?.agentsRunning ?? 0,
                // זמן־התנועה האחרון, למיון בלבד
                "moved": session?.lastEvent.timeIntervalSince1970 ?? 0,
                // "continued in 021" / "continues 017" — the 600k relay
                "chain": Relay.label(for: term.sessionID, terms: terms),
                // "ready" ⇒ the row offers "continue in a new conversation"
                "relay": Relay.stage(for: term.sessionID),
                "relayAgents": Relay.stage(for: term.sessionID).isEmpty ? 0 : Relay.agents(for: term.sessionID),
                "relayShell": Relay.stage(for: term.sessionID).isEmpty ? false : Relay.shellOut(for: term.sessionID)
            ]
            // ⛔ מסוף ששואל אינו "ממתין לך" סתם — יש מה לענות, ובלחיצה אחת.
            //    בלי הסימן הזה השאלה נבלעה בשורת־המשנה ואיש לא ידע שהיא שם.
            // ⛔ מסוף ששואל אינו "ממתין לך" סתם — יש מה לענות, ובלחיצה אחת.
            if let card = liveAsk(term) {
                row["ask"] = card
                row["state"] = "ask"
                row["stateLabel"] = card["kind"] as? String == "plan"
                    ? Lang.t("מבקש אישור", "wants approval") : Lang.t("שואל אותך", "asking you")
            }
            // A background session with no window: say so, plainly.
            if term.windowless {
                row["windowless"] = true
                row["say"] = Lang.t("רץ ברקע, בלי חלון. ״לחלון״ פותח לו חלון.",
                                    "Running in the background with no window. \"To window\" opens one.")
            }
            // A process Claude Code keeps no record of: not answering.
            if term.waiting == nil && term.sessionID.isEmpty {
                row["state"] = "quiet"
                row["stateLabel"] = Lang.t("לא מגיב", "not responding")
                row["say"] = Lang.t("אין לקלוד־קוד רישום של התהליך הזה. כנראה נתקע או נסגר.",
                                    "Claude Code keeps no record of this process. It is probably stuck or gone.")
            }
            // Taken down by hand: stays at the bottom until something changes.
            let askKey = ((row["ask"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["question"] as? String ?? ""
            let stamp = Muted.stamp(event: session?.lastEvent, ask: askKey)
            row["stamp"] = stamp
            if Muted.isMuted(term.sessionID, stamp: stamp) { row["muted"] = true }
            // ⇒ הצריכה של השיחה עצמה, כאן ולא רק במסך־הצריכה. מספר שיושב
            //   במסך נפרד אינו נקרא, ומספר שיושב בשורה נקרא בלי לבקש אותו.
            let burn = Spend.session(term.sessionID)
            row["share"] = burn.share
            row["output"] = burn.output
            if let tokens = session?.contextTokens, tokens > 0 {
                row["context"] = tokens >= 1000 ? "\(tokens / 1000)k" : "\(tokens)"
                // ⛔ ‏**חלון־ההקשר אינו נרשם ביומן** — נבדק, אין שם שדה כזה.
                //    ⇒ מניחים מיליון ואומרים זאת. שיחה עם חלון קטן יותר
                //      מתכווצת הרבה לפני 750 אלף, ולכן הסימן פשוט לא יידלק
                //      אצלה. אזהרת־חסר, לעולם לא אזהרת־שווא.
                row["full"] = Relay.fill(tokens)
                // "warn" at ask−5 points, "ask" at the hand-off line (menu).
                row["ctxLevel"] = Relay.level(tokens)
            } else {
                row["context"] = ""
                row["full"] = 0
            }
            return row
        }
        return rows.sorted { a, b in
            let ra = a["muted"] as? Bool == true ? rank("muted") : rank(a["state"] as? String ?? "")
            let rb = b["muted"] as? Bool == true ? rank("muted") : rank(b["state"] as? String ?? "")
            if ra != rb { return ra < rb }
            let ta = a["moved"] as? Double ?? 0, tb = b["moved"] as? Double ?? 0
            if ta != tb { return ta > tb }
            return (a["slot"] as? String ?? "") < (b["slot"] as? String ?? "")
        }
    }

    /// מסך־הצריכה. שמות השיחות הפתוחות נמסרים כדי ששורה של מסוף שרץ עכשיו
    /// תישא את שמו ולא רק את שם־הפרויקט.
    static func spend() -> [String: Any] {
        var live: [String: String] = [:]
        for term in Terminals.open() where !term.sessionID.isEmpty {
            live[term.sessionID] = title(term: term, session: Sessions.state(id: term.sessionID))
        }
        var out = Spend.board(live: live)
        // ⛔ שיחה שנסגרה קיבלה את שם־הפרויקט בלבד, ולכן חמש שורות "בית" זו
        //    מתחת לזו. הכותרת יושבת ביומן שלה, וכאן זה המקום לשלוף אותה.
        for key in ["today", "week", "all"] {
            guard var window = out[key] as? [String: Any],
                  var rows = window["sessions"] as? [[String: Any]] else { continue }
            for i in rows.indices where !(rows[i]["open"] as? Bool ?? false) {
                let sid = rows[i]["sid"] as? String ?? ""
                if let named = Sessions.state(id: sid)?.title, !named.isEmpty {
                    rows[i]["title"] = named
                }
            }
            window["sessions"] = rows
            out[key] = window
        }
        out["quota"] = Quota.payload()
        // ⇒ השרת אומר כמה אחוז מהחלון נצרך; היומנים אומרים מה נשרף בו בפועל.
        //   שני הצדדים של אותו חלון, ולכן אותם גבולות בדיוק.
        if let reset = Quota.read().rows.first(where: { $0.kind == "session" })?.resets {
            out["windowNow"] = Spend.window(from: reset.addingTimeInterval(-5 * 3600), to: reset)
        }
        return out
    }

    /// קוד־המצב שהדף מסתמך עליו לצבע ולספירה. הוא **חייב** להיות זהה למחלקות
    /// שבגיליון־הסגנון — שם ארוך אחר צובע נכון בעברית ומשאיר את המונים על אפס.
    private static func code(_ mode: SessionState.Mode) -> String {
        switch mode {
        case .working: return "run"
        case .waiting: return "wait"
        case .quiet:   return "quiet"
        }
    }

    // MARK: - סוכנים

    /// שורה של סוכן, בצורה שהדף מצייר.
    static func agentRow(_ agent: Agent) -> [String: Any] {
        [
            "id": agent.id,
            "sid": agent.sid,
            "chat": agent.chat,
            "kind": agent.kind,
            "task": agent.task.isEmpty ? Lang.t("בלי תיאור", "no description") : agent.task,
            "model": agent.model,
            "state": agent.running ? "run" : "quiet",
            "stateLabel": agent.running ? Lang.t("רץ", "running") : Lang.t("הסתיים", "done"),
            "age": age(since: agent.updated, fallback: 0),
            "since": since(agent.started),
            "doing": agent.doing,
            "say": agent.say,
            "steps": agent.steps,
            "context": agent.context >= 1000 ? "\(agent.context / 1000)k" : "",
            "depth": agent.depth
        ]
    }

    /// כמה זמן הסוכן רץ — משך, לא "לפני".
    private static func since(_ start: Date) -> String {
        let seconds = Int(max(0, Date().timeIntervalSince(start)))
        if seconds < 60 { return Lang.t("\(seconds) שנ׳", "\(seconds)s") }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: "%d:%02d", minutes, seconds % 60) }
        return String(format: Lang.t("%d:%02d שע׳", "%d:%02dh"), minutes / 60, minutes % 60)
    }

    static func agents() -> [[String: Any]] {
        Agents.all(for: Terminals.open()).map { agentRow($0) }
    }

    // MARK: - ספר־היכולות

    /// כל מה שהמסוף יודע לעשות, מקובץ למשפחות.
    ///
    /// **הקיבוץ נגזר מהשמות ולא נכתב ביד.** משפחה היא כל תחילית שחוזרת
    /// בשניים ומעלה — כך סקיל שנוסף מחר נכנס למשפחה שלו מעצמו, ורשימה
    /// שנכתבה ביד לא מתיישנת בשקט.
    static func book() -> [[String: Any]] {
        let all = Commands.all()

        var families: [String: [Command]] = [:]
        var order: [String] = []
        for command in all where command.kind == Lang.t("סקיל", "skill") {
            let family = command.name.split(separator: "-").first.map(String.init) ?? command.name
            if families[family] == nil { order.append(family) }
            families[family, default: []].append(command)
        }

        var groups: [[String: Any]] = []

        func add(_ title: String, _ rows: [Command]) {
            guard !rows.isEmpty else { return }
            groups.append([
                "title": title,
                "rows": rows.map { ["name": $0.name, "kind": $0.kind,
                                    "hint": $0.hint.isEmpty ? Lang.t("בלי תיאור", "no description") : $0.hint] }
            ])
        }

        add(Lang.t("סוכנים", "agents"), all.filter { $0.kind == Lang.t("סוכן", "agent") })
        add(Lang.t("פקודות משלך", "Your own commands"), all.filter { $0.kind == Lang.t("פקודה", "command") })

        var loose: [Command] = []
        for family in order.sorted() {
            let rows = families[family] ?? []
            if rows.count >= 2 { add(Lang.t("משפחת ", "family ") + family, rows) } else { loose.append(contentsOf: rows) }
        }
        add(Lang.t("סקילים בודדים", "Individual skills"), loose.sorted { $0.name < $1.name })
        add(Lang.t("פקודות מובנות במסוף", "Built-in terminal commands"), all.filter { $0.kind == Lang.t("מובנית", "built-in") })

        return groups
    }

    // MARK: - תוצרים

    static func works() -> [String: Any] {
        let rows = Works.all()
        var projects: [String] = []
        for row in rows where !projects.contains(row.project) { projects.append(row.project) }
        return ["rows": rows.map(workRow), "projects": projects.sorted()]
    }

    static func workRow(_ work: Work) -> [String: Any] {
        let age = Date().timeIntervalSince(work.modified)
        return [
            "path": work.path,
            "name": work.name,
            "kind": work.kind,
            "project": work.project,
            "folder": Works.folder(work.path),
            "age": self.age(since: work.modified, fallback: 0),
            "size": size(work.size),
            // חלון־זמן לסינון: היום, השבוע, החודש
            "span": age < 86_400 ? "day" : (age < 604_800 ? "week"
                  : (age < 2_592_000 ? "month" : "old"))
        ]
    }

    private static func size(_ bytes: Int) -> String {
        if bytes < 1024 { return Lang.t("\(bytes)ב", "\(bytes)B") }
        if bytes < 1_048_576 { return "\(bytes / 1024)K" }
        return String(format: "%.1fM", Double(bytes) / 1_048_576)
    }

    // MARK: - שאלות פתוחות

    static func asks() -> [[String: Any]] {
        Asks.all().map { ask in
            [
                "id": ask.id,
                "urgency": ask.urgency,
                "title": ask.title,
                "asker": ask.asker,
                "since": ask.since,
                "cost": ask.cost,
                "body": ask.body,
                "answer": ask.answer,
                "answered": !ask.answer.isEmpty
            ]
        }
    }

    // MARK: - שחזור שיחות

    /// ⛔ ‏**פיץ׳ אינו מדרג שיחות בעצמו.** המנוע הוא `tabs-restore.sh`, והוא
    ///   מדרג לפי ההודעה האחרונה **בתוך** התמליל — לא לפי זמן־שינוי של
    ///   הקובץ, שמשקר: מגע המוני בקבצים מתים מחתים עשרות מהם באותה דקה
    ///   ומעלה אותם לראש הרשימה. שני מקומות שיודעים לדרג = שניים שיטעו.
    static let restoreTool = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/bin/tabs-restore.sh").path

    /// השיחות שאפשר להחזיר למסך. שיחות שכבר פתוחות מסוננות אצל הסקריפט.
    static func restorable(hours: Int = 168, limit: Int = 12) -> [[String: Any]] {
        guard FileManager.default.isExecutableFile(atPath: restoreTool),
              let out = Terminals.shell("/bin/bash",
                  [restoreTool, "--json", "--recent", "\(hours)", "--limit", "\(limit)"]),
              let data = out.data(using: .utf8),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        return rows
    }

    /// מחזיר חלון לכל שיחה שנבחרה.
    ///
    /// ⚠ ‏**חוסם שניות ארוכות** — הסקריפט מרווח שמונה שניות בין חלון לחלון
    ///   ואז מאמת שכל אחד עלה. הרווח אינו נימוס: פתיחה בהפרש שלוש שניות
    ///   נמדדה כהורגת שתיים מכל חמש, בלי שגיאה ובלי דוח־קריסה.
    ///   ⇒ הקריאה חייבת לרוץ מחוץ לחוט הראשי.
    @discardableResult
    static func restore(_ sids: [String]) -> Bool {
        // מזהה־שיחה הוא הקסה ומקפים בלבד. מה שאינו כזה לא מגיע לצדפה.
        let clean = sids.filter { sid in
            !sid.isEmpty && sid.count <= 64 && sid.allSatisfy { $0.isHexDigit || $0 == "-" }
        }
        guard !clean.isEmpty,
              FileManager.default.isExecutableFile(atPath: restoreTool) else { return false }
        return Terminals.shell("/bin/bash",
            [restoreTool, "--sids", clean.joined(separator: " ")]) != nil
    }

    // MARK: - היסטוריית־הקלדה

    /// ההודעות שהמשתמש כתב בשיחה, מהאחרונה לראשונה. זו היסטוריית־השורה של
    /// המסוף: חץ־למעלה מחזיר את מה שאמרת קודם, בלי לחפש אותו בעין.
    static func history(sessionID: String) -> [String] {
        var out: [String] = []
        for line in Transcript.lines(sessionID: sessionID).reversed()
        where line.role == "you" {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, out.last != text else { continue }
            out.append(text)
            if out.count >= 30 { break }
        }
        return out
    }

    // MARK: - מסך־השיחה

    /// השיחה של מסוף אחד, מוכנה לציור. `pending` הן הודעות שנשלחו מכאן
    /// ועדיין לא הופיעו ביומן — בלעדיהן ההודעה נעלמת לרגע אחרי השליחה.
    /// שיחה נפתחת לפי **מזהה־השיחה**, לא לפי מסוף: תוצאת־חיפוש עשויה להצביע
    /// על שיחה שהמסוף שלה כבר נסגר, ואותה עדיין רוצים לקרוא.
    static func chat(sessionID: String, pending: [String], want: Int) -> [String: Any]? {
        guard !sessionID.isEmpty else { return nil }
        let term = Terminals.recent().first(where: { $0.sessionID == sessionID })
        let session = Sessions.state(id: sessionID)
        guard term != nil || session != nil else { return nil }
        let mode = session?.mode ?? .quiet

        var askOnScreen = ""
        var screenCard: [String: Any]? = nil
        let reading = Transcript.read(sessionID: sessionID, want: want)
        var lines: [[String: Any]] = reading.lines.map { line in
            ["role": line.role, "text": line.text, "arg": line.arg,
             "when": hhmm.string(from: line.time),
             "ts": line.time.timeIntervalSince1970,
             // נתיבים שקיימים בפועל — רק הם הופכים לקישור שפותח מסמך
             "paths": line.role == "tool" ? [] : Documents.paths(in: line.text)]
        }
        // הודעה שכבר נחתה ביומן אינה מוצגת פעמיים
        let landed = Set(lines.compactMap { $0["role"] as? String == "you" ? $0["text"] as? String : nil })
        for text in pending where !landed.contains(text) {
            lines.append(["role": "you", "text": text, "arg": "", "when": "",
                          "paths": Documents.paths(in: text), "pending": true])
        }

        // ⛔ ‏**גם השיחה שפתוחה מולך צריכה את המסך, ולא רק היומן.**
        //    נמדד 30.8: המשתמש ישב בתוך שיחה 010, המסוף שלה הציג בורר פתוח,
        //    ופיץ׳ הראה ״עובד״ — כי היומן קפא באמצע תור ארוך.
        //    ⚠ והרצועה שמזהירה על שאלות **מדלגת על השיחה הפתוחה בכוונה**,
        //      כדי לא להצביע עליך אל עצמך. ⇒ נוצר בדיוק חור אחד: המסוף
        //      היחיד שאתה מסתכל בו הוא היחיד שלא נבדק מול המסך.
        let liveCard: [String: Any]? = term.flatMap { liveAsk($0) }
        // A closed terminal cannot be answered, so its transcript question is not shown.
        let ask: PendingQuestion? = nil
        if let liveCard {
            screenCard = liveCard
            askOnScreen = ((liveCard["parts"] as? [[String: Any]])?.first?["question"] as? String ?? "")
                + (liveCard["id"] as? String ?? "")
        }

        // The next thing you would type — only when the terminal is yours to type into.
        var suggest = ""
        if term != nil, mode != .working, liveCard == nil, pending.isEmpty {
            suggest = Suggest.lookup(sid: sessionID, lines: reading.lines) ?? ""
        }

        let crew = Agents.live(sessionID: sessionID)
        var key = "\(lines.count)|\(reading.atStart ? 1 : 0)|"
        // The agents' strip is painted before the page compares this key, so
        // agent steps no longer belong in it. Reported 8.10: with them here,
        // every agent step rebuilt the whole log and moved a reader's place.
        if let last = lines.last { key += (last["text"] as? String ?? "").suffix(120) }
        key += "|\(pending.count)|\(ask?.toolID ?? "")|\(askOnScreen.prefix(40))"

        var context = ""
        if let tokens = session?.contextTokens, tokens > 0 {
            context = tokens >= 1000 ? Lang.t("\(tokens / 1000)k הקשר", "\(tokens / 1000)k context") : Lang.t("\(tokens) הקשר", "\(tokens) context")
        }

        return [
            "sid": sessionID,
            "tty": term?.tty ?? "",
            "slot": term?.slot ?? "—",
            "live": term != nil,
            "title": chatTitle(term: term, session: session),
            "state": term == nil ? "closed" : code(mode),
            "stateLabel": term == nil ? Lang.t("המסוף נסגר", "terminal closed") : label(mode),
            "model": session?.model ?? "",
            "context": context,
            "ctxLevel": Relay.level(session?.contextTokens ?? 0),
            "relay": term == nil ? "" : Relay.stage(for: sessionID),
            "relayAgents": term == nil || Relay.stage(for: sessionID).isEmpty ? 0 : Relay.agents(for: sessionID),
            "relayShell": term == nil || Relay.stage(for: sessionID).isEmpty ? false : Relay.shellOut(for: sessionID),
            "lines": lines,
            // ⛔ ‏**סוכן שרץ בשיחה שקטה הוא הסיבה ש"דומם" משקר.** קלוד־קוד
            //    מראה את זה בתוך השיחה, וכאן זה היה קיים רק במסך נפרד.
            "crew": crew.map { agentRow($0) },
            // ⇒ אין עוד מעליה ⇐ הדף מציג "תחילת השיחה" במקום כפתור־עוד
            "atStart": reading.atStart,
            "history": history(sessionID: sessionID),
            "suggest": suggest,
            "key": key
        ,
            // ⇒ מהיומן כשיש, ומהמסך כשאין. אותו כרטיס, אותה לחיצה.
            "ask": ask.map { askPayload($0, tty: term?.tty ?? "") } ?? (screenCard ?? [:]),
            // The files this conversation made, oldest first.
            "outputs": sessionOutputs(sessionID)
        ]
    }

    private static let dayClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d.M HH:mm"
        return f
    }()

    private static func sessionOutputs(_ sid: String) -> [[String: Any]] {
        let today = Calendar.current.startOfDay(for: Date())
        return Outputs.of(sessionID: sid).enumerated().map { pair in
            let o = pair.element
            let bytes = ((try? FileManager.default.attributesOfItem(atPath: o.path))?[.size] as? NSNumber)?.intValue ?? 0
            return [
                "path": o.path,
                "n": pair.offset + 1,
                "kind": (o.path as NSString).pathExtension.lowercased(),
                "when": o.at >= today ? hhmm.string(from: o.at) : dayClock.string(from: o.at),
                "size": size(bytes)
            ]
        }
    }

    private static func label(_ mode: SessionState.Mode) -> String {
        switch mode {
        case .working: return Lang.t("עובד", "working")
        case .waiting: return Lang.t("ממתין לך", "waiting for you")
        case .quiet:   return Lang.t("דומם", "idle")
        }
    }

    /// שם לשיחה שנפתחה — גם כשהמסוף שלה כבר אינו קיים.
    private static func chatTitle(term: Terminal?, session: SessionState?) -> String {
        if let term { return title(term: term, session: session) }
        if let t = session?.title, !t.isEmpty { return t }
        if let p = session?.project, !p.isEmpty { return p }
        return Lang.t("שיחה סגורה", "closed conversation")
    }

    /// שם השיחה, לפי סדר־אמינות יורד: השם שהמודל נתן, כותרת־החלון, שם התיקייה.
    private static func title(term: Terminal, session: SessionState?) -> String {
        // ⇒ שם שהמשתמש נתן גובר על הכותרת שהמודל נותן, שמשתנה מעצמה לאורך היום
        let mine = Names.name(for: term.sessionID)
        if !mine.isEmpty { return mine }
        if let t = session?.title, !t.isEmpty { return t }
        if !term.windowTitle.isEmpty { return term.windowTitle }
        if let p = session?.project, !p.isEmpty { return p }
        return Lang.t("מסוף ", "terminal ") + term.slot
    }

    /// שורת־המשנה: כשעובדים — מה עושים; אחרת — מה נאמר לאחרונה.
    private static func say(mode: SessionState.Mode, session: SessionState?) -> String {
        guard let session else { return Lang.t("אין יומן רשום למסוף הזה", "No log registered for this terminal") }
        if mode == .working, !session.activity.isEmpty { return session.activity }
        return session.snippet
    }

    /// ‏"/Users/me/Documents/claude" → "~/Documents/claude"
    private static func short(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let home = Terminals.home.path
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }

    /// כמה זמן עבר מאז התנועה האחרונה. בלי יומן — כמה זמן המסוף פתוח.
    private static func age(since date: Date?, fallback uptime: TimeInterval) -> String {
        let seconds = date.map { Date().timeIntervalSince($0) } ?? uptime
        if seconds < 60 { return Lang.t("עכשיו", "now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return Lang.t("לפני \(minutes)ד", "\(minutes)m ago") }
        let hours = minutes / 60
        if hours < 24 { return Lang.t("לפני \(hours)ש", "\(hours)h ago") }
        return Lang.t("לפני \(hours / 24)י", "\(hours / 24)d ago")
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func clock() -> String { hhmm.string(from: Date()) }
}
