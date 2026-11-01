import Foundation

/// פקודת־לוכסן אחת, כפי שהיא זמינה במסוף.
struct Command {
    let name: String
    let hint: String
    /// ‏"מובנית" · "פקודה" · "סקיל"
    let kind: String
    /// פקודה שהתשובה שלה חיה **רק במסוף** — בורר, טבלה או לוח שמצוירים
    /// בממשק ואינם נכתבים ליומן. פיץ׳ קורא את היומן, ולכן פלט כזה אינו
    /// מגיע אליו לעולם. אחרי שליחה כזו הוא מקפיץ את חלון־המסוף.
    let interactive: Bool
}

/// רשימת הפקודות שאפשר להקליד. פיץ׳ אינו מפרש אף אחת מהן — הוא מזריק את
/// הטקסט למסוף, ושם קלוד מבצע. הרשימה כאן היא השלמה בלבד, וזו הסיבה שהיא
/// נקראת מהדיסק ולא מקובעת: סקיל שנוסף אתמול חייב להופיע היום.
enum Commands {

    private static let lock = NSLock()
    private static var cache: [Command] = []
    private static var stamp = Date.distantPast

    static func all() -> [Command] {
        lock.lock()
        let fresh = Date().timeIntervalSince(stamp) < 60 ? cache : nil
        lock.unlock()
        if let fresh { return fresh }

        var list = builtins
        list.append(contentsOf: userCommands())
        list.append(contentsOf: skills())
        list.append(contentsOf: agents())

        lock.lock(); cache = list; stamp = Date(); lock.unlock()
        return list
    }

    static func matching(_ prefix: String) -> [Command] {
        let needle = prefix.lowercased()
        guard !needle.isEmpty else { return all() }
        let list = all()
        // התאמה בתחילת השם קודמת להתאמה באמצע — זה מה שהעין מצפה לו
        let head = list.filter { $0.name.lowercased().hasPrefix(needle) }
        let rest = list.filter {
            !$0.name.lowercased().hasPrefix(needle)
                && ($0.name.lowercased().contains(needle) || $0.hint.contains(prefix))
        }
        return head + rest
    }

    /// האם הטקסט שנשלח פותח בורר במסוף.
    static func opensPicker(_ text: String) -> Bool {
        let word = text.split(separator: " ").first.map(String.init) ?? text
        // ‏"מודל אופוס" אינו בורר; "מודל" לבדו הוא כן
        guard text.trimmingCharacters(in: .whitespaces) == word else { return false }
        return all().first { "/" + $0.name == word }?.interactive ?? false
    }

    // MARK: - מובנות

    private static let builtins: [Command] = [
        Command(name: "clear", hint: Lang.t("לנקות את ההקשר ולהתחיל שיחה חדשה", "Clear the context and start fresh"), kind: Lang.t("מובנית", "built-in"), interactive: false),
        Command(name: "compact", hint: Lang.t("לכווץ את השיחה ולשמור את התמצית", "Compact the conversation and keep the gist"), kind: Lang.t("מובנית", "built-in"), interactive: false),
        Command(name: "context", hint: Lang.t("מה תופס את חלון־ההקשר", "What is filling the context window"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "cost", hint: Lang.t("כמה עלתה השיחה", "What the conversation cost"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "usage", hint: Lang.t("מכסת השימוש", "Usage quota"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "status", hint: Lang.t("מצב החיבור והחשבון", "Connection and account status"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "model", hint: Lang.t("בחירת מודל", "Pick a model"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "config", hint: Lang.t("הגדרות", "Settings"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "permissions", hint: Lang.t("הרשאות כלים", "Tool permissions"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "agents", hint: Lang.t("סוכנים מותאמים", "Custom agents"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "mcp", hint: Lang.t("שרתי גישה חיצוניים", "External access servers"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "hooks", hint: Lang.t("ווים", "Hooks"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "resume", hint: Lang.t("לחזור לשיחה קודמת", "Resume an earlier conversation"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "rewind", hint: Lang.t("לחזור אחורה בשיחה", "Rewind the conversation"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "memory", hint: Lang.t("עריכת הזיכרון", "Edit memory"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "todos", hint: Lang.t("רשימת המשימות", "Task list"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "review", hint: Lang.t("סקירת קוד", "Code review"), kind: Lang.t("מובנית", "built-in"), interactive: false),
        Command(name: "security-review", hint: Lang.t("סקירת אבטחה", "Security review"), kind: Lang.t("מובנית", "built-in"), interactive: false),
        Command(name: "init", hint: Lang.t("לייצר קובץ־הנחיות לפרויקט", "Generate a project instructions file"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "export", hint: Lang.t("לייצא את השיחה", "Export the conversation"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "add-dir", hint: Lang.t("להוסיף תיקייה להקשר", "Add a folder to the context"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "pr-comments", hint: Lang.t("הערות על בקשת־מיזוג", "Comments on a pull request"), kind: Lang.t("מובנית", "built-in"), interactive: false),
        Command(name: "doctor", hint: Lang.t("אבחון התקנה", "Install diagnostics"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "help", hint: Lang.t("עזרה", "Help"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "release-notes", hint: Lang.t("מה חדש", "What is new"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "vim", hint: Lang.t("מצב עריכה", "Edit mode"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "output-style", hint: Lang.t("סגנון הפלט", "Output style"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "statusline", hint: Lang.t("שורת־המצב", "Status line"), kind: Lang.t("מובנית", "built-in"), interactive: true),
        Command(name: "exit", hint: Lang.t("לצאת מהמסוף", "Exit the terminal"), kind: Lang.t("מובנית", "built-in"), interactive: false)
    ]

    // MARK: - מהדיסק

    private static func userCommands() -> [Command] {
        let dir = Terminals.home.appendingPathComponent(".claude/commands")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "md" }.map { file in
            let name = file.deletingPathExtension().lastPathComponent
            return Command(name: name,
                           hint: frontMatter(file, key: "description"),
                           kind: Lang.t("פקודה", "command"),
                           interactive: false)
        }.sorted { $0.name < $1.name }
    }

    private static func skills() -> [Command] {
        let dir = Terminals.home.appendingPathComponent(".claude/skills")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items.compactMap { folder -> Command? in
            let skill = folder.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skill.path) else { return nil }
            return Command(name: folder.lastPathComponent,
                           hint: frontMatter(skill, key: "description"),
                           kind: Lang.t("סקיל", "skill"),
                           interactive: false)
        }.sorted { $0.name < $1.name }
    }

    /// סוכנים מותאמים. הם אינם פקודות־לוכסן, אבל הם חלק מספר־היכולות —
    /// ומי שמחפש "מי יודע לעצב" רוצה למצוא אותם באותה רשימה.
    private static func agents() -> [Command] {
        let dir = Terminals.home.appendingPathComponent(".claude/agents")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "md" }.map { file in
            let name = file.deletingPathExtension().lastPathComponent
            return Command(name: name,
                           hint: frontMatter(file, key: "description"),
                           kind: Lang.t("סוכן", "agent"),
                           interactive: false)
        }.sorted { $0.name < $1.name }
    }

    /// ערך מתוך כותרת־המסמך. נקרא מראש־הקובץ בלבד — הסקילים ארוכים מאוד.
    private static func frontMatter(_ url: URL, key: String) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4000)) ?? Data()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n",
                                                               omittingEmptySubsequences: false)
        for (i, line) in lines.enumerated() {
            guard line.hasPrefix(key + ":") else { continue }
            var value = String(line.dropFirst(key.count + 1))
                .trimmingCharacters(in: .whitespaces)

            // ‏">" או "|" פירושם שהערך ממשיך בשורות המוזחות שאחריו.
            // בלי זה שני סקילים הציגו סימן בודד במקום תיאור.
            if value == ">" || value == "|" || value == ">-" || value == "|-" {
                var parts: [String] = []
                var j = i + 1
                while j < lines.count {
                    let next = lines[j]
                    guard next.hasPrefix(" ") || next.hasPrefix("\t") else { break }
                    parts.append(next.trimmingCharacters(in: .whitespaces))
                    j += 1
                }
                value = parts.joined(separator: " ")
            }

            if value.hasPrefix("\"") { value.removeFirst() }
            if value.hasSuffix("\"") { value.removeLast() }
            return String(value.prefix(220))
        }
        return ""
    }
}
