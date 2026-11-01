import Foundation

/// One file a conversation produced.
struct Output {
    let path: String
    /// When it first appeared in the conversation — the order the user asked for.
    let at: Date
}

/// The files one conversation made, in the order it made them.
///
/// Requested 3.10: "inside a conversation, show that conversation's outputs,
/// neatly, in the order they were created". The global outputs screen lists
/// everything under ~/Documents/claude by modification time, which mixes all
/// sessions and reshuffles as files are touched.
///
/// A file counts when the main thread (not a background agent) either wrote
/// it with a file tool, or named it in its own prose — the standing rule is
/// that every handed-over file is named by absolute path in the reply. It
/// must still exist on disk.
///
/// The transcript is read incrementally: the offset already scanned is kept,
/// so a 25 MB log costs one full pass and then only its new tail.
enum Outputs {

    private struct Seen {
        var offset: UInt64 = 0
        var order: [String] = []
        var first: [String: Date] = [:]
    }

    private static let lock = NSLock()
    private static var memo: [String: Seen] = [:]

    private static let writeTools: Set<String> = ["Write", "NotebookEdit", "Edit", "MultiEdit"]
    private static let kept: Set<String> = [
        "md", "markdown", "txt", "html", "pdf", "png", "jpg", "jpeg", "gif", "webp", "svg",
        "csv", "tsv", "xlsx", "docx", "pptx", "json", "py", "js", "swift", "sh", "css",
        "php", "mp4", "mov", "yml", "yaml", "log"
    ]

    static func of(sessionID: String) -> [Output] {
        guard !sessionID.isEmpty, let url = Sessions.transcriptURL(for: sessionID) else { return [] }
        lock.lock()
        var seen = memo[sessionID] ?? Seen()
        lock.unlock()

        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            if size < seen.offset { seen = Seen() }          // rewritten log
            if size > seen.offset {
                try? handle.seek(toOffset: seen.offset)
                let data = (try? handle.readToEnd()) ?? Data()
                // Only whole lines; a half-written last line waits for next time.
                if let lastNL = data.lastIndex(of: 0x0A) {
                    scan(data[data.startIndex...lastNL], into: &seen)
                    seen.offset += UInt64(lastNL - data.startIndex + 1)
                }
            }
        }

        lock.lock()
        memo[sessionID] = seen
        if memo.count > 60 { memo.removeAll() }
        lock.unlock()

        let fm = FileManager.default
        return seen.order.compactMap { path in
            var dir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &dir), !dir.boolValue else { return nil }
            return Output(path: path, at: seen.first[path] ?? .distantPast)
        }
    }

    private static let assistant = Array("\"assistant\"".utf8)

    private static func scan(_ data: Data.SubSequence, into seen: inout Seen) {
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let row = data[start..<end]
            start = end < data.endIndex ? end + 1 : end
            guard contains(row, assistant),
                  let obj = try? JSONSerialization.jsonObject(with: Data(row)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  obj["isSidechain"] as? Bool != true,
                  let message = obj["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { continue }
            let when = Sessions.time(obj["timestamp"]) ?? Date()
            for block in blocks {
                switch block["type"] as? String {
                case "tool_use":
                    guard writeTools.contains(block["name"] as? String ?? ""),
                          let input = block["input"] as? [String: Any],
                          let path = (input["file_path"] ?? input["notebook_path"]) as? String
                    else { continue }
                    note(path, when, &seen)
                case "text":
                    for path in Documents.paths(in: block["text"] as? String ?? "") {
                        note(Documents.expand(path), when, &seen)
                    }
                default:
                    continue
                }
            }
        }
    }

    private static func note(_ path: String, _ when: Date, _ seen: inout Seen) {
        let ext = (path as NSString).pathExtension.lowercased()
        guard kept.contains(ext), seen.first[path] == nil else { return }
        // Scratch files of the session itself are not outputs.
        if path.contains("/scratchpad/") || path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") {
            return
        }
        seen.first[path] = when
        seen.order.append(path)
    }

    private static func contains(_ slice: Data.SubSequence, _ needle: [UInt8]) -> Bool {
        let n = needle.count
        guard slice.count >= n else { return false }
        var i = slice.startIndex
        let last = slice.endIndex - n
        while i <= last {
            if slice[i] == needle[0] {
                var j = 1
                while j < n && slice[i + j] == needle[j] { j += 1 }
                if j == n { return true }
            }
            i += 1
        }
        return false
    }
}
