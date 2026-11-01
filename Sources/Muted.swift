import Foundation

/// Conversations the user took down from the top of the rack.
///
/// Requested 3.10: a conversation with an open question sticks to the top
/// even when it no longer matters. "Take down" moves it to the bottom, and it
/// stays there **only while nothing changes in it**: the mute remembers what
/// the conversation looked like when it was taken down (its last event and
/// its open question). A new message or a new question brings it back up by
/// itself, so taking a row down can never hide something new.
enum Muted {

    /// A file beside Peach's other state, so every tool that reads Peach's
    /// state sees the same mutes (a defaults domain is per-binary).
    private static var file: URL { Terminals.home.appendingPathComponent(".claude/peach-muted.json") }

    private static func all() -> [String: String] {
        if let data = try? Data(contentsOf: file),
           let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] { return map }
        // One-time carry-over from the first version, which kept them in defaults.
        return UserDefaults.standard.dictionary(forKey: "mutedRows") as? [String: String] ?? [:]
    }

    private static func save(_ map: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: map, options: [.prettyPrinted]) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func stamp(event: Date?, ask: String) -> String {
        "\(Int(event?.timeIntervalSince1970 ?? 0))|\(ask)"
    }

    static func set(_ sid: String, stamp: String?) {
        var map = all()
        if let stamp { map[sid] = stamp } else { map.removeValue(forKey: sid) }
        save(map)
    }

    /// True while the conversation is exactly as it was when taken down.
    /// Anything new clears the mute.
    static func isMuted(_ sid: String, stamp: String) -> Bool {
        guard let was = all()[sid] else { return false }
        if was == stamp { return true }
        set(sid, stamp: nil)
        return false
    }
}
