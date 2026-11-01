import Foundation
import UserNotifications

/// Pop-up notifications for open questions, answerable in the notification.
///
/// Requested 10.10 by the user: "tasks must not get stuck". When any console
/// shows an open question — an AskUserQuestion form, its review screen, or a
/// tool-permission prompt — macOS shows a notification with the session's
/// name, the question, and the options as action buttons. A click answers
/// through Terminals.choose with the confirmed submit (Control.answer).
///
/// ⇒ A click on the notification is the user's own click, so it may answer a
///   permission prompt too. Nothing else here answers anything.
///
/// No scanning of its own: `tick` runs on the state feed's queue each time
/// Peach's own screen scan finishes, over the pickers that scan found.
/// No model: plain code.
///
///   · one notification per question (keyed by StateFeed.questionID);
///   · retracted when the question leaves the screen (answered elsewhere),
///     after it has been gone for 4 s — one scan that misses a picker
///     mid-redraw does not retract and re-post it;
///   · re-posted once if still open after 10 minutes;
///   · menu: on/off, and "only after waiting N s" (UserDefaults).
final class Notify: NSObject, UNUserNotificationCenterDelegate {

    static let shared = Notify()
    /// Set by AppDelegate: bring Peach up on this conversation.
    static var onOpen: ((String) -> Void)?

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "notifyOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifyOn") }
    }
    static let waitChoices = [0, 30, 60, 120, 300]
    static var minWait: Int {
        get { UserDefaults.standard.integer(forKey: "notifyMinWait") }
        set { UserDefaults.standard.set(newValue, forKey: "notifyMinWait") }
    }

    private struct Seen {
        var first: Date
        var posted: Date?
        var reposted = false
        var missingSince: Date?
    }
    /// Touched only on StateFeed's serial queue.
    private var seen: [String: Seen] = [:]
    private var categories: [String: UNNotificationCategory] = [:]
    private var ready = false

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    /// macOS's answer for Peach: "authorized", "denied", "notDetermined"…
    static var authorization = "unknown"

    func setup() {
        center.delegate = self
        // Notifications outlive a Peach restart. Those still in Notification
        // Center count as posted, so a restart does not announce them again.
        center.getDeliveredNotifications { list in
            let now = Date()
            StateFeed.onQueue {
                for n in list where n.request.identifier.hasPrefix("peach.q.") {
                    let qid = String(n.request.identifier.dropFirst("peach.q.".count))
                    self.seen[qid] = Seen(first: n.date, posted: n.date, reposted: now.timeIntervalSince(n.date) >= 600)
                }
            }
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.ready = granted
            self.center.getNotificationSettings { s in
                Notify.authorization = ["notDetermined", "denied", "authorized", "provisional", "ephemeral"]
                    .indices.contains(s.authorizationStatus.rawValue)
                    ? ["notDetermined", "denied", "authorized", "provisional", "ephemeral"][s.authorizationStatus.rawValue] : "unknown"
                StateFeed.appendPrivate("\(ISO8601DateFormatter().string(from: Date())) notifications granted=\(granted) status=\(Notify.authorization)",
                                        to: StateFeed.dir.appendingPathComponent("notify.log"))
            }
        }
    }

    private static func id(_ qid: String) -> String { "peach.q." + qid }

    /// Over the pickers the last screen scan found. Called on StateFeed's queue.
    func tick(terms: [Terminal], pickers: [Terminals.Picker]) {
        let now = Date()
        guard Notify.enabled else {
            if !seen.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: seen.keys.map(Notify.id))
                seen.removeAll(); categories.removeAll()
                center.setNotificationCategories([])
            }
            return
        }
        var live: Set<String> = []
        for p in pickers {
            guard let term = terms.first(where: { $0.tty == p.tty }), !term.windowless else { continue }
            let qid = StateFeed.questionID(p)
            live.insert(qid)
            var s = seen[qid] ?? Seen(first: now)
            s.missingSince = nil
            // A picker our own answer just opened (next question, review
            // screen) is being handled — counted as seen, not announced.
            if Terminals.answering(p.tty) { s.first = now; seen[qid] = s; continue }
            if s.posted == nil, now.timeIntervalSince(s.first) >= Double(Notify.minWait) {
                post(p, term: term, qid: qid, again: false)
                s.posted = now
            } else if let at = s.posted, !s.reposted, now.timeIntervalSince(at) >= 600 {
                post(p, term: term, qid: qid, again: true)
                s.reposted = true
            }
            seen[qid] = s
        }
        for (qid, var s) in seen where !live.contains(qid) {
            if s.missingSince == nil { s.missingSince = now; seen[qid] = s; continue }
            guard now.timeIntervalSince(s.missingSince!) >= 4 else { continue }
            seen.removeValue(forKey: qid)
            if s.posted != nil {
                center.removeDeliveredNotifications(withIdentifiers: [Notify.id(qid)])
                Notify.trace("retract \(qid) (left the screen)")
            }
            if categories.removeValue(forKey: Notify.id(qid)) != nil {
                center.setNotificationCategories(Set(categories.values))
            }
        }
    }

    private func post(_ p: Terminals.Picker, term: Terminal, qid: String, again: Bool) {
        let kind = StateFeed.kind(p)
        let name = Control.displayName(term)
        let content = UNMutableNotificationContent()
        content.title = StateFeed.redact(name)
        switch kind {
        case "permission": content.subtitle = Lang.t("מבקש הרשאה", "asks for permission")
        case "plan": content.subtitle = Lang.t("מבקש אישור לתוכנית", "asks to approve a plan")
        case "review": content.subtitle = Lang.t("לשלוח את התשובות?", "ready to submit answers")
        default: content.subtitle = Lang.t("שואל אותך", "asks you")
        }
        if again { content.subtitle += Lang.t(" · עדיין ממתין", " · still waiting") }
        var lines: [String] = []
        if kind == "permission" || kind == "plan" { lines += p.body.prefix(3) }
        lines.append(p.question)
        if kind == "review" { lines += p.context.components(separatedBy: "\n").prefix(4) }
        content.body = StateFeed.redact(lines.filter { !$0.isEmpty }.joined(separator: "\n"))
        content.sound = again ? .default : nil
        content.userInfo = ["tty": term.tty, "qid": qid, "sid": term.sessionID]

        var actions: [UNNotificationAction] = []
        let fit = 5
        for o in p.options.prefix(fit) {
            actions.append(UNNotificationAction(identifier: "opt." + o.n,
                                                title: StateFeed.redact(String(o.label.prefix(60))),
                                                options: []))
        }
        if kind == "ask", p.freeRow > 0, !p.multi {
            actions.append(UNTextInputNotificationAction(identifier: "reply",
                                                         title: Lang.t("תשובה חופשית", "Reply"),
                                                         options: [],
                                                         textInputButtonTitle: Lang.t("שליחה", "Send"),
                                                         textInputPlaceholder: ""))
        }
        actions.append(UNNotificationAction(identifier: "open", title: Lang.t("פתיחה בפיץ׳", "Open in Peach"),
                                            options: [.foreground]))
        let cat = UNNotificationCategory(identifier: Notify.id(qid), actions: actions,
                                         intentIdentifiers: [], options: [])
        categories[Notify.id(qid)] = cat
        content.categoryIdentifier = Notify.id(qid)
        let center = self.center
        center.setNotificationCategories(Set(categories.values))
        // Categories register asynchronously; a request added in the same
        // instant can show without its buttons.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if again { center.removeDeliveredNotifications(withIdentifiers: [Notify.id(qid)]) }
            center.add(UNNotificationRequest(identifier: Notify.id(qid), content: content, trigger: nil)) { err in
                Notify.trace("post \(qid) kind=\(kind) again=\(again) actions=\(actions.count)"
                             + (err.map { " error=\($0.localizedDescription)" } ?? " ok"))
            }
        }
    }

    // MARK: - Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) { done([.banner, .list, .sound]) } else { done([.alert, .sound]) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let tty = info["tty"] as? String ?? ""
        let qid = info["qid"] as? String ?? ""
        let sid = info["sid"] as? String ?? ""
        let action = response.actionIdentifier
        if action == "open" || action == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async { Notify.onOpen?(sid) }
            done(); return
        }
        var option = "", text = ""
        if action.hasPrefix("opt.") { option = "#" + String(action.dropFirst(4)) }
        else if action == "reply", let r = response as? UNTextInputNotificationResponse { text = r.userText }
        else { done(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            defer { done() }
            guard let term = Terminals.open().first(where: { $0.tty == tty }) else {
                self.fyi(Lang.t("לא נשלח: המסוף נסגר", "Not sent: the terminal is gone")); return
            }
            // Bound to the exact question the notification showed (expect:
            // qid): if the screen moved on, nothing is typed.
            let reply = Control.answer(term: term, expect: qid, option: option, text: text,
                                       via: "notification") { _, _, _, _ in
                (true, "asaf", "The user's click on the notification")
            }
            if reply["ok"] as? Bool != true {
                let why = reply["error"] as? String ?? (reply["result"] as? String ?? "")
                self.fyi(Lang.t("לא נשלח", "Not sent") + " — " + why)
            }
        }
    }

    static func trace(_ line: String) {
        StateFeed.appendPrivate(ISO8601DateFormatter().string(from: Date()) + " " + line,
                                to: StateFeed.dir.appendingPathComponent("notify.log"))
    }

    private func fyi(_ text: String) {
        let c = UNMutableNotificationContent()
        c.title = Lang.t("פיץ׳", "Peach")
        c.body = text
        center.add(UNNotificationRequest(identifier: "peach.fyi." + UUID().uuidString, content: c, trigger: nil))
    }
}
