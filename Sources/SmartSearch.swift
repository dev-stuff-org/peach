import Foundation

/// Search in plain words: a model picks the conversations and files.
///
/// Requested 3.10: "search the chats with a simple model". The keyword search
/// finds exact words; this one answers "the conversation where we fixed the
/// cookie bar" when no exact phrase is remembered.
///
/// How, kept deliberately simple:
///   1. A catalog of the most recent conversations is built from what Peach
///      already has — the title, the folder, the date, and a few of the user's own
///      prompts from the search index.
///   2. The catalog and the question go to Sonnet through the local `claude`
///      command (the user's own sign-in, no key to store), with no tools, no MCP,
///      no settings and no hooks, and nothing saved as a session.
///   3. The answer is a list of short ids; each is checked against the
///      catalog, so a made-up id can never open a wrong conversation.
///
/// Measured 3.10: about 3 seconds for a bare call. 7.10: 4–7 seconds for a
/// full catalog of 90 conversations and 140 files, thinking off.
enum SmartSearch {

    private static let model = "sonnet"
    private static let catalogSize = 90
    private static let promptChars = 90
    private static let fileMatches = 80
    private static let fileRecent = 60

    /// nil when the model could not be reached — the caller says so plainly.
    /// One line per search in ~/.claude/peach-smart.log — what was asked, how
    /// long it took, how many came back, and why it failed. Reported 3.10:
    /// "the smart search did not work", and without a record there was no way
    /// to tell which link broke.
    static func log(_ text: String) {
        let url = Terminals.home.appendingPathComponent(".claude/peach-smart.log")
        let line = ISO8601DateFormatter().string(from: Date()) + " " + text + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(line.utf8))
        } else { try? Data(line.utf8).write(to: url) }
    }

    static func run(_ question: String) -> [[String: Any]]? {
        let began = Date()
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { log("skip short: \(q)"); return nil }
        guard let claude = Terminals.claudePath() else { log("no claude binary found"); return nil }
        let result = runWith(claude, q)
        log(String(format: "%.1fs ", Date().timeIntervalSince(began))
            + (result.map { "\($0.count) results" } ?? "FAILED: \(lastError)") + " · " + q)
        return result
    }

    private static var lastError = ""

    private static func runWith(_ claude: String, _ q: String) -> [[String: Any]]? {
        let t0 = Date()
        Index.refresh()
        let chats = catalog(q)
        let files = fileCatalog(q)
        guard !chats.isEmpty || !files.isEmpty else { return [] }

        var lines: [String] = []
        var chatKey: [String: Entry] = [:]
        var fileKey: [String: Work] = [:]
        for (n, e) in chats.enumerated() {
            let key = "c\(n + 1)"
            chatKey[key] = e
            lines.append("[\(key)] \(e.when) · \(e.title) · \(e.project) :: " + e.prompts.joined(separator: " / "))
        }
        lines.append("")
        lines.append("FILES (path below the documents folder, date):")
        for (n, w) in files.enumerated() {
            let key = "f\(n + 1)"
            fileKey[key] = w
            lines.append("[\(key)] \(Works.relative(w.path)) · \(Works.day.string(from: w.modified))")
        }
        let prompt = """
        You help find a past conversation or a file the user made with an assistant.
        Below are conversations (ids c…: date · title · folder :: things the user typed)
        and files (ids f…: path · date). Newest first.
        The user is looking for: \(q)

        If the user asks for a draft, document, page, image or file, prefer files.
        Answer with at most 6 lines, best match first, in exactly this form:
        <id> | <a few words, in the user's language, saying why it matches>
        If nothing fits, answer with the single word NONE.

        \(lines.joined(separator: "\n"))
        """
        let built = Date().timeIntervalSince(t0)
        if ProcessInfo.processInfo.environment["PEACH_DUMP"] != nil {
            try? prompt.write(toFile: NSTemporaryDirectory() + "peach-smart-prompt.txt", atomically: true, encoding: .utf8)
        }

        let t1 = Date()
        guard let answer = ask(claude, prompt) else { return nil }
        log(String(format: "catalog %.1fs · %d chars · %d chats · %d files · model %.1fs",
                   built, prompt.count, chats.count, files.count, Date().timeIntervalSince(t1)))
        lastError = ""
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastError = "empty answer"; return nil }
        var out: [[String: Any]] = []
        var used = Set<String>()
        for row in answer.split(separator: "\n") {
            let parts = row.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: " []\t"))
            }
            guard let key = parts.first, !used.contains(key) else { continue }
            let why = parts.count > 1 ? parts[1] : ""
            if let e = chatKey[key] {
                used.insert(key)
                out.append(["sid": e.sid, "title": e.title, "project": e.project,
                            "when": e.when, "why": why, "total": 0,
                            "hits": [] as [[String: Any]]])
            } else if let w = fileKey[key] {
                used.insert(key)
                var row = Works.row(w)
                row["file"] = true
                row["why"] = why
                out.append(row)
            }
        }
        return Array(out.prefix(6))
    }

    private struct Entry {
        let sid: String
        let title: String
        let project: String
        let when: String
        let prompts: [String]
    }

    private static let day = Works.day

    /// Recent conversations, plus older ones whose title shares a word with
    /// the question. Two of the user's prompts each, short — the title carries
    /// most of the meaning, and every character here is model time.
    private static func catalog(_ q: String) -> [Entry] {
        let ws = QuickFind.words(q)
        let shards = Index.shardsByRecency()
        var picked: [String] = Array(shards.prefix(catalogSize))
        for path in shards.dropFirst(catalogSize).prefix(600) where picked.count < catalogSize + 40 {
            let sid = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if QuickFind.score(Titles.known(sid).lowercased(), ws) > 0 { picked.append(path) }
        }
        let entries: [Entry] = picked.compactMap { path in
            let sid = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            var mine: [String] = []
            var last: Double = 0
            for row in text.split(separator: "\n") {
                let f = row.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard f.count == 3 else { continue }
                last = Double(f[0]) ?? last
                if f[1] == "y" {
                    mine.append(String(f[2].prefix(promptChars)).replacingOccurrences(of: "\n", with: " "))
                }
            }
            guard !mine.isEmpty else { return nil }
            let chosen = mine.count <= 2 ? mine : [mine[0], mine[mine.count - 1]]
            var title = Titles.of(sid)
            if title.isEmpty { title = "untitled" }
            return Entry(sid: sid, title: title, project: Index.project(of: sid),
                         when: last > 0 ? day.string(from: Date(timeIntervalSince1970: last)) : "",
                         prompts: chosen)
        }
        Titles.save()
        return entries
    }

    /// Files whose path shares a word with the question, best first, then
    /// the newest documents and pages to fill the rest.
    private static func fileCatalog(_ q: String) -> [Work] {
        let ws = QuickFind.words(q)
        let all = Works.everything()
        var scored: [(Int, Work)] = []
        for w in all {
            let s = QuickFind.score(Works.relative(w.path).lowercased(), ws)
            if s > 0 { scored.append((s, w)) }
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.modified > $1.1.modified }
        var out = scored.prefix(fileMatches).map(\.1)
        let images: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg"]
        for w in all where out.count < fileMatches + fileRecent {
            guard !images.contains((w.path as NSString).pathExtension.lowercased()),
                  !out.contains(where: { $0.path == w.path }) else { continue }
            out.append(w)
        }
        return out
    }

    private static func ask(_ claude: String, _ prompt: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = ["-p", "--model", model, "--no-session-persistence", "--tools", "",
                       "--strict-mcp-config", "--setting-sources", ""]
        // ⛔ Measured 7.10: the command thinks before it answers unless told
        //    not to, and that thinking was 10–50 of the 15–58 seconds the user
        //    waited. With thinking off: Haiku 3s but picked the wrong file;
        //    Sonnet 4–7s and picked the right draft on every run.
        var env = ProcessInfo.processInfo.environment
        env["MAX_THINKING_TOKENS"] = "0"
        p.environment = env
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        let errPipe = Pipe()
        p.standardError = errPipe
        do { try p.run() } catch { lastError = "launch: \(error)"; return nil }
        input.fileHandleForWriting.write(Data(prompt.utf8))
        try? input.fileHandleForWriting.close()
        // A hung call must not hang the search screen.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: killer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0 else {
            let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            lastError = "exit \(p.terminationStatus): " + String((err + String(decoding: data, as: UTF8.self)).prefix(300))
                .replacingOccurrences(of: "\n", with: " ")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
