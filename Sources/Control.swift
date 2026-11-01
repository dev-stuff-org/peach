import Foundation

/// The central console's line into Peach: a Unix socket, owner-only, never
/// on the network. `peach-q` (tools/peach-q) is its client.
///
///     ~/.claude/peach-state/peach.sock     mode 600, folder mode 700
///
/// One JSON request per connection, one JSON line back.
///
/// ⛔ HARD SAFETY LINE — this file is where it is enforced:
///
///   1. A tool-permission prompt ("Do you want to proceed?", "Allow …",
///      auto-mode classifier denials, plan approval) is NEVER answered on the
///      console's word. It needs `--asaf-click <token>`, and a token exists
///      only after the user clicked "Approve" in Peach's own window
///      (`request-click`). The token is bound to that console, that exact
///      question and that exact option, is single-use and expires in 10 min.
///      Anything else would launder approvals: one session approving another
///      session's tool call with nobody looking.
///   2. An AskUserQuestion about product, money, something going out to a
///      person, publishing or deploying (gate "asaf") is answered only with
///      the user's choice: an `--asaf-click` token, or `--asaf-relayed`, which
///      Peach checks against the console's OWN transcript — his answer to
///      the console's question tool, at most 30 minutes old, naming the same
///      option. The console relays his click; it does not decide for him.
///   3. A plain routine question may be answered by the console ("console"
///      in the log).
///   4. Unknown pickers are permission prompts (StateFeed.kind defaults to
///      "permission"), and an unreadable screen is never answered blind.
///
/// Every answer and send is logged to ~/.claude/peach-state/answers.log.
enum Control {

    static let socketPath = StateFeed.dir.appendingPathComponent("peach.sock").path
    static let logURL = StateFeed.dir.appendingPathComponent("answers.log")

    /// Set by AppDelegate: shows the approval sheet in Peach's window and
    /// calls back with the user's click (true = approve).
    static var askAsaf: ((_ title: String, _ text: String, _ done: @escaping (Bool) -> Void) -> Void)?
    /// Set by AppDelegate: takes the approval sheet down unanswered, so a
    /// request that timed out never leaves a sheet waiting in Peach.
    static var cancelAsk: (() -> Void)?
    /// Set by AppDelegate. Display-only hooks for verification: open a file
    /// in the reader (optionally in the editor), close it, and photograph
    /// Peach's own page. None of them types into a terminal or writes a file
    /// other than the snapshot, which only goes under ~/.claude/peach-state/.
    static var viewDoc: ((_ path: String, _ editing: Bool) -> Void)?
    static var closeDoc: (() -> Void)?
    static var snapshot: ((_ done: @escaping (Data?) -> Void) -> Void)?

    // MARK: - Server

    static func start() {
        StateFeed.ensureDir()
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            path.withUnsafeBytes { src in dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[0..<path.count])) }
        }
        // umask so the socket is born owner-only, then chmod to be sure.
        let old = umask(0o077)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(old)
        guard bound == 0 else { close(fd); return }
        chmod(socketPath, 0o600)
        guard listen(fd, 8) == 0 else { close(fd); return }
        let t = Thread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { continue }
                DispatchQueue.global(qos: .userInitiated).async { serve(c) }
            }
        }
        t.name = "peach.control"
        t.start()
    }

    private static func serve(_ c: Int32) {
        defer { close(c) }
        var on: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        // Same user only.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(c, &uid, &gid) == 0, uid == getuid() else { return }
        var buf = [UInt8](repeating: 0, count: 65536)
        var data = Data()
        while data.count < 65536 {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if data.contains(0x0A) { break }
        }
        let req = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let reply = handle(req)
        var out = (try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys])) ?? Data("{}".utf8)
        out.append(0x0A)
        out.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(c, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    static func handle(_ req: [String: Any]) -> [String: Any] {
        switch req["cmd"] as? String ?? "" {
        case "state":
            return StateFeed.snapshot(fresh: true)
        case "list":
            return ["questions": openQuestions()]
        case "answer":
            return answerCommand(req)
        case "request-click":
            return requestClick(req)
        case "send":
            return sendCommand(req)
        case "ping":
            return ["ok": true, "pid": Int(getpid())]
        case "view-doc":
            guard let path = req["path"] as? String else { return ["ok": false, "error": "path missing"] }
            let editing = req["editing"] as? Bool == true
            DispatchQueue.main.sync { viewDoc?(path, editing) }
            return ["ok": true]
        case "close-doc":
            DispatchQueue.main.sync { closeDoc?() }
            return ["ok": true]
        case "snapshot":
            return snapshotCommand(req)
        default:
            return ["ok": false, "error": "unknown command"]
        }
    }

    // MARK: - snapshot

    private static func snapshotCommand(_ req: [String: Any]) -> [String: Any] {
        let name = ((req["name"] as? String) ?? "snapshot").filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let url = StateFeed.dir.appendingPathComponent((name.isEmpty ? "snapshot" : name) + ".png")
        let wait = DispatchSemaphore(value: 0)
        var png: Data?
        DispatchQueue.main.async {
            guard let shoot = snapshot else { wait.signal(); return }
            shoot { data in png = data; wait.signal() }
        }
        guard wait.wait(timeout: .now() + 10) == .success, let data = png else {
            return ["ok": false, "error": "snapshot failed"]
        }
        do { try data.write(to: url) } catch { return ["ok": false, "error": error.localizedDescription] }
        return ["ok": true, "path": url.path]
    }

    // MARK: - list

    static func openQuestions() -> [[String: Any]] {
        let snap = StateFeed.snapshot(fresh: true)
        var out: [[String: Any]] = []
        for s in snap["sessions"] as? [[String: Any]] ?? [] {
            for q in s["questions"] as? [[String: Any]] ?? [] {
                var row = q
                row["sessionId"] = s["sessionId"]
                row["name"] = s["name"]
                row["slot"] = s["slot"]
                row["tty"] = s["tty"]
                row["status"] = s["status"]
                out.append(row)
            }
        }
        return out
    }

    // MARK: - Finding a console

    static func resolve(_ key: String) -> Terminal? {
        let k = key.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return nil }
        let terms = Terminals.open()
        if let t = terms.first(where: { $0.sessionID == k || $0.tty == k || String($0.pid) == k }) { return t }
        let digits = k.allSatisfy { $0.isNumber }
        if digits, let n = Int(k), let t = terms.first(where: { Int($0.slot) == n }) { return t }
        if k.count >= 6 {
            let hits = terms.filter { $0.sessionID.hasPrefix(k) }
            if hits.count == 1 { return hits[0] }
        }
        let low = k.lowercased()
        let named = terms.filter {
            let n = Names.name(for: $0.sessionID)
            return n.lowercased() == low || $0.recordName.lowercased() == low
        }
        return named.count == 1 ? named[0] : nil
    }

    // MARK: - Grants (tokens from the user's click)

    private struct Grant { let tty: String; let qid: String; let label: String; let until: Date }
    private static var grants: [String: Grant] = [:]
    private static var usedRelays: Set<String> = []
    /// Sessions Peach typed an answer into on someone's behalf, and when.
    /// ⛔ Their transcripts hold answers Peach typed, not the user's clicks, so
    ///    they are never accepted as relay evidence — otherwise the console
    ///    could answer a routine "Yes" somewhere and cite it for a gated one.
    private static var typedInto: [String: Date] = [:]
    private static let lock = NSLock()
    private static func guarded<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private static func mint(tty: String, qid: String, label: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytesShim(&bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        guarded {
            grants = grants.filter { $0.value.until > Date() }
            grants[token] = Grant(tty: tty, qid: qid, label: label, until: Date().addingTimeInterval(600))
        }
        return token
    }

    /// Single use: a valid token is consumed by the check.
    private static func redeem(_ token: String, tty: String, qid: String, label: String) -> Bool {
        guarded {
            guard let g = grants[token], g.until > Date(), g.tty == tty, g.qid == qid,
                  g.label == label else { return false }
            grants.removeValue(forKey: token)
            return true
        }
    }

    /// `peach-q request-click`: shows the user the exact question and option in
    /// Peach's window. His "Approve" mints the token; nothing else can.
    private static func requestClick(_ req: [String: Any]) -> [String: Any] {
        guard let term = resolve(req["session"] as? String ?? "") else { return fail("no such session") }
        let live = Terminals.livePicker(term.tty)
        guard live.seen, let p = live.picker else { return fail("no open question on that console's screen") }
        let qid = StateFeed.questionID(p)
        if let expect = req["expect"] as? String, !expect.isEmpty, expect != qid { return fail("question changed") }
        guard let opt = pickOption(p, req["option"] as? String ?? "") else { return fail("no such option") }
        guard let ask = askAsaf else { return fail("Peach UI not ready") }
        let name = displayName(term)
        let kind = StateFeed.kind(p)
        let title = Lang.t("המסוף המרכזי מבקש את אישורך", "The central console asks for your approval")
        var text = Lang.t("שיחה: ", "Session: ") + name + "\n\n"
        if !p.body.isEmpty { text += p.body.prefix(6).joined(separator: "\n") + "\n\n" }
        text += p.question + "\n\n" + Lang.t("התשובה שתישלח: ", "Answer to send: ") + "“" + opt.label + "”"
        if kind == "permission" || kind == "plan" {
            text += "\n\n" + Lang.t("זו בקשת־הרשאה לכלי. אישור כאן הוא האישור שלך.",
                                    "This is a tool-permission prompt. Approving here is your approval.")
        }
        let sem = DispatchSemaphore(value: 0)
        var approved = false
        DispatchQueue.main.async { ask(title, StateFeed.redact(text)) { ok in approved = ok; sem.signal() } }
        let wait = min(600, max(5, req["timeout"] as? Int ?? 600))
        if sem.wait(timeout: .now() + .seconds(wait)) == .timedOut {
            DispatchQueue.main.async { cancelAsk?() }
            return fail("The user did not answer within \(wait) s — the request was taken down")
        }
        guard approved else {
            log(who: "asaf-declined", term: term, p: p, option: opt.label, text: "", result: "declined")
            return fail("The user declined")
        }
        let token = mint(tty: term.tty, qid: qid, label: opt.label)
        return ["ok": true, "token": token, "id": qid, "option": opt.label, "expiresIn": 600]
    }

    // MARK: - Relay evidence

    /// the user's answer to the console's own AskUserQuestion, in the console's
    /// transcript: a main-thread tool_result "User has answered your
    /// questions: …" at most 30 min old that names `needle`. Each such answer
    /// relays once.
    private static func relayEvidence(fromSID sid: String, needle: String, target: String) -> String? {
        let tainted: Bool = guarded {
            if let at = typedInto[sid], Date().timeIntervalSince(at) < 1800 { return true }
            return false
        }
        guard !tainted, sid != target, !sid.isEmpty, !needle.isEmpty, let url = Sessions.transcriptURL(for: sid),
              let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 1_500_000 ? size - 1_500_000 : 0)
        let data = (try? h.readToEnd()) ?? Data()
        let rows = data.split(separator: 0x0A).reversed()
        // Claude Code 2.1.296 writes "Your questions have been answered:
        // \"Q\"=\"Label\"" (measured 10.10); older builds "User has answered
        // your questions: …". Both are accepted.
        let markers = [Data("questions have been answered".utf8), Data("answered your questions".utf8)]
        for row in rows {
            guard markers.contains(where: { row.range(of: $0) != nil }),
                  let obj = try? JSONSerialization.jsonObject(with: Data(row)) as? [String: Any],
                  obj["type"] as? String == "user", obj["isSidechain"] as? Bool != true,
                  let when = Sessions.time(obj["timestamp"]),
                  Date().timeIntervalSince(when) < 1800,
                  let msg = obj["message"] as? [String: Any],
                  let blocks = msg["content"] as? [[String: Any]] else { continue }
            for b in blocks where b["type"] as? String == "tool_result" {
                let id = b["tool_use_id"] as? String ?? ""
                var text = b["content"] as? String ?? ""
                if let arr = b["content"] as? [[String: Any]] {
                    text = arr.compactMap { $0["text"] as? String }.joined(separator: " ")
                }
                // The answer is matched exactly: ="Label" — so "Yes" does
                // not match an answer that merely contains the word.
                guard text.contains("questions have been answered") || text.contains("answered your questions"),
                      text.lowercased().contains("=\"" + needle.lowercased() + "\"") else { continue }
                let key = id + "|" + needle
                let fresh: Bool = guarded {
                    if usedRelays.contains(key) { return false }
                    usedRelays.insert(key); return true
                }
                if fresh { return id }
            }
        }
        return nil
    }

    // MARK: - answer

    private static func pickOption(_ p: Terminals.Picker, _ want: String) -> Terminals.Option? {
        let w = want.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return nil }
        if let o = p.options.first(where: { $0.label == w }) { return o }
        if let o = p.options.first(where: { $0.label.lowercased() == w.lowercased() }) { return o }
        if w.hasPrefix("#"), let o = p.options.first(where: { $0.n == String(w.dropFirst()) }) { return o }
        let pre = p.options.filter { $0.label.lowercased().hasPrefix(w.lowercased()) }
        return pre.count == 1 ? pre[0] : nil
    }

    private static func answerCommand(_ req: [String: Any]) -> [String: Any] {
        guard let term = resolve(req["session"] as? String ?? "") else { return fail("no such session") }
        let index = req["index"] as? Int ?? 0
        guard index == 0 else { return fail("only question 0 (the one on screen) can be answered") }
        let token = req["token"] as? String ?? ""
        let relayFrom = req["relayFrom"] as? String ?? ""
        let relayed = req["relayed"] as? Bool ?? false
        return answer(term: term, expect: req["expect"] as? String ?? "",
                      option: req["option"] as? String ?? "", text: req["text"] as? String ?? "",
                      via: "peach-q") { p, kind, gate, label in
            // Returns (allowed, who, evidence)
            let needle = label
            if !token.isEmpty {
                if redeem(token, tty: term.tty, qid: StateFeed.questionID(p), label: label) {
                    return (true, "asaf-relayed", "peach-click token")
                }
                return (false, "", "token invalid, expired, used, or for another question/option")
            }
            if gate == "asaf-click" {
                return (false, "", "REFUSED: tool-permission prompt — needs --asaf-click <token> from the user's click in Peach (peach-q request-click)")
            }
            if relayed {
                if let id = relayEvidence(fromSID: relayFrom, needle: needle, target: term.sessionID) {
                    return (true, "asaf-relayed", "console transcript answer " + id)
                }
                return (false, "", "no answer from the user naming “\(needle)” in the console's transcript in the last 30 min")
            }
            if gate == "asaf" {
                return (false, "", "REFUSED: this question is the user's decision (product/money/outward/deploy) — ask him, then --asaf-relayed, or use request-click")
            }
            return (true, "console", "routine")
        }
    }

    /// The one answering path for peach-q and for notification clicks.
    /// `authorize` decides; this function does the typing and the checking.
    static func answer(term: Terminal, expect: String, option: String, text: String, via: String,
                       authorize: (Terminals.Picker, String, String, String) -> (Bool, String, String)) -> [String: Any] {
        guard !term.windowless else { return fail("background session with no window — open it first") }
        let live = Terminals.livePicker(term.tty)
        guard live.seen else { return fail("not sent: the console's screen cannot be read, so it is not answered blind") }
        guard let p = live.picker else { return fail("not sent: no open question on screen") }
        let qid = StateFeed.questionID(p)
        if !expect.isEmpty && expect != qid { return fail("not sent: the question on screen changed (id \(qid))") }
        let kind = StateFeed.kind(p)
        let gate = StateFeed.gate(p, kind: kind)
        let free = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var label = ""
        var opt: Terminals.Option?
        if !free.isEmpty {
            guard kind == "ask", p.freeRow > 0, !p.multi else { return fail("not sent: this question takes no free text") }
            label = free
        } else {
            guard let o = pickOption(p, option) else {
                return fail("not sent: no option “\(option)”; options: " + p.options.map { $0.label }.joined(separator: " | "))
            }
            opt = o; label = o.label
        }
        let verdict = authorize(p, kind, gate, label)
        guard verdict.0 else {
            log(who: "refused", term: term, p: p, option: label, text: verdict.2, result: "refused", via: via)
            return ["ok": false, "result": "refused", "error": verdict.2, "kind": kind, "gate": gate, "id": qid]
        }
        let before = Terminals.signature(p)
        if !term.sessionID.isEmpty { guarded { typedInto[term.sessionID] = Date() } }
        let typed = opt.map { Terminals.choose($0.n, tty: term.tty) } ?? Terminals.answerFree(free, tty: term.tty)
        // Verify on a fresh read: the question must be gone, or replaced.
        Thread.sleep(forTimeInterval: 0.4)
        let after = Terminals.livePicker(term.tty)
        var result: String
        if !after.seen { result = typed ? "unverified" : "not sent" }
        else if let still = after.picker, Terminals.signature(still) == before { result = "not sent" }
        else { result = "answered" }
        log(who: verdict.1, term: term, p: p, option: label, text: verdict.2, result: result, via: via)
        var reply: [String: Any] = ["ok": result == "answered", "result": result, "who": verdict.1,
                                    "kind": kind, "gate": gate, "id": qid, "answer": label]
        if let next = after.picker, Terminals.signature(next) != before {
            reply["next"] = ["id": StateFeed.questionID(next), "question": StateFeed.redact(next.question),
                             "kind": StateFeed.kind(next)]
        }
        return reply
    }

    // MARK: - send

    private static func sendCommand(_ req: [String: Any]) -> [String: Any] {
        guard let term = resolve(req["session"] as? String ?? "") else { return fail("no such session") }
        let text = (req["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return fail("empty text") }
        guard !term.windowless else { return fail("background session with no window") }
        // ⛔ Typing into an open picker would pick an option ("1…" selects
        //    row 1). A console with a question open gets no prompt.
        let live = Terminals.livePicker(term.tty)
        guard live.seen else { return fail("not sent: the console's screen cannot be read") }
        if live.picker != nil || term.status == "waiting" {
            return fail("not sent: that console has an open question — answer it first")
        }
        let ok = Terminals.send(text, tty: term.tty)
        appendLog(["who": "console", "via": "peach-q", "action": "send", "session": term.sessionID,
                   "name": displayName(term), "tty": term.tty, "text": StateFeed.redact(String(text.prefix(500))),
                   "result": ok ? "sent" : "not sent"])
        return ["ok": ok, "result": ok ? "sent" : "not sent"]
    }

    // MARK: - Log

    static func displayName(_ term: Terminal) -> String {
        let n = Names.name(for: term.sessionID)
        if !n.isEmpty { return n }
        if !term.recordName.isEmpty { return term.recordName }
        if let t = Sessions.state(id: term.sessionID)?.title, !t.isEmpty { return t }
        return "terminal " + term.slot
    }

    static func log(who: String, term: Terminal, p: Terminals.Picker, option: String, text: String,
                    result: String, via: String = "peach-q") {
        appendLog(["who": who, "via": via, "action": "answer", "session": term.sessionID,
                   "name": displayName(term), "tty": term.tty, "kind": StateFeed.kind(p),
                   "gate": StateFeed.gate(p, kind: StateFeed.kind(p)),
                   "question": StateFeed.redact(String(p.question.prefix(400))),
                   "option": StateFeed.redact(option), "note": text, "result": result])
    }

    private static func appendLog(_ entry: [String: Any]) {
        var e = entry
        e["time"] = ISO8601DateFormatter().string(from: Date())
        guard let d = try? JSONSerialization.data(withJSONObject: e, options: [.sortedKeys]),
              let line = String(data: d, encoding: .utf8) else { return }
        StateFeed.appendPrivate(line, to: logURL)
    }

    private static func fail(_ why: String) -> [String: Any] { ["ok": false, "result": "not sent", "error": why] }
}

/// arc4random_buf is the system CSPRNG; no Security framework link needed.
@inline(__always) private func SecRandomCopyBytesShim(_ bytes: inout [UInt8]) -> Int32 {
    arc4random_buf(&bytes, bytes.count)
    return 0
}
