import Foundation

/// Conversation titles, cheap enough to read for hundreds of conversations.
///
/// Measured 7.10: the smart search took 29–42 seconds while a bare model call
/// takes 3. Most of the gap was naming the catalog: `Sessions.state` parses a
/// conversation's log to find its title, and the catalog asked for 150 of
/// them. Here a title costs one `grep` over the log the first time, and a
/// dictionary lookup after that — kept on disk across launches, refreshed
/// only when the log grew.
enum Titles {

    private static let file = Terminals.home.appendingPathComponent(".claude/peach-titles.json")
    private static let lock = NSLock()
    /// sid → [size, title]
    private static var memo: [String: [Any]]?

    static func of(_ sid: String) -> String {
        let custom = Names.name(for: sid)
        if !custom.isEmpty { return custom }
        guard let url = Sessions.transcriptURL(for: sid) else { return "" }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        load()
        lock.lock()
        let hit = memo?[sid]
        lock.unlock()
        // A title is set early and rarely changes, so a log that grew by less
        // than a megabyte keeps the title it had.
        if let hit, hit.count == 2, let was = hit[0] as? Int, let title = hit[1] as? String,
           size - was < 1_000_000 { return title }

        let raw = Terminals.shell("/usr/bin/grep", ["-a", "-o", "-E",
            "\"(customTitle|aiTitle)\":\"[^\"]{1,200}\"", url.path]) ?? ""
        var title = "", custom2 = ""
        for row in raw.split(separator: "\n") {
            guard let colon = row.firstIndex(of: ":") else { continue }
            let value = String(row[row.index(after: colon)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if row.hasPrefix("\"customTitle\"") { custom2 = value } else { title = value }
        }
        let found = custom2.isEmpty ? title : custom2
        lock.lock()
        memo?[sid] = [size, found]
        lock.unlock()
        return found
    }

    /// The title only if it is already known — for code that runs on every
    /// keystroke and must never wait on a first read.
    static func known(_ sid: String) -> String {
        let custom = Names.name(for: sid)
        if !custom.isEmpty { return custom }
        load()
        lock.lock(); defer { lock.unlock() }
        return (memo?[sid]?.last as? String) ?? ""
    }

    private static func load() {
        lock.lock(); defer { lock.unlock() }
        guard memo == nil else { return }
        let data = (try? Data(contentsOf: file)) ?? Data()
        memo = (try? JSONSerialization.jsonObject(with: data)) as? [String: [Any]] ?? [:]
    }

    /// Reads the titles of the most recent conversations ahead of time, in
    /// the background, so the first search does not pay for them.
    static func warm(_ count: Int = 400) {
        for path in Index.shardsByRecency().prefix(count) {
            _ = of(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        save()
    }

    /// Written after a search, not after every title.
    static func save() {
        lock.lock(); let snapshot = memo; lock.unlock()
        guard let snapshot, let data = try? JSONSerialization.data(withJSONObject: snapshot) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// The instant half of the finder: what matches by name, as you type.
///
/// Requested 7.10: "find a conversation or an artifact in a second, from one
/// search". The word search reads what was said inside conversations; this
/// adds the two things it never looked at — file names and folder names under
/// ~/Documents/claude, and conversation titles. No model, no waiting.
enum QuickFind {

    private static let fileLimit = 8
    private static let chatLimit = 6
    private static let chatScan = 400

    /// Lower-cased words, each with its Hebrew prefix-stripped form, so that
    /// "לניוזלטר" also matches a file named "ניוזלטר".
    /// Words that ask rather than describe — "find me the …" names nothing.
    private static let filler: Set<String> = [
        "את", "של", "על", "לי", "עם", "אני", "זה", "זאת", "מה", "איפה", "תמצא", "תמצאי", "מצא",
        "למצוא", "חפש", "תחפש", "השיחה", "שיחה", "שבה", "הקובץ", "קובץ", "איזה", "ההוא", "שעשינו",
        "the", "a", "an", "of", "find", "me", "where", "that", "with", "for", "and"
    ]

    static func words(_ q: String) -> [[String]] {
        q.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "?" }).map(String.init)
            .filter { $0.count >= 2 && !filler.contains($0) }
            .map { w in
                var forms = [w]
                let prefixes: [Character] = ["ה", "ל", "ב", "ו", "מ", "ש", "כ"]
                if w.count >= 4, let first = w.first, prefixes.contains(first) {
                    forms.append(String(w.dropFirst()))
                }
                return forms
            }
    }

    /// How many of the query's words appear in the text (any form counts).
    static func score(_ hay: String, _ words: [[String]]) -> Int {
        words.reduce(0) { n, forms in n + (forms.contains { hay.contains($0) } ? 1 : 0) }
    }

    static func files(_ q: String) -> [[String: Any]] {
        let ws = words(q)
        guard !ws.isEmpty else { return [] }
        // Every word must hit — one word of three matches half the disk.
        let need = ws.count
        var scored: [(Int, Work)] = []
        for w in Works.everything() {
            let name = w.name.lowercased()
            let hay = Works.relative(w.path).lowercased()
            let s = score(hay, ws)
            guard s >= need else { continue }
            // A hit in the file's own name ranks above a hit in its folder.
            scored.append((s + score(name, ws), w))
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.modified > $1.1.modified }
        return scored.prefix(fileLimit).map { Works.row($0.1) }
    }

    static func chats(_ q: String) -> [[String: Any]] {
        let ws = words(q)
        guard !ws.isEmpty else { return [] }
        var out: [[String: Any]] = []
        for path in Index.shardsByRecency().prefix(chatScan) {
            let sid = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let title = Titles.known(sid)
            let project = Index.project(of: sid)
            guard score((title + " " + project).lowercased(), ws) >= ws.count else { continue }
            let at = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            out.append(["sid": sid, "title": title.isEmpty ? Lang.t("שיחה ללא שם", "untitled conversation") : title,
                        "project": project, "when": at.map { Works.day.string(from: $0) } ?? "",
                        "total": 0, "hits": [] as [[String: Any]]])
            if out.count >= chatLimit { break }
        }
        return out
    }
}
