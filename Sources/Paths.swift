import Foundation

/// Where Peach looks for the user's work. Each one is a setting, so Peach
/// does not assume one machine's folder layout:
///
///     defaults write org.hameretz2.peach workRoot ~/Projects/notes
///     defaults write org.hameretz2.peach questionsFile ~/Projects/notes/questions.md
///     defaults write org.hameretz2.peach handoffsDir ~/Projects/notes/handoffs
enum Paths {

    private static func setting(_ key: String) -> URL? {
        guard let p = UserDefaults.standard.string(forKey: key), !p.isEmpty else { return nil }
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
    }

    /// The folder listed in the outputs screen and offered by Open.
    static var workRoot: URL {
        setting("workRoot") ?? Terminals.home.appendingPathComponent("Documents/claude")
    }

    /// The single questions file the questions screen reads and writes.
    static var questionsFile: URL {
        setting("questionsFile") ?? workRoot.appendingPathComponent("questions.md")
    }

    /// Where context hand-off files are written.
    static var handoffsDir: URL {
        setting("handoffsDir") ?? workRoot.appendingPathComponent("handoffs")
    }
}
