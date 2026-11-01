import Foundation

/// The machine-readable view of every console, for the central console.
///
/// Requested 10.10 by the user: "full control and full knowledge of all running
/// consoles, continuously" — with the constraint "keep it light: a service
/// that simply always sees this, no special writing, no model".
///
/// ⇒ Nothing here scans. Everything is read from what Peach already holds:
///   the process listing (`Terminals.recent`), the screen scan
///   (`Terminals.cachedPickers`), and the cached transcript reads
///   (`Sessions.state`, `Questions.pending`). The two scans call `poke()`
///   when they finish; the file is written only when the picture changed.
///   `peach-q` asks the running Peach over the local socket (`Control`) for
///   the same snapshot, on demand.
///
/// No LLM anywhere: classification is plain pattern matching.
enum StateFeed {

    static let dir = Terminals.home.appendingPathComponent(".claude/peach-state")
    static let file = dir.appendingPathComponent("sessions.json")

    private static let queue = DispatchQueue(label: "org.hameretz2.peach.state", qos: .utility)
    private static var lastCheap = ""
    private static var lastFull = ""
    private static var pending = false

    /// Called by the two scans after they refresh. Coalesced: many pokes in
    /// a burst make one check. Cheap check first (status words + pickers);
    /// the full snapshot is built only when that moved.
    /// Runs on the feed's serial queue (Notify's state lives there).
    static func onQueue(_ body: @escaping () -> Void) { queue.async(execute: body) }

    static func poke() {
        queue.async {
            if pending { return }
            pending = true
            queue.asyncAfter(deadline: .now() + 0.3) {
                pending = false
                writeIfChanged()
            }
        }
    }

    private static func cheapSignature() -> String {
        let terms = Terminals.recent()
        let scan = Terminals.cachedPickers()
        var parts: [String] = [scan.readable ? "R" : "U"]
        for t in terms {
            parts.append([t.tty, t.sessionID, t.status, t.recordName, t.windowless ? "w" : ""].joined(separator: ","))
        }
        for p in scan.list {
            parts.append(p.tty + "#" + Terminals.signature(p) + "#\(p.cursor)#" + p.checked.sorted().joined())
        }
        return parts.joined(separator: "|")
    }

    private static func writeIfChanged() {
        let scan = Terminals.cachedPickers()
        if scan.readable { Notify.shared.tick(terms: Terminals.recent(), pickers: scan.list) }
        let cheap = cheapSignature()
        if cheap == lastCheap { return }
        lastCheap = cheap
        var snap = snapshot(fresh: false)
        snap.removeValue(forKey: "updatedAt")
        guard let body = try? JSONSerialization.data(withJSONObject: snap, options: [.sortedKeys]),
              let text = String(data: body, encoding: .utf8) else { return }
        if text == lastFull { return }
        lastFull = text
        snap["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        guard let out = try? JSONSerialization.data(withJSONObject: snap, options: [.prettyPrinted, .sortedKeys]) else { return }
        writePrivate(out, to: file)
    }

    // MARK: - The snapshot

    /// Every console Peach sees. `fresh` lets a live `peach-q list` take a new
    /// screen read when the cached one is older than Peach's own 1.5 s; the
    /// feed itself never asks for one.
    static func snapshot(fresh: Bool) -> [String: Any] {
        let terms = Terminals.recent()
        let scan: (list: [Terminals.Picker], readable: Bool)
        if fresh {
            let s = Terminals.pickers()
            scan = (s.list, s.readable)
        } else {
            let s = Terminals.cachedPickers()
            scan = (s.list, s.readable)
        }
        var sessions: [[String: Any]] = []
        for term in terms {
            sessions.append(entry(term, scan: scan))
        }
        return [
            "version": 1,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "screenReadable": scan.readable,
            "notifications": ["on": Notify.enabled, "minWaitSeconds": Notify.minWait,
                              "macOS": Notify.authorization],
            "sessions": sessions
        ]
    }

    private static func entry(_ term: Terminal, scan: (list: [Terminals.Picker], readable: Bool)) -> [String: Any] {
        let session = Sessions.state(id: term.sessionID)
        let visible = scan.readable && Terminals.screenShows(term.tty)
        let picker = visible ? scan.list.first(where: { $0.tty == term.tty }) : nil
        let ask = Questions.pending(sessionID: term.sessionID)

        var name = Names.name(for: term.sessionID)
        if name.isEmpty { name = term.recordName }
        if name.isEmpty { name = session?.title ?? "" }
        if name.isEmpty { name = term.windowTitle }

        var out: [String: Any] = [
            "sessionId": term.sessionID,
            "name": redact(name),
            "cwd": session?.cwd ?? "",
            "pid": term.pid,
            "tty": term.tty,
            "slot": term.slot,
            "windowId": Terminals.windowID(term.tty),
            "windowless": term.windowless,
            "screenVisible": visible,
            "recordStatus": term.status,
            // "record" — Claude Code's own sessions/<pid>.json; "tty-registry"
            // — the older hook's guess, which can be stale for a new process.
            "sessionSource": term.status.isEmpty && term.recordName.isEmpty ? "tty-registry" : "record",
            "model": session?.model ?? "",
            "agentsRunning": session?.agentsRunning ?? 0,
            "lastTurn": redact(session?.snippet ?? ""),
            "lastEvent": session.map { ISO8601DateFormatter().string(from: $0.lastEvent) } ?? ""
        ]
        if let tokens = session?.contextTokens, tokens > 0 {
            out["contextTokens"] = tokens
            out["contextFill"] = (Relay.fill(tokens) * 1000).rounded() / 1000
        }

        var questions: [[String: Any]] = []
        if let picker {
            questions.append(describe(picker, ask: ask, term: term))
        } else if !visible, term.status == "waiting" || term.waiting == nil, let ask {
            // The screen cannot be seen: the transcript is all there is.
            // Shown so the console knows, never answerable from here.
            var q = transcriptOnly(ask)
            q["answerable"] = false
            q["why"] = "screen not readable — answer in the terminal"
            questions.append(q)
        }
        out["questions"] = questions

        // Status: the screen decides when it shows a picker.
        let status: String
        if let q = questions.first {
            let kind = q["kind"] as? String ?? ""
            status = (kind == "permission" || kind == "plan") ? "waiting-on-permission" : "waiting-on-question"
        } else if term.status == "waiting" {
            // Waiting with no picker in sight. Permission prompts never reach
            // the transcript; a question would show there once answered.
            status = ask != nil ? "waiting-on-question" : "waiting-on-permission"
        } else if term.status == "busy" || term.status == "shell" {
            status = "busy"
        } else if term.status == "idle" {
            status = "idle"
        } else {
            status = session?.mode == .working ? "busy" : "idle"
        }
        out["status"] = status
        return out
    }

    // MARK: - Questions

    /// A stable id for "this picker on this console": the console re-sends it
    /// with `answer`, and Peach refuses when the screen moved on meanwhile.
    static func questionID(_ p: Terminals.Picker) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        // A review screen reads the same in every form; its summary is what
        // tells one from the next.
        let key = p.tty + "|" + Terminals.signature(p) + (p.review ? "|" + p.context : "")
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }

    private static let permissionText: [String] = [
        "do you want to proceed", "do you want to make this edit", "do you want to create",
        "do you want to allow", "do you want to run", "do you want to", "allow ", "permission",
        "auto mode", "auto-mode", "classifier", "was blocked", "denied", "trust this folder",
        "would you like to proceed", "dangerously", "bypass"
    ]

    /// What kind of picker this is. ⛔ The default is "permission": only a
    /// picker that positively shows an AskUserQuestion form (its free-text
    /// row, its checkboxes, its header chips, or its review screen) is a
    /// question. Anything unrecognised is treated as an approval prompt.
    /// The plan-approval prompt. Measured 28.10 on 2.1.312: it no longer
    /// offers "keep planning" — it reads "Claude has written up a plan …
    /// Would you like to proceed?" with "Yes, and use auto mode" · "Yes,
    /// manually approve edits" · "Tell Claude what to change". Matched on the
    /// old and the new wording both.
    static func isPlan(_ p: Terminals.Picker) -> Bool {
        let q = p.question.lowercased()
        let opts = p.options.map { $0.label.lowercased() }
        return opts.contains { $0.contains("keep planning") || $0.contains("manually approve edits") }
            || q.contains("written up a plan") || q.contains("ready to code")
    }

    static func kind(_ p: Terminals.Picker) -> String {
        if p.review { return "review" }
        let q = p.question.lowercased()
        let opts = p.options.map { $0.label.lowercased() }
        if isPlan(p) { return "plan" }
        let chips = p.body.contains { $0.contains("☐") || $0.contains("☒") || $0.contains("✔ Submit") }
        let formShape = p.freeRow > 0 || p.multi || chips
        let body = p.body.joined(separator: " ").lowercased()
        let looksPermission = permissionText.contains { q.contains($0) }
            || (!chips && permissionText.contains { body.contains($0) })
            || opts.contains { $0.hasPrefix("yes, and don") || $0.hasPrefix("yes, allow") || $0.contains("don't ask again") }
        if formShape && !looksPermission { return "ask" }
        return "permission"
    }

    /// Words that make an AskUserQuestion a decision that belongs to the user:
    /// product, money, outward to a person, publish/deploy, irreversible.
    /// Over-matching is the safe side: it only means the console relays.
    private static let asafWords: [String] = [
        // deploy / release / publish
        "deploy", "release", "publish", "ship", "go live", "production", "prod ", "push", "merge",
        "rollback", "upload", "פרסום", "לפרסם", "שחרור", "לשחרר", "פריסה", "לפרוס", "להעלות", "באוויר",
        // money
        "price", "pricing", "pay", "payment", "refund", "charge", "invoice", "budget", "cost", "money",
        "₪", "$", "€", "subscription", "coupon", "discount", "מחיר", "כסף", "תשלום", "החזר", "חיוב",
        "חשבונית", "תקציב", "עלות", "מנוי", "קופון", "הנחה", "שקל",
        // outward to a person
        "send", "email", "mail", "whatsapp", "sms", "message to", "customer", "client", "post ",
        "instagram", "facebook", "newsletter", "לשלוח", "שליחה", "מייל", "ווטסאפ", "וואטסאפ", "סמס",
        "הודעה ל", "לקוח", "פוסט", "דיוור", "אינסטגרם",
        // irreversible / product
        "delete", "remove all", "drop ", "wipe", "irreversible", "למחוק", "מחיקה", "בלתי הפיך",
        "product", "brand", "מוצר", "מיתוג", "החלטה"
    ]

    /// "asaf-click" — a permission/plan prompt: only with a token from the user's
    /// click in Peach. "asaf" — a product/money/outward/deploy question:
    /// only with the user's own choice (token, or his answer in the console's
    /// transcript). "routine" — the console may answer.
    static func gate(_ p: Terminals.Picker, kind: String) -> String {
        if kind == "permission" || kind == "plan" { return "asaf-click" }
        let text = ([p.question] + p.body + p.options.map { $0.label + " " + $0.detail } + [p.context])
            .joined(separator: " ").lowercased()
        return asafWords.contains { text.contains($0) } ? "asaf" : "routine"
    }

    static func describe(_ p: Terminals.Picker, ask: PendingQuestion?, term: Terminal) -> [String: Any] {
        let k = kind(p)
        var header = ""
        for line in p.body where line.contains("☐") || line.contains("☒") {
            // "☐ Fruit" or "←  ☒ Fruit  ☐ Color  ✔ Submit  →": the first open chip.
            if let r = line.range(of: "☐") {
                header = String(line[r.upperBound...]).components(separatedBy: "  ").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
            }
        }
        var q: [String: Any] = [
            "index": 0,
            "id": questionID(p),
            "kind": k,
            "form": (k == "permission" || k == "plan") ? "tool-permission" : "AskUserQuestion",
            "gate": gate(p, kind: k),
            "header": redact(header),
            "question": redact(p.question),
            "body": p.body.map(redact),
            "multiSelect": p.multi,
            "cursor": p.cursor,
            "freeTextRow": p.freeRow,
            "options": p.options.map { o -> [String: Any] in
                ["n": o.n, "label": redact(o.label), "description": redact(o.detail),
                 "checked": p.checked.contains(o.n)]
            },
            "context": redact(String(p.context.prefix(1200))),
            "answerable": !term.windowless
        ]
        // The transcript holds the form's full structure (all its questions)
        // once Claude Code has flushed it; when it matches, include it.
        if let ask, ask.kind == "ask", k != "permission",
           ask.parts.contains(where: { !p.question.isEmpty && $0.question.hasPrefix(String(p.question.prefix(30))) }) || k == "review" {
            q["parts"] = parts(ask)
            if header.isEmpty, let hit = ask.parts.first(where: { $0.question.hasPrefix(String(p.question.prefix(30))) }) {
                q["header"] = redact(hit.header)
            }
        }
        return q
    }

    private static func parts(_ ask: PendingQuestion) -> [[String: Any]] {
        ask.parts.map { part in
            ["header": redact(part.header), "question": redact(part.question), "multiSelect": part.multi,
             "options": part.choices.map { ["label": redact($0.label), "description": redact($0.detail)] }]
        }
    }

    private static func transcriptOnly(_ ask: PendingQuestion) -> [String: Any] {
        var q: [String: Any] = [
            "index": 0, "id": ask.toolID,
            "kind": ask.kind == "plan" ? "plan" : "ask",
            "form": ask.kind == "plan" ? "tool-permission" : "AskUserQuestion",
            "gate": ask.kind == "plan" ? "asaf-click" : "asaf",
            "context": redact(String(ask.context.prefix(1200)))
        ]
        if ask.kind == "plan" { q["question"] = "Approve the plan?"; q["plan"] = redact(String(ask.plan.prefix(1200))) }
        else {
            q["parts"] = parts(ask)
            q["header"] = redact(ask.parts.first?.header ?? "")
            q["question"] = redact(ask.parts.first?.question ?? "")
        }
        return q
    }

    // MARK: - Redaction

    /// Screen text can hold secrets. Any long token-like run — 24+ chars of
    /// [A-Za-z0-9_-+=/] holding both letters and digits — is replaced, and
    /// so are the usual prefixed keys at any length over 12.
    private static let tokenLike = try! NSRegularExpression(
        pattern: "(sk-[A-Za-z0-9_\\-]{12,}|gh[pousr]_[A-Za-z0-9]{12,}|xox[abpr]-[A-Za-z0-9\\-]{10,}|AKIA[0-9A-Z]{12,}|eyJ[A-Za-z0-9_\\-]{10,}(\\.[A-Za-z0-9_\\-]+)*|[A-Za-z0-9_\\-+=/]{24,})")
    private static let bearer = try! NSRegularExpression(
        pattern: "(?i)(bearer|token|password|passwd|secret|api[_-]?key)([\"'=: ]+)([^\\s\"']{8,})")

    static func redact(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var text = s
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in tokenLike.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let run = ns.substring(with: m.range)
            let letters = run.rangeOfCharacter(from: .letters) != nil
            let digits = run.rangeOfCharacter(from: .decimalDigits) != nil
            // A path ("/Users/…") or a UUID-free word run is not a token.
            let pathy = run.hasPrefix("/") || run.filter({ $0 == "/" }).count >= 2
            guard letters && digits && !pathy else { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += "[redacted:\(run.count)]"
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        text = out
        let ns2 = text as NSString
        text = bearer.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns2.length),
                                               withTemplate: "$1$2[redacted]")
        return text
    }

    // MARK: - Private files

    /// Atomic write, mode 600, in a mode-700 folder: a temp file created 0600
    /// beside the target, then renamed over it.
    static func writePrivate(_ data: Data, to url: URL) {
        ensureDir()
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".\(getpid()).tmp")
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return }
        fchmod(fd, 0o600)
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { break }
                off += n
            }
        }
        close(fd)
        rename(tmp.path, url.path)
    }

    /// One line appended to a mode-600 file.
    static func appendPrivate(_ line: String, to url: URL) {
        ensureDir()
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { return }
        fchmod(fd, 0o600)
        let bytes = Array((line.hasSuffix("\n") ? line : line + "\n").utf8)
        _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
        close(fd)
    }

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        chmod(dir.path, 0o700)
    }
}
