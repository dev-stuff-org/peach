import Foundation

/// The next thing you would type, offered as ghost text in the composer.
///
/// Requested 25.10: Claude Code began predicting the user's next message and
/// the user wanted it in Peach. Measured the same day on 2.1.310: the terminal
/// never writes its suggestion anywhere — not the transcript, not a hook, not
/// a file. It is surfaced only to `claude -p --output-format stream-json`,
/// which Peach's sessions are not.
///
/// So Peach asks the same question itself, with the same instructions Claude
/// Code uses (copied from the binary), on the conversation that is open:
///   - only when the terminal is live, not working, has no question open, and
///     Claude spoke last;
///   - once per turn — the answer is kept until Claude says something new;
///   - through the local `claude` command with no tools, no MCP, no settings
///     and no hooks, thinking off, nothing saved as a session.
/// A conversation you never open costs nothing.
enum Suggest {

    private static let model = "haiku"
    private static let contextChars = 6000

    private struct Slot {
        let key: String
        var text: String?
        var busy: Bool
    }

    private static var slots: [String: Slot] = [:]
    private static let lock = NSLock()

    /// Posted on the main queue when a suggestion arrives, so the screen repaints.
    static let arrived = Notification.Name("PeachSuggestArrived")

    /// The suggestion for this turn, or nil while it is being made or when
    /// the model chose silence. Starts the request on first sight of a turn.
    static func lookup(sid: String, lines: [Line]) -> String? {
        guard let last = lines.last, last.role == "claude" else { return nil }
        let key = "\(lines.count)|" + String(last.text.suffix(160))
        lock.lock()
        if let slot = slots[sid], slot.key == key {
            lock.unlock()
            return slot.text
        }
        slots[sid] = Slot(key: key, text: nil, busy: true)
        lock.unlock()

        let context = transcript(lines)
        let hebrew = writesHebrew(lines)
        DispatchQueue.global(qos: .utility).async {
            let began = Date()
            let answer = ask(context, hebrew: hebrew)
            let text = answer.flatMap(clean)
            SmartSearch.log(String(format: "suggest %.1fs sid=%@ → %@", Date().timeIntervalSince(began),
                                   String(sid.prefix(8)), text ?? (answer == nil ? "FAILED" : "silence")))
            lock.lock()
            if slots[sid]?.key == key { slots[sid] = Slot(key: key, text: text, busy: false) }
            lock.unlock()
            DispatchQueue.main.async { NotificationCenter.default.post(name: arrived, object: sid) }
        }
        return nil
    }

    /// The end of the conversation as plain text, newest last. Tool steps are
    /// left out: the prediction is about what the person says next.
    private static func transcript(_ lines: [Line]) -> String {
        var out: [String] = []
        var used = 0
        for line in lines.reversed() where line.role == "you" || line.role == "claude" {
            let who = line.role == "you" ? "USER" : "ASSISTANT"
            let room = contextChars - used
            guard room > 200 else { break }
            let body = line.text.count > room ? "…" + String(line.text.suffix(room)) : line.text
            out.append("\(who): \(body)")
            used += body.count
        }
        return out.reversed().joined(separator: "\n\n")
    }

    /// Measured 25.10: on a Hebrew conversation Haiku answered in English
    /// unless told which language the user writes in.
    private static func writesHebrew(_ lines: [Line]) -> Bool {
        let mine = lines.filter { $0.role == "you" }.suffix(4).map(\.text).joined()
        let heb = mine.unicodeScalars.filter { (0x0590...0x05FF).contains($0.value) }.count
        let lat = mine.unicodeScalars.filter { $0.isASCII && $0.properties.isAlphabetic }.count
        return heb > lat
    }

    /// Claude Code's own instructions, 2.1.310, with the conversation in front.
    private static func prompt(_ context: String, hebrew: Bool) -> String {
        """
        Below is the end of a conversation between a user and an AI coding assistant.

        <conversation>
        \(context)
        </conversation>

        [SUGGESTION MODE: Suggest what the user might naturally type next.]

        FIRST: Look at the user's recent messages and original request.
        Your job is to predict what THEY would type - not what you think they should do.
        THE TEST: Would they think "I was just about to type that"?
        EXAMPLES:
        User asked "fix the bug and run tests", bug is fixed → "run the tests"
        After code written → "try it out"
        Claude offers options → suggest the one the user would likely pick, based on conversation
        Claude asks to continue → "yes" or "go ahead"
        Task complete, obvious follow-up → "commit this" or "push it"
        After error or misunderstanding → silence (let them assess/correct)
        Be specific: "run the tests" beats "continue".
        NEVER SUGGEST:
        - Evaluative ("looks good", "thanks")
        - Questions ("what about...?")
        - Claude-voice ("Let me...", "I'll...", "Here's...")
        - New ideas they didn't ask about
        - Multiple sentences
        Stay silent if the next step isn't obvious from what the user said.
        Stay silent if a suggestion could be unsafe or inappropriate — including any sensitive topic (security incidents, credentials, harm, private data).
        Format: 2-12 words, match the user's style and language. Or nothing.
        Reply with ONLY the suggestion, no quotes or explanation.
        You write AS the user, to the assistant. Never address the user, never report work, never speak as the assistant.
        """ + (hebrew ? "\nThe user writes in Hebrew: if you suggest anything, write it in Hebrew, the way they type." : "")
    }

    /// The same filters Claude Code applies: tags and labels stripped,
    /// meta-answers and long answers dropped.
    private static func clean(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"^<(suggestion|response|output|answer|result)>([\s\S]*)</\1>$"#,
                                   with: "$2", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"^\s*(suggested\s+(response|reply|input|prompt)|suggestion|response|reply|answer|output|result)\s*[:：]\s*"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”„ \n\t"))
        let low = s.lowercased()
        if s.isEmpty || low == "done" || low.hasPrefix("nothing") || low.hasPrefix("no suggestion")
            || low.range(of: #"\bsilen(ce|t)\b"#, options: .regularExpression) != nil { return nil }
        if s.contains("\n") || s.count > 120 { return nil }
        // Questions are on Claude Code's never-suggest list; Haiku slips one in now and then.
        if s.hasSuffix("?") { return nil }
        if s.split(separator: " ").count > 14 { return nil }
        return s
    }

    private static func ask(_ context: String, hebrew: Bool) -> String? {
        guard let claude = Terminals.claudePath() else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = ["-p", "--model", model, "--no-session-persistence", "--tools", "",
                       "--strict-mcp-config", "--setting-sources", ""]
        var env = ProcessInfo.processInfo.environment
        env["MAX_THINKING_TOKENS"] = "0"
        p.environment = env
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        input.fileHandleForWriting.write(Data(prompt(context, hebrew: hebrew).utf8))
        try? input.fileHandleForWriting.close()
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: killer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
