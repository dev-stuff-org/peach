import Foundation

/// Hand-over when a conversation's context window fills up.
///
/// Requested 3.10 as an automatic new terminal at 600k; reworked 8.10 (0.26)
/// after the user asked "why doesn't Peach make sure to move conversations to a
/// new conversation when the context grows?" — until then it depended on each
/// Claude session noticing the "refresh before fatigue" rule by itself.
///
/// Measured on the fill of the window, not a fixed token count:
///   · warn  (ask − 5 points, default 70%) — the rack row shows a badge.
///   · ask   (default 75%, menu-configurable) — Peach types one line asking the
///     conversation to write its hand-off to ~/Documents/claude/handoffs/ and
///     register its open items.
///   · ready — the file exists, is substantial and has stopped changing. The
///     row (and the open conversation) offers one click: "המשך בשיחה חדשה".
///   · go → continued — on that click Peach runs /clear in the same terminal,
///     names the new conversation "<name> · המשך" and pastes the
///     "Continue the work of conversation …" line pointing at the hand-off.
///
/// Every typed step waits until Claude Code's own record says "idle" for a
/// while: never mid-tool-call, never while agents run, never on a terminal
/// that is waiting on a question or showing a picker.
///
/// If the file never arrives within 20 minutes the attempt is marked failed
/// and never re-asked on its own; a file that turns up later still flips it
/// to ready.
enum Relay {

    // MARK: - Thresholds

    /// The window size the fill is measured against. The transcript does not
    /// record it (checked); Opus here runs with 1M (measured: 965k seen).
    /// A smaller window only means the badge comes late, never falsely.
    static var window: Int {
        let v = UserDefaults.standard.integer(forKey: "relayWindow")
        return v > 0 ? v : 1_000_000
    }
    static let choices = [60, 65, 70, 75, 80, 85]
    static var askPercent: Int {
        get { let v = UserDefaults.standard.integer(forKey: "relayAskPct"); return choices.contains(v) ? v : 75 }
        set { UserDefaults.standard.set(newValue, forKey: "relayAskPct") }
    }
    static var warnPercent: Int { askPercent - 5 }
    static func fill(_ tokens: Int) -> Double { Double(tokens) / Double(max(window, 1)) }
    /// "" · "warn" · "ask" — for the rack badge.
    static func level(_ tokens: Int) -> String {
        let pct = fill(tokens) * 100
        if pct >= Double(askPercent) { return "ask" }
        if pct >= Double(warnPercent) { return "warn" }
        return ""
    }
    /// Test hook: when set, only conversations under this folder are touched.
    private static var onlyCwd: String { UserDefaults.standard.string(forKey: "relayOnlyCwd") ?? "" }

    /// Idle this long before anything is typed into a conversation.
    private static let quiet: TimeInterval = 45
    private static let giveUp: TimeInterval = 20 * 60

    private static let key = "relayOn"
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    struct Record: Codable {
        var stage: String            // "asked" · "ready" · "go" · "continued" · "failed" (+ legacy "spawned" · "kept" · "closed" · "baseline")
        var file: String
        var cwd: String
        var name: String
        var at: Date
        var next: String?
        var prev: String?
        var pct: Int?
        /// Continued by Peach on its own (auto-continue), not by a click.
        var auto: Bool?
    }

    private static let lock = NSLock()
    private static var memo: [String: Record]?
    private static var memoStamp: Date?
    private static var lastTick = Date.distantPast
    private static var stateURL: URL { Terminals.home.appendingPathComponent(".claude/peach-relay.json") }

    private static func stamp() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: stateURL.path))?[.modificationDate] as? Date
    }

    static func all() -> [String: Record] {
        lock.lock(); defer { lock.unlock() }
        // Re-read when the file was changed from outside (tests, another copy).
        let now = stamp()
        if let memo, now == memoStamp { return memo }
        let data = (try? Data(contentsOf: stateURL)) ?? Data()
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let loaded = (try? dec.decode([String: Record].self, from: data)) ?? [:]
        memo = loaded; memoStamp = now
        return loaded
    }

    private static func save(_ next: [String: Record]) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(next) else { return }
        lock.lock(); defer { lock.unlock() }
        try? data.write(to: stateURL, options: .atomic)
        memo = next; memoStamp = stamp()
    }

    /// The row's relay stage, for buttons: "asked" · "ready" · "go" · "".
    static func stage(for sid: String) -> String {
        guard !sid.isEmpty, let r = all()[sid] else { return "" }
        return ["asked", "ready", "go"].contains(r.stage) ? r.stage : ""
    }

    /// Background agents still running in this conversation (for the button's note).
    /// Claude Code's own record says "shell": a background command is still out.
    static func shellOut(for sid: String) -> Bool {
        guard let term = Terminals.open().first(where: { $0.sessionID == sid }) else { return false }
        return official(pid: term.pid).state == "shell"
    }

    /// Counted as background agents launched (their .meta.json says
    /// "background") whose completion notice ("<task-id>ID</task-id>") has not
    /// reached the conversation's log. Activity is not used: an agent that is
    /// waiting on a long command writes nothing for minutes (measured 8.10).
    /// Only called for rows that are in a relay, so the log read is rare.
    static func agents(for sid: String) -> Int {
        guard !sid.isEmpty, let url = Sessions.transcriptURL(for: sid) else { return 0 }
        let dir = url.deletingPathExtension().appendingPathComponent("subagents")
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return 0 }
        let metas = items.filter { $0.lastPathComponent.hasSuffix(".meta.json") }
        var ids: [String] = []
        for m in metas {
            guard let d = try? Data(contentsOf: m),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  o["requestShape"] as? String == "background" else { continue }
            let name = m.lastPathComponent.replacingOccurrences(of: ".meta.json", with: "")
            ids.append(name.hasPrefix("agent-") ? String(name.dropFirst(6)) : name)
        }
        guard !ids.isEmpty, let log = try? Data(contentsOf: url) else { return 0 }
        return ids.filter { log.range(of: Data("<task-id>\($0)</task-id>".utf8)) == nil }.count
    }

    /// The click: continue in a new conversation. Done on the next quiet tick.
    static func go(_ sid: String) {
        var map = all()
        guard var r = map[sid], r.stage == "ready" || r.stage == "failed" && ready(r.file) else { return }
        r.stage = "go"; r.at = Date(); map[sid] = r
        save(map)
        lastTick = .distantPast
    }

    /// The label a rack row shows, if this conversation is part of a relay.
    static func label(for sid: String, terms: [Terminal]) -> String {
        guard !sid.isEmpty else { return "" }
        let map = all()
        func slot(_ id: String?) -> String {
            guard let id else { return "" }
            return terms.first { $0.sessionID == id }?.slot ?? Lang.t("סגור", "closed")
        }
        if let r = map[sid] {
            switch r.stage {
            case "asked":   return Lang.t("כותב מסירה להמשך", "writing a hand-off")
            case "ready":   return Lang.t("המסירה מוכנה", "hand-off ready")
            case "go":      return Lang.t("עובר לשיחה חדשה…", "moving to a new conversation…")
            case "spawned", "kept": return Lang.t("הועבר ל־", "continued in ") + slot(r.next)
            case "continued" where r.auto == true: return Lang.t("הומשך אוטומטית", "continued automatically")
            case "failed":  return Lang.t("המסירה לא נכתבה", "hand-off not written")
            default: break
            }
        }
        if let prev = map.first(where: { $0.value.next == sid }) {
            if prev.value.stage == "continued" {
                return prev.value.auto == true ? Lang.t("הומשך אוטומטית", "continued automatically")
                                               : Lang.t("המשך משיחה קודמת", "continues an earlier conversation")
            }
            return Lang.t("המשך של ", "continues ") + slot(prev.key)
        }
        return ""
    }

    /// Called from the scan, off the main thread. Cheap: at most every 10 s.
    static func tick(_ terms: [Terminal]) {
        guard on, Date().timeIntervalSince(lastTick) > 10 else { return }
        lastTick = Date()
        var map = all()
        var changed = false

        // Relays from before closing existed are left as they are: closing a
        // conversation the user kept working in would be a surprise, not a fix.
        if !UserDefaults.standard.bool(forKey: closeKey) {
            for (k, r) in map where r.stage == "spawned" { var r2 = r; r2.stage = "kept"; map[k] = r2 }
            UserDefaults.standard.set(true, forKey: closeKey)
            changed = true
        }

        for term in terms where !term.sessionID.isEmpty && !term.windowless {
            let sid = term.sessionID
            let status = official(pid: term.pid)
            // ⛔ "idle" in Claude Code's own record = the turn ended. A tool
            //    call in flight is "busy"; a question or permission prompt is
            //    "waiting". A picker on screen is checked too (it reads the
            //    screen, so it runs last, only when the record already says quiet).
            // ⛔ Background agents do NOT block (fixed 0.27). Measured 8.10: the
            //    central console almost always has agents running, so a rule
            //    of "no agents" meant it was never asked — at 95% context.
            //    Typing into an idle prompt is safe with agents running; the
            //    hand-off lists them and the button says how many are still out.
            // ⛔ And "shell" counts as idle: Claude Code's record has four
            //    states — busy · shell · idle · waiting (read from its source,
            //    2.1.294). "shell" = the turn ended but a background shell or
            //    agent is still out; the prompt is free. Measured 8.10 on a
            //    test session with one background agent: "shell", never "idle".
            let free = status.state == "idle" || status.state == "shell"
            let idle = { free && Date().timeIntervalSince(status.since) > quiet
                && term.waiting != true
                && !Terminals.pickers().list.contains(where: { $0.tty == term.tty }) }

            if var r = map[sid] {
                // Legacy (0.11–0.25): the old conversation is closed once the
                // successor opened in a new terminal has started.
                if r.stage == "spawned", idle(), let next = r.next,
                   terms.contains(where: { $0.sessionID == next }), started(next, file: r.file) {
                    _ = Terminals.send("/exit", tty: term.tty)
                    Thread.sleep(forTimeInterval: 2)
                    if terms.contains(where: { $0.pid == term.pid }) { kill(pid_t(term.pid), SIGTERM) }
                    Thread.sleep(forTimeInterval: 1)
                    Terminals.closeWindow(tty: term.tty)
                    r.stage = "closed"; map[sid] = r; changed = true
                    continue
                }
                if r.stage == "asked" || r.stage == "failed" {
                    if ready(r.file) {
                        r.stage = "ready"; map[sid] = r; changed = true
                    } else if r.stage == "asked", Date().timeIntervalSince(r.at) > giveUp {
                        r.stage = "failed"; map[sid] = r; changed = true
                    }
                    continue
                }
                // AUTO-CONTINUE (approved by the user 10.10): a ready hand-off is
                // carried on without the click — with the same safety as the
                // click, plus: no agents or background shells out ("idle",
                // not "shell"), and nothing said in the conversation since the
                // hand-off was written (else the file is older than the work).
                if r.stage == "ready", autoContinue, idle(), status.state == "idle",
                   agents(for: sid) == 0 {
                    if let why = staleHandoff(sid: sid, file: r.file) {
                        if r.auto != false {
                            hygieneLog("AUTO-CONTINUE skipped \(term.slot) \(sid.prefix(8)) — \(why)")
                            r.auto = false; map[sid] = r; changed = true
                        }
                        continue
                    }
                    hygieneLog("AUTO-CONTINUE \(term.slot) \(sid.prefix(8)) \(r.name) — hand-off \(r.file)")
                    r.stage = "go"; r.auto = true
                }
                guard r.stage == "go", idle() else { continue }
                if let next = carryOn(sid: sid, record: r, term: term) {
                    r.stage = "continued"; r.next = next; r.at = Date()
                    count(reset: r.name.isEmpty ? String(sid.prefix(8)) : r.name)
                    if r.auto == true { hygieneLog("AUTO-CONTINUE done \(term.slot) → \(next.prefix(8))") }
                } else {
                    r.stage = "ready"           // the button comes back; nothing half-done
                }
                map[sid] = r; changed = true
                continue
            }

            guard let s = Sessions.state(id: sid), level(s.contextTokens) == "ask" else { continue }
            if !onlyCwd.isEmpty && !s.cwd.hasPrefix(onlyCwd) { continue }
            // ⛔ The first time the feature runs, conversations that are
            //    already past the line are left alone (measured 3.10: four
            //    were, one idle for two weeks). Typing into all of them at
            //    install would be a surprise, not a hand-off.
            if !primed {
                map[sid] = Record(stage: "baseline", file: "", cwd: s.cwd, name: "",
                                  at: Date(), next: nil, prev: nil)
                changed = true
                continue
            }
            guard idle() else { continue }
            let pct = Int((fill(s.contextTokens) * 100).rounded())
            let file = handoffPath(sid: sid)
            let line = "Peach: this conversation's context window is \(pct)% full. "
                + "Stop starting new work. Write your hand-off now to \(file) — the goal, the current state, "
                + "what is done and verified, every open item with its exact next step, key paths, commands, "
                + "decisions and warnings — so a fresh conversation can continue with no other context. "
                + "List every background agent that is still running — its task, its agent id and its output "
                + "file path — so the next conversation can pick up their results. "
                + "Register every open item in the task queue as well. Then reply with one short line. "
                + "Peach will offer the user one click to continue in a new conversation from that file."
            // Recorded even if the send is not confirmed, so the request is
            // never typed a second time; an unanswered one fails after 20 min.
            _ = submit(line, tty: term.tty, pid: term.pid)
            var name = Names.name(for: sid)
            if name.isEmpty { name = s.title.isEmpty ? (s.project) : s.title }
            map[sid] = Record(stage: "asked", file: file, cwd: s.cwd, name: name,
                              at: Date(), next: nil, prev: nil, pct: pct)
            changed = true
        }
        if !primed { UserDefaults.standard.set(true, forKey: primedKey) }
        if changed { save(map) }
        rollDay()
        sweepIdle(terms, map: map)
    }

    // MARK: - Session hygiene (approved by the user 10.10)

    static var autoContinue: Bool {
        get { UserDefaults.standard.object(forKey: "relayAutoContinue") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "relayAutoContinue") }
    }
    static var idleClose: Bool {
        get { UserDefaults.standard.object(forKey: "hygieneIdleClose") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hygieneIdleClose") }
    }
    /// Idle this long, by Claude Code's own record and by the log, before a
    /// conversation's terminal is closed.
    static var idleAge: TimeInterval { testCwd.isEmpty ? 24 * 3600 : max(30, testAge) }
    /// Test hook: BOTH a short age (hygieneTestAge, seconds) and a folder
    /// (hygieneTestCwd) must be set; then only that folder's conversations are
    /// considered, so a test can never close a real one.
    private static var testAge: TimeInterval { UserDefaults.standard.double(forKey: "hygieneTestAge") }
    private static var testCwd: String {
        let c = UserDefaults.standard.string(forKey: "hygieneTestCwd") ?? ""
        return testAge > 0 ? c : ""
    }
    private static var lastSweep = Date.distantPast
    private static let dryKey = "hygieneDryRunDone"

    static func hygieneLog(_ text: String) {
        let url = Terminals.home.appendingPathComponent(".claude/peach-hygiene.log")
        let line = ISO8601DateFormatter().string(from: Date()) + " " + text + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(line.utf8))
        } else { try? Data(line.utf8).write(to: url) }
    }

    /// nil when the hand-off is current; otherwise why it is not.
    private static func staleHandoff(sid: String, file: String) -> String? {
        guard let f = (try? FileManager.default.attributesOfItem(atPath: file))?[.modificationDate] as? Date
        else { return "hand-off file missing" }
        guard let url = Sessions.transcriptURL(for: sid),
              let t = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return nil }
        // The reply line after writing the file lands within a few minutes.
        return t.timeIntervalSince(f) > 300 ? "the conversation went on after the hand-off was written" : nil
    }

    /// Open items in the session's task queue (pending or in progress).
    private static func openTasks(_ sid: String) -> Int {
        let dir = Terminals.home.appendingPathComponent(".claude/tasks/\(sid)")
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return 0 }
        return items.filter { $0.pathExtension == "json" }.filter { url in
            guard let d = try? Data(contentsOf: url),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
            let st = o["status"] as? String ?? ""
            return st == "pending" || st == "in_progress"
        }.count
    }

    /// Every name this conversation goes by — Peach's, Claude Code's, the window's.
    private static func names(_ term: Terminal) -> [String] {
        [Names.name(for: term.sessionID), term.recordName, term.windowTitle,
         Sessions.state(id: term.sessionID)?.title ?? ""].filter { !$0.isEmpty }
    }

    /// IDLE CLOSE: a conversation idle ≥ 24 h, with nothing open, is exited
    /// (/exit) and its window closed. The transcript stays resumable from the
    /// search screen. The first run only lists what it would close.
    /// Read-only: what the sweep would do now, for a check before install.
    static func idleReport() -> [String] {
        var out: [String] = []
        for term in Terminals.open() where !term.sessionID.isEmpty {
            let st = official(pid: term.pid)
            let h = Int(Date().timeIntervalSince(st.since) / 3600)
            out.append("\(term.slot) \(st.state) idle \(h)h tasks \(openTasks(term.sessionID)) agents \(agents(for: term.sessionID)) windowless \(term.windowless) · " + (names(term).first ?? ""))
        }
        return out
    }

    private static func sweepIdle(_ terms: [Terminal], map: [String: Record], force: Bool = false) {
        guard idleClose, force || Date().timeIntervalSince(lastSweep) > (testCwd.isEmpty ? 600 : 20) else { return }
        lastSweep = Date()
        let dry = !UserDefaults.standard.bool(forKey: dryKey)
        let shown = Terminals.pickers().list
        var picked = 0
        for term in terms where !term.sessionID.isEmpty && !term.windowless {
            let sid = term.sessionID
            if !testCwd.isEmpty && !(Sessions.state(id: sid)?.cwd ?? "").hasPrefix(testCwd) { continue }
            let st = official(pid: term.pid)
            guard st.state == "idle", Date().timeIntervalSince(st.since) >= idleAge else { continue }
            if let url = Sessions.transcriptURL(for: sid),
               let t = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
               Date().timeIntervalSince(t) < idleAge { continue }
            let label = "\(term.slot) \(sid.prefix(8)) \(names(term).first ?? "")"
            func skip(_ why: String) { hygieneLog("IDLE-CLOSE keep \(label) — \(why)") }
            // "מסוף · המשך" and "מסוף המשך" are the same name: the dot goes.
            let plain = names(term).map {
                $0.replacingOccurrences(of: "·", with: " ").replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            }
            if plain.contains(where: { $0.contains("מסוף המשך") || $0.contains("מסוף מרכזי") }) { skip("central console"); continue }
            if term.waiting == true || shown.contains(where: { $0.tty == term.tty }) { skip("a question is open"); continue }
            if let r = map[sid], ["asked", "ready", "go"].contains(r.stage) { skip("hand-off in progress"); continue }
            let open = openTasks(sid)
            if open > 0 { skip("\(open) open tasks"); continue }
            if agents(for: sid) > 0 { skip("agents running"); continue }
            let hours = Int(Date().timeIntervalSince(st.since) / 3600)
            picked += 1
            if dry { hygieneLog("IDLE-CLOSE dry-run would close \(label) — idle \(hours)h"); continue }
            hygieneLog("IDLE-CLOSE closing \(label) — idle \(hours)h")
            _ = Terminals.send("/exit", tty: term.tty)
            var gone = false
            for _ in 0..<16 {
                Thread.sleep(forTimeInterval: 0.5)
                if kill(pid_t(term.pid), 0) != 0 { gone = true; break }
            }
            guard gone else { hygieneLog("IDLE-CLOSE \(label) did not exit — left open"); continue }
            Thread.sleep(forTimeInterval: 0.5)
            let closed = Terminals.closeLoneWindow(tty: term.tty)
            hygieneLog("IDLE-CLOSE closed \(label)" + (closed ? "" : " (session exited; window kept — it has other tabs)"))
            count(closed: names(term).first ?? String(sid.prefix(8)))
        }
        if dry {
            hygieneLog("IDLE-CLOSE dry-run done — \(picked) would be closed; acting from the next sweep")
            UserDefaults.standard.set(true, forKey: dryKey)
        }
    }

    // MARK: Daily summary

    private struct Day: Codable { var day: String; var reset: [String]; var closed: [String] }
    private static let dayKey = "hygieneDay"
    private static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private static func loadDay() -> Day {
        guard let d = UserDefaults.standard.data(forKey: dayKey),
              let v = try? JSONDecoder().decode(Day.self, from: d) else { return Day(day: today(), reset: [], closed: []) }
        return v
    }
    private static func saveDay(_ d: Day) {
        if let data = try? JSONEncoder().encode(d) { UserDefaults.standard.set(data, forKey: dayKey) }
    }
    private static func count(reset: String? = nil, closed: String? = nil) {
        rollDay()
        var d = loadDay()
        if let reset { d.reset.append(reset) }
        if let closed { d.closed.append(closed) }
        saveDay(d)
    }
    static func line(_ d: (reset: [String], closed: [String])) -> String {
        func part(_ xs: [String]) -> String { xs.isEmpty ? "0" : "\(xs.count) (" + xs.joined(separator: ", ") + ")" }
        return Lang.t("אופסו: ", "Reset: ") + part(d.reset) + " · " + Lang.t("נסגרו: ", "Closed: ") + part(d.closed)
    }
    /// Today's one line, for the menu.
    static func todayLine() -> String { let d = loadDay(); return line((d.reset, d.closed)) }
    /// A new day: yesterday's line goes to the log once.
    private static func rollDay() {
        let d = loadDay()
        guard d.day != today() else { return }
        hygieneLog("DAILY \(d.day) " + line((d.reset, d.closed)))
        saveDay(Day(day: today(), reset: [], closed: []))
    }

    /// /clear in the same terminal, then the continue line. Returns the new
    /// conversation's id, or nil if /clear did not take (nothing else typed).
    private static func carryOn(sid: String, record r: Record, term: Terminal) -> String? {
        _ = Terminals.send("/clear", tty: term.tty)
        // The product's own record follows /clear with a new session id.
        var next = ""
        for _ in 0..<25 {
            let now = recordSID(pid: term.pid)
            if !now.isEmpty && now != sid { next = now; break }
            Thread.sleep(forTimeInterval: 0.6)
        }
        guard !next.isEmpty else { return nil }
        let base = r.name.isEmpty ? Lang.t("שיחה", "conversation") : r.name
        let cont = " · " + Lang.t("המשך", "cont.")
        // A name already ending in "· המשך" is not stacked twice.
        let name = base.hasSuffix(cont) ? base : base + cont
        Names.set(name, for: next)
        Terminals.setWindowTitle(name, tty: term.tty)
        _ = Terminals.send("/rename " + name, tty: term.tty)
        Thread.sleep(forTimeInterval: 1)
        let pct = r.pct.map { "\($0)%" } ?? "\(askPercent)%"
        let first = "Continue the work of conversation \(sid), which was handed over at "
            + "\(pct) context. Read the hand-off first: \(r.file) — then carry on "
            + "with its open items. The old transcript, if a detail is missing: "
            + (Sessions.transcriptURL(for: sid)?.path ?? "(not found)")
        _ = Terminals.send(first, tty: term.tty)
        return next
    }

    private static func recordSID(pid: Int) -> String {
        let url = Terminals.home.appendingPathComponent(".claude/sessions/\(pid).json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return obj["sessionId"] as? String ?? ""
    }

    private static let closeKey = "relayCloseMigrated"

    /// The successor has begun: its own log mentions the hand-off file.
    private static func started(_ sid: String, file: String) -> Bool {
        guard let url = Sessions.transcriptURL(for: sid),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        // The hand-off reached it. Waiting on a permission prompt still counts
        // (measured 3.10: the first Read waited for approval and nothing had
        // reached the log yet) — that prompt shows in Peach like any question.
        return text.contains(file)
    }

    private static let primedKey = "relayPrimed"
    private static var primed: Bool { UserDefaults.standard.bool(forKey: primedKey) }

    /// Types the line and makes sure it was actually sent.
    ///
    /// ⛔ Measured 3.10 on a live test: a long line followed by Enter 0.25 s
    ///    later stayed in the input box, unsent — the Enter arrived while the
    ///    terminal was still taking the paste. Waiting longer and then
    ///    checking Claude Code's own status ("busy") is what proves it left.
    /// Typing and confirming the send is Terminals.send's job (it checks
    /// Claude Code's own status and retries Enter only if needed).
    private static func submit(_ text: String, tty: String, pid: Int) -> Bool {
        Terminals.send(text, tty: tty) && official(pid: pid).state != "idle"
    }

    /// The hand-off sits under the work root (Paths), so it also shows in the
    /// outputs screen and in the conversation's own outputs.
    private static func handoffPath(sid: String) -> String {
        let dir = Paths.handoffsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"
        return dir.appendingPathComponent("\(f.string(from: Date()))-\(sid.prefix(8)).md").path
    }

    /// Written, substantial, and untouched for 20 s — the writer is done.
    private static func ready(_ path: String) -> Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (a[.size] as? NSNumber)?.intValue, size > 300,
              let at = a[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(at) > 20
    }

    /// Claude Code's own record of this process: "idle" · "busy" · "waiting".
    private static func official(pid: Int) -> (state: String, since: Date) {
        let url = Terminals.home.appendingPathComponent(".claude/sessions/\(pid).json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("", .distantFuture)
        }
        let ms = (obj["statusUpdatedAt"] as? Double) ?? (obj["updatedAt"] as? Double) ?? 0
        return (obj["status"] as? String ?? "", Date(timeIntervalSince1970: ms / 1000))
    }
}
