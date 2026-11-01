import AppKit
import WebKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler,
                        WKNavigationDelegate {

    private var window: NSWindow!
    private var web: WKWebView!
    private var timer: Timer?
    private var hotKey: EventHotKeyRef?
    private var findKey: EventHotKeyRef?
    private var ready = false
    /// חתימת־המצב האחרונה. ציור חוזר של אותו מצב מבזבז ומהבהב.
    private var lastPaint = ""
    private var scanning = false
    private var loginMenuItem: NSMenuItem?
    /// סדר המדף, לפי מזהי־שיחה.
    ///
    /// **הסדר קופא בכוונה.** מיון לפי פעילות בכל פעימה מקפיץ שורות מתחת
    /// לעכבר וגורם למשתמש לאבד את המקום. לכן: ממיינים פעם אחת, שיחה חדשה
    /// נכנסת בראש, וסידור מחדש קורה רק כשמבקשים אותו — ⌘R.
    private var order: [String] = []
    /// מסך־הסוכנים פתוח?
    private var agentsOpen = false
    /// ספר־היכולות פתוח?
    private var bookOpen = false
    /// מסך־התוצרים פתוח?
    private var worksOpen = false
    /// מסך־השאלות פתוח?
    private var asksOpen = false
    /// מסך־הצריכה פתוח?
    private var spendOpen = false
    /// The document fills the window as a plain reader — opened from Finder,
    /// from the Open dialog with no conversation, or from the outputs list.
    private var readerOpen = false
    /// כמה תורות־שיחה מוצגות בשיחה הפתוחה. גדל כשהמשתמש מבקש להראות מוקדם יותר,
    /// ומתאפס בכל מעבר לשיחה אחרת — אחרת שיחה חדשה נפתחת עם חלון ענק.
    private var chatWant = Transcript.turns

    // MARK: - המסמך שפתוח בגוף השיחה
    /// נשמר בין ריצות, כמו השיחה עצמה.
    private var docPath = UserDefaults.standard.string(forKey: "docPath") ?? "" {
        didSet { UserDefaults.standard.set(docPath, forKey: "docPath") }
    }
    private var docText = ""
    private var docEditing = false
    private var docNote = ""
    private var docWarn = false
    /// חותמת שמשתנה רק בפתיחה, בשמירה ובמעבר בין קריאה לעריכה.
    /// היא מה שמונע מרענון־הרקע לדרוס טיוטה שנכתבת ברגע זה.
    private var docStamp = 0
    /// השיחה שפתוחה כרגע. ריק ⇐ המדף.
    /// נשמרת בין ריצות — חלון שנפתח בקיצור־מקלדת חוזר למקום שבו היית.
    private var openSID = UserDefaults.standard.string(forKey: "openSID") ?? "" {
        didSet {
            UserDefaults.standard.set(openSID, forKey: "openSID")
            // A search's highlights belong to the conversation it opened.
            if let f = chatFind, f["sid"] as? String != openSID { chatFind = nil }
        }
    }
    /// The search that opened this conversation: its words are highlighted in
    /// the log and the clicked hit is scrolled into view. Requested 10.10:
    /// "it must mark the results inside the conversation it led to too".
    /// Keys: sid, query, ts (epoch of the clicked message, 0 = none), role,
    /// token (changes per click), ready (the window reaches the target).
    private var chatFind: [String: Any]? = nil
    private var findToken = 0
    /// Highlights showing in an open conversation view — ⌘G steps them.
    private var findActive: Bool {
        guard let f = chatFind, f["sid"] as? String == openSID, !openSID.isEmpty else { return false }
        return !searchOpen && !agentsOpen && !bookOpen && !worksOpen && !asksOpen && !spendOpen && !readerOpen
    }
    /// מצב־החיפוש: השאילתה האחרונה ותוצאותיה. ריק ⇐ החיפוש סגור.
    /// מסך־החיפוש והשאילתה נשמרים כמו מסך־השיחה — החלון חוזר למקום שבו היית.
    private var searchOpen = UserDefaults.standard.bool(forKey: "searchOpen") {
        didSet { UserDefaults.standard.set(searchOpen, forKey: "searchOpen") }
    }
    private var query = UserDefaults.standard.string(forKey: "searchQuery") ?? "" {
        didSet { UserDefaults.standard.set(query, forKey: "searchQuery") }
    }
    private var hits: [[String: Any]] = []
    /// Name matches, as you type: files under ~/Documents/claude and
    /// conversation titles. Requested 7.10 — one search for both.
    private var fileHits: [[String: Any]] = []
    private var titleHits: [[String: Any]] = []
    /// Plain-words search through the small model.
    private var smartQuery = ""
    private var smartBusy = false
    private var smartHits: [[String: Any]]?
    private var smartFailed = false
    private var searching = false
    /// הודעות שנשלחו מכאן ועדיין לא הופיעו ביומן.
    private var pending: [(text: String, at: Date)] = []

    // MARK: - חיים

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        buildWindow()
        registerHotKey()
        NotificationCenter.default.addObserver(forName: Suggest.arrived, object: nil, queue: .main) { [weak self] note in
            guard let self, note.object as? String == self.openSID else { return }
            self.lastPaint = ""
            self.scan()
        }
        // בניית האינדקס הראשונה אורכת כחצי דקה. היא רצה ברקע מרגע הפתיחה,
        // כדי שהחיפוש הראשון של המשתמש כבר ימצא אותה מוכנה.
        DispatchQueue.global(qos: .utility).async { Index.refresh(force: true) }
        // מונה־הצריכה נבנה באותו אופן: פעם אחת ברקע, ומשם מצטבר
        DispatchQueue.global(qos: .utility).async { Spend.refresh(force: true) }
        // Conversation titles for the finder, read once ahead of the first search.
        DispatchQueue.global(qos: .background).async { Titles.warm() }
        // The central console's line (peach-q) and the question pop-ups.
        // Both ride on the scans below; neither adds a scan of its own.
        Terminals.onScan = { StateFeed.poke() }
        Control.askAsaf = { [weak self] title, text, done in self?.approvalSheet(title, text, done) ?? done(false) }
        Control.viewDoc = { [weak self] path, editing in
            guard let self else { return }
            self.loadDoc(path, reader: true)
            if editing { self.editSidePane() }
        }
        Control.closeDoc = { [weak self] in self?.closeDocument() }
        Control.snapshot = { [weak self] done in
            guard let web = self?.web else { done(nil); return }
            web.takeSnapshot(with: nil) { image, _ in
                guard let image, let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff) else { done(nil); return }
                done(rep.representation(using: .png, properties: [:]))
            }
        }
        Control.cancelAsk = { [weak self] in
            if let w = self?.window, let sheet = w.attachedSheet { w.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
        }
        Control.start()
        Notify.onOpen = { [weak self] sid in self?.openSession(sid) }
        Notify.shared.setup()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.scan()
        }
        scan()
    }

    /// A Markdown or text file opened from Finder ("Open With", double-click
    /// once Peach is the default, or a drop on the Dock icon) opens in the
    /// full-window reader.
    func application(_ sender: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        showWindow()
        loadDoc(url.path, reader: true)
    }

    /// Makes Peach the default app for Markdown files, on the user's click.
    @objc private func claimMarkdown() {
        let bundle = Bundle.main.bundleIdentifier ?? "org.hameretz2.peach"
        var failed = false
        for type in ["net.daringfireball.markdown", "public.markdown"] {
            let status = LSSetDefaultRoleHandlerForContentType(type as CFString, .all, bundle as CFString)
            if status != noErr && type == "net.daringfireball.markdown" { failed = true }
        }
        note(failed ? Lang.t("לא הצלחתי להגדיר את פיץ׳ כברירת־המחדל", "Could not make Peach the default")
                    : Lang.t("קובצי md ייפתחו מעכשיו בפיץ׳", "Markdown files now open in Peach"))
    }

    /// סגירת החלון אינה יציאה — פיץ׳ נשאר במעגן, כמו כל אפליקציה שיושבת שם.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    /// לחיצה על סמל־המעגן מחזירה את החלון. בלי זה החלון נסגר ואין דרך להחזירו
    /// חוץ מקיצור־המקלדת — וזה בדיוק מה שגורם לאפליקציה להרגיש שבורה.
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showWindow() }
        return true
    }

    // MARK: - חלון

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "peach")
        // The Markdown editor (CodeMirror, bundled offline). Without it the page
        // falls back to a plain textarea, which is slow on long files.
        if let url = Bundle.main.url(forResource: "peach-editor", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        // ניגודיות: הדף כהה, ולכן הרקע שמאחוריו חייב להיות כהה גם ברגע הטעינה
        let frame = NSRect(x: 0, y: 0, width: 940, height: 620)
        web = WKWebView(frame: frame, configuration: config)
        web.setValue(false, forKey: "drawsBackground")

        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = Lang.t("פיץ׳", "Peach")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.039, green: 0.043, blue: 0.047, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.setFrameAutosaveName("PeachMain")
        window.center()

        // ‏paint לפני שהדף נטען נופל **בשקט** — לכן ההמתנה היא לאירוע־הסיום
        // האמיתי, לא להשהיית־זמן שנראית מספיקה.
        web.navigationDelegate = self
        web.loadHTMLString(Screen.html, baseURL: nil)
        showWindow()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        lastPaint = ""
        pushCommands()
        // המסמך נשמר בין ריצות בשמו בלבד — בלי טעינה מפורשת הלוח נפתח
        // עם שם קובץ ובלי שורה אחת בתוכו
        if !docPath.isEmpty { loadDoc(docPath) }
        scan()
        // Self-test hook: `defaults write org.hameretz2.peach smartSelfTest "<q>"`
        // runs one plain-words search inside the app at launch and logs it.
        if let q = UserDefaults.standard.string(forKey: "smartSelfTest"), !q.isEmpty {
            UserDefaults.standard.removeObject(forKey: "smartSelfTest")
            DispatchQueue.global(qos: .utility).async { _ = SmartSearch.run(q) }
        }
        // שאילתה שנשמרה מהריצה הקודמת מורצת מחדש, אחרת המסך נפתח עם טקסט
        // בשדה ובלי תוצאות — מצב שנראה כמו חיפוש שנכשל
        if searchOpen && query.count >= 2 { runSearch(query) }
    }

    /// רשימת הפקודות נשלחת פעם אחת לדף, והסינון קורה שם. הלכה־למעשה זה
    /// ההבדל בין השלמה מיידית לבין הלוך־ושוב על כל הקשה.
    private func pushCommands() {
        let list = Commands.all().map { command -> [String: Any] in
            ["name": command.name, "hint": command.hint,
             "kind": command.kind, "interactive": command.interactive]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("setCommands(" + json + ")", completionHandler: nil)
    }

    /// מחיל את הסדר הקפוא: מי שכבר על המדף נשאר במקומו, וחדש נכנס בראש.
    private func settle(_ units: [[String: Any]]) -> [[String: Any]] {
        guard !units.isEmpty else { return units }
        var byID: [String: [String: Any]] = [:]
        for unit in units { byID[unit["sid"] as? String ?? ""] = unit }

        let fresh = units.filter { !order.contains($0["sid"] as? String ?? "") }
        // חדשים נכנסים בראש, ובתוכם לפי פעילות — פעם אחת, ואז הם קופאים גם הם
        order = fresh.map { $0["sid"] as? String ?? "" } + order
        order = order.filter { byID[$0] != nil }
        return order.compactMap { byID[$0] }
    }

    /// שולח תוכן של קובץ לדף. ערוץ נפרד מהציור הרגיל בכוונה: תמונה מוטמעת
    /// שוקלת מגהבייטים, ואין שום סיבה לשלוח אותה שוב בכל פעימה.
    /// רשימת השיחות לשחזור, לפי דרישה בלבד — לא רוכבת על מחזור־הציור,
    /// ולכן אינה עולה כלום בכל פעימה.
    private func pushRestorable() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rows = Panel.restorable()
            guard let data = try? JSONSerialization.data(withJSONObject: rows),
                  let json = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.web.evaluateJavaScript("setRestorable(" + json + ")",
                                             completionHandler: nil)
            }
        }
    }

    private func pushAsset(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            note(Lang.t("קידוד הקובץ נכשל", "Encoding the file failed"))
            return
        }
        web.evaluateJavaScript("setAsset(" + json + ")") { [weak self] _, error in
            if let error { self?.note(Lang.t("שליחת הקובץ לדף נכשלה — ", "Sending the file to the page failed — ") + String(describing: error)) }
        }
    }

    /// מחרוזת בטוחה להעברה לדף. נתיבים מכילים גרשיים, לוכסנים ועברית —
    /// שרשור נאיבי היה שובר את הקריאה בשקט.
    private func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    /// שגיאה שמגיעה מהדף אינה נראית בשום מקום אחר. בלי השורה הזאת כרטיס
    /// נשאר על "נטען…" לנצח ואין שום רמז למה.
    private func note(_ message: String) {
        FileHandle.standardError.write(Data((Lang.t("פיץ׳: ", "Peach: ") + message + "\n").utf8))
    }

    private func runSearch(_ text: String) {
        searching = true
        lastPaint = ""
        scan()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Names first: they are instant, and usually what is wanted.
            let files = QuickFind.files(text)
            let titles = QuickFind.chats(text)
            DispatchQueue.main.async {
                guard let self, self.query == text else { return }
                self.fileHits = files
                self.titleHits = titles
                self.lastPaint = ""
                self.scan()
            }
            let found = Search.run(text)
            DispatchQueue.main.async {
                guard let self, self.query == text else { return }
                self.hits = found
                self.searching = false
                self.lastPaint = ""
                self.scan()
            }
        }
    }

    /// Serial line for the work that types into terminals (relays, renames).
    static let chores = DispatchQueue(label: "peach.chores", qos: .utility)

    /// ⛔ Reported 7.10: "clicking a conversation doesn't open it, or takes a
    ///    whole minute". A click waited for the refresh already running and
    ///    then for a whole new one. ⇒ The conversation is read and drawn on
    ///    its own, right away; the regular refresh fills in the rest after.
    private func openNow(_ sid: String) {
        let began = Date()
        let target = (chatFind?["ts"] as? Double) ?? 0
        let token = chatFind?["token"] as? Int ?? -1
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            // A search hit may sit far above the last 24 turns: widen the
            // window along the same ladder as "show earlier" until it reaches
            // the clicked message, so the page can scroll to it.
            let want = Transcript.want(reaching: target, sessionID: sid)
            DispatchQueue.main.async {
                guard let self, self.openSID == sid else { return }
                if want > self.chatWant { self.chatWant = want }
                if var f = self.chatFind, f["token"] as? Int == token { f["ready"] = true; self.chatFind = f }
            }
            let chat = Panel.chat(sessionID: sid, pending: [], want: want)
            let took = Date().timeIntervalSince(began)
            if took > 2 { SmartSearch.log(String(format: "SLOW OPEN %.1fs sid=%@", took, sid)) }
            DispatchQueue.main.async {
                guard let self, let chat, self.openSID == sid else { return }
                self.paint(units: [], chat: chat, crew: [], book: [], works: [:], asks: [],
                           live: [], spend: [:], alerts: [])
            }
        }
    }

    /// Plain-words search through the small model, for conversations and files.
    private func startSmart(_ text: String) {
        SmartSearch.log("asked from the page: " + text)
        guard text.count >= 3, text != smartQuery || smartFailed else { return }
        smartFailed = false
        smartQuery = text
        smartBusy = true
        smartHits = nil
        lastPaint = ""
        scan()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = SmartSearch.run(text)
            DispatchQueue.main.async {
                guard let self, self.smartQuery == text else { return }
                self.smartBusy = false
                self.smartHits = found
                self.smartFailed = found == nil
                self.lastPaint = ""
                self.scan()
            }
        }
    }

    /// Opens one conversation in Peach — from the page, or from a
    /// notification's "Open in Peach".
    private func openSession(_ sid: String, show: Bool = true, find: [String: Any]? = nil) {
        guard !sid.isEmpty else { if show { showWindow() }; return }
        openSID = sid
        chatFind = nil
        if let find, let q = find["query"] as? String, q.trimmingCharacters(in: .whitespaces).count >= 2 {
            findToken += 1
            let ts = (find["ts"] as? Double) ?? Double(find["ts"] as? Int ?? 0)
            chatFind = ["sid": sid, "query": q, "ts": ts, "role": find["role"] as? String ?? "",
                        "token": findToken, "ready": ts <= 0]
        }
        chatWant = Transcript.turns
        searchOpen = false
        agentsOpen = false
        bookOpen = false
        worksOpen = false
        asksOpen = false
        spendOpen = false
        query = ""
        hits = []
        pending.removeAll()
        lastPaint = ""
        scan()
        openNow(sid)
        if show { showWindow() }
    }

    /// The approval sheet for `peach-q request-click`: The user's own click in
    /// Peach's window, the only thing that mints an approval token.
    private func approvalSheet(_ title: String, _ text: String, _ done: @escaping (Bool) -> Void) {
        showWindow()
        guard window.attachedSheet == nil else { done(false); return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: Lang.t("אישור", "Approve"))
        alert.addButton(withTitle: Lang.t("לא", "Decline"))
        alert.beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn) }
    }

    @objc private func toggleNotify(_ item: NSMenuItem) {
        Notify.enabled.toggle()
        item.state = Notify.enabled ? .on : .off
        StateFeed.poke()
    }

    @objc private func setNotifyWait(_ item: NSMenuItem) {
        Notify.minWait = item.tag
        item.menu?.items.forEach { $0.state = $0.tag == item.tag ? .on : .off }
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc fileprivate func toggleWindow() {
        if window.isVisible && NSApp.isActive {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    // MARK: - סריקה וציור

    /// ⛔ **קליק שנפל על סריקה שרצה נעלם.** קודם `scan` יצא מיד כשסריקה
    ///    אחרת רצה, והמסך התחלף רק בפעימת־הטיימר הבאה — עד שתי שניות
    ///    שבהן שום דבר לא קורה אחרי לחיצה. עכשיו הבקשה נרשמת ורצה מיד
    ///    כשהסריקה שלפניה נגמרת.
    private var queued = false

    private func scan() {
        guard ready else { return }
        if scanning { queued = true; return }
        scanning = true
        // הודעה ממתינה שלא נחתה תוך שתי דקות כנראה לא תיחת — עדיף שתיעלם
        // מהמסך מאשר שתישאר תלויה שם ותיראה כאילו נשלחה
        pending.removeAll { Date().timeIntervalSince($0.at) > 120 }
        let sid = openSID
        let showAgents = agentsOpen
        let showBook = bookOpen
        let showWorks = worksOpen
        let showAsks = asksOpen
        let showSpend = spendOpen
        let want = chatWant
        let texts = pending.map(\.text)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let began = Date()
            // ⛔ Reported 7.10: a click on a conversation waited behind these
            //    two — they type into terminals and wait for them to go idle.
            //    They run on their own line now and never hold up the screen.
            AppDelegate.chores.async {
                Relay.tick(Terminals.open())
                Names.tick(Terminals.open())
            }
            let chat = sid.isEmpty ? nil : Panel.chat(sessionID: sid, pending: texts, want: want)
            let chatTook = Date().timeIntervalSince(began)
            // ⛔ מסך־ריק אינו מצב לגיטימי. כשיש שיחה פתוחה אין מציירים את המדף,
            //    ולכן שיחה ש**לא נמצאה** הותירה `units` ריק ו-`chat` ריק — כלומר
            //    חלון שחור לגמרי, בלי הסבר ובלי דרך חזרה חוץ מכפתור אחד.
            //    ⚠ וזה קורה בקלות: `openSID` נשמר בין ריצות, והמסוף שלו כבר נסגר.
            //    ⇒ שיחה שאיננה מחזירה למדף. **תמיד יש לאן לנחות.**
            let lost = !sid.isEmpty && chat == nil
            let units = (sid.isEmpty || lost) ? Panel.units() : []
            // ⇒ וכשיש שיחה פתוחה, עדיין בודקים מי שואל במקום אחר. בלי זה
            //   השאלה מחכה עד שתחזור למדף — נמדד: 4:29 של עיוורון.
            let alerts = (sid.isEmpty || lost) ? [] : Panel.alerts(excluding: sid)
            let crew = showAgents ? Panel.agents() : []
            let book = showBook ? Panel.book() : []
            let works: [String: Any] = showWorks ? Panel.works() : [:]
            let asks = showAsks ? Panel.asks() : []
            let live = showAsks ? Panel.liveAsks() : []
            // הרענון זול אחרי הבנייה הראשונה, אבל אין סיבה להריץ אותו כשהמסך סגור
            if showSpend { Spend.refresh() }
            let spend: [String: Any] = showSpend ? Panel.spend() : [:]
            let took = Date().timeIntervalSince(began)
            if took > 3 {
                SmartSearch.log(String(format: "SLOW SCAN %.1fs (chat %.1fs) sid=%@ works=%@ agents=%@",
                                       took, chatTook, sid, showWorks ? "y" : "n", showAgents ? "y" : "n"))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                // ⇒ המצב השתנה בזמן שהסריקה רצה: מה שנאסף מתאר מסך אחר
                if sid != self.openSID || showSpend != self.spendOpen {
                    self.queued = false
                    self.scan()
                    return
                }
                if lost { self.openSID = ""; self.pending.removeAll() }
                self.paint(units: units, chat: chat, crew: crew, book: book,
                           works: works, asks: asks, live: live, spend: spend,
                           alerts: alerts)
                if self.queued { self.queued = false; self.scan() }
            }
        }
    }

    private func paint(units: [[String: Any]], chat: [String: Any]?,
                       crew: [[String: Any]], book: [[String: Any]],
                       works: [String: Any], asks: [[String: Any]],
                       live: [[String: Any]], spend: [String: Any],
                       alerts: [[String: Any]]) {
        var payload: [String: Any] = ["units": settle(units), "clock": Panel.clock()]
        if agentsOpen { payload["crew"] = crew }
        if bookOpen { payload["book"] = book }
        if worksOpen { payload["works"] = works }
        if asksOpen { payload["asks"] = asks; payload["live"] = live }
        if spendOpen { payload["spend"] = spend }
        if let chat { payload["chat"] = chat }
        if let f = chatFind, f["sid"] as? String == openSID { payload["find"] = f }
        hygieneItem?.title = Relay.todayLine()
        payload["alerts"] = alerts
        if searchOpen {
            payload["search"] = ["query": query, "hits": hits,
                                 "files": fileHits, "titles": titleHits,
                                 "busy": searching, "building": Index.pending,
                                 "smartQuery": smartQuery, "smartBusy": smartBusy,
                                 "smartFailed": smartFailed,
                                 "smart": smartHits ?? []]
        }
        if readerOpen && !docPath.isEmpty { payload["reader"] = true }
        if !docPath.isEmpty {
            payload["doc"] = [
                "path": docPath,
                "name": Documents.shorten(docPath),
                "text": docText,
                "editing": docEditing,
                "note": docNote,
                "warn": docWarn,
                "stamp": docStamp,
                "paths": Documents.paths(in: docText)
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        guard json != lastPaint else { return }
        // החתימה נשמרת רק אחרי ציור שהצליח. שמירה מוקדמת הייתה מקפיאה את המסך
        // על כישלון בודד — כל סריקה הבאה נראית "זהה" ומדלגת.
        web.evaluateJavaScript("paint(" + json + ")") { [weak self] _, error in
            if let error {
                FileHandle.standardError.write(Data((Lang.t("פיץ׳: הציור נכשל — ", "Peach: painting failed — ") +
                    String(describing: error) + "\n").utf8))
                return
            }
            self?.lastPaint = json
        }
    }

    // MARK: - הודעות מהדף

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let act = body["act"] as? String else { return }
        switch act {
        case "open":
            guard let sid = body["sid"] as? String, !sid.isEmpty else { return }
            openSession(sid, show: false, find: body["find"] as? [String: Any])
        case "findClear":
            chatFind = nil
        case "agents":
            toggleAgents()
        case "book":
            toggleBook()
        case "works":
            toggleWorks()
        case "asks":
            toggleAsks()
        case "spend":
            toggleSpend()
        case "refresh":
            refreshNow()
        case "newTerminal":
            newTerminal()
        case "restorable":
            pushRestorable()
        case "restoreRun":
            guard let sids = body["sids"] as? [String], !sids.isEmpty else { return }
            // ⛔ שמונה שניות לכל שיחה — על החוט הראשי פיץ׳ היה קופא לדקה.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                Panel.restore(sids)
                // ⇒ והדף חייב לדעת שנגמר, אחרת הכפתור נשאר נעול לנצח.
                DispatchQueue.main.async {
                    self?.web.evaluateJavaScript("restoreDone()", completionHandler: nil)
                }
            }
        case "quick":
            guard let sid = body["sid"] as? String, !sid.isEmpty,
                  let text = body["text"] as? String, !text.isEmpty else { return }
            quickSend(sid: sid, text: text)
        case "wakeAll":
            wakeAll()
        case "rename":
            guard let sid = body["sid"] as? String, !sid.isEmpty else { return }
            let name = body["name"] as? String ?? ""
            Names.set(name, for: sid)
            if body["real"] as? Bool == true {
                let live = Terminals.open().contains { $0.sessionID == sid }
                Names.rename(name, sid: sid, live: live)
            }
            lastPaint = ""
            scan()
        case "relayGo":
            // "Continue in a new conversation": /clear + the continue line,
            // typed by the relay tick once the conversation is idle.
            guard let sid = body["sid"] as? String, !sid.isEmpty else { return }
            AppDelegate.chores.async { Relay.go(sid) }
            lastPaint = ""
            scan()
        case "mute":
            guard let sid = body["sid"] as? String, !sid.isEmpty else { return }
            Muted.set(sid, stamp: body["stamp"] as? String)
            lastPaint = ""
            scan()
            lastPaint = ""
            scan()
        case "more":
            // סולם ולא הכפלה: קפיצה ישר להכול על יומן בן ארבעים מגה תוקעת
            let ladder = [Transcript.turns, 80, 250, 800, Transcript.huge]
            chatWant = ladder.first(where: { $0 > chatWant }) ?? Transcript.huge
            lastPaint = ""
            scan()
        case "answer":
            guard let id = body["id"] as? String,
                  let text = body["text"] as? String, !text.isEmpty else { return }
            let error = Asks.answer(id: id, text: text)
            if !error.isEmpty { note(error) }
            lastPaint = ""
            scan()
        case "step":
            step(by: (body["by"] as? Int) ?? 1)
        case "searchOpen":
            searchOpen = true
            lastPaint = ""
            scan()
        case "back":
            // אסקייפ סוגר קודם את החיפוש, ורק אחר כך את השיחה
            if readerOpen { readerOpen = false }
            else if spendOpen { spendOpen = false }
            else if asksOpen { asksOpen = false }
            else if worksOpen { worksOpen = false }
            else if bookOpen { bookOpen = false }
            else if agentsOpen { agentsOpen = false }
            else if searchOpen { searchOpen = false; query = ""; hits = [] }
            else if !openSID.isEmpty { openSID = ""; pending.removeAll() }
            else { return }
            lastPaint = ""
            scan()
        case "findHere":
            // From the outputs screen: the same words, in the finder.
            let text = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            worksOpen = false; searchOpen = true
            query = text
            web.evaluateJavaScript("setFind(" + jsString(text) + ")", completionHandler: nil)
            if text.count >= 2 { runSearch(text) }
            startSmart(text)
        case "showInFinder":
            guard let raw = body["path"] as? String else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Documents.expand(raw))])
        case "smartSearch":
            startSmart((body["text"] as? String ?? "").trimmingCharacters(in: .whitespaces))
        case "resume":
            // Continue an old conversation in a new terminal, in its own folder.
            guard let sid = body["sid"] as? String, !sid.isEmpty else { return }
            if let tty = Terminals.open().first(where: { $0.sessionID == sid })?.tty {
                DispatchQueue.global(qos: .userInitiated).async { Terminals.raise(tty: tty) }
                return
            }
            let cwd = Sessions.state(id: sid)?.cwd ?? ""
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let error = Terminals.spawnClaude(cwd: cwd, args: ["--resume", sid])
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !error.isEmpty { self.note(error); return }
                    self.lastPaint = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.scan() }
                }
            }
        case "search":
            let text = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            query = text
            if text.count < 2 { hits = []; fileHits = []; titleHits = []; searching = false; lastPaint = ""; scan(); return }
            runSearch(text)
        case "send":
            guard let text = body["text"] as? String, !text.isEmpty, !openSID.isEmpty else { return }
            guard let tty = Terminals.open().first(where: { $0.sessionID == openSID })?.tty else {
                reportClosedTerminal()
                return
            }
            pending.append((text: text, at: Date()))
            // פקודה שפותחת בורר במסוף אינה יכולה להסתיים כאן — מקפיצים את
            // החלון כדי שאפשר יהיה לבחור שם, במקום להשאיר מסך תקוע
            let picker = Commands.opensPicker(text)
            lastPaint = ""
            scan()
            // ההזרקה חוסמת רבע שנייה בין הטקסט לאנטר — לא על החוט הראשי
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let ok = Terminals.send(text, tty: tty)
                if !ok {
                    DispatchQueue.main.async { self?.reportSendFailure() }
                } else if picker {
                    Terminals.raise(tty: tty)
                }
            }
        case "answerFree":
            guard let text = body["text"] as? String, !text.isEmpty,
                  let tty = body["tty"] as? String, !tty.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let ok = Terminals.answerFree(text, tty: tty)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.web.evaluateJavaScript("freeDone(\(ok ? "true" : "false"), " + self.jsString(Terminals.failure(tty)) + ")", completionHandler: nil)
                    self.lastPaint = ""
                    self.scan()
                }
            }
        case "answerAsk":
            // תשובה לשאלה שנשאלה במסוף. שולחים לאותו מסוף גם כשהשיחה
            // אינה הפתוחה — התור ב-⌘I עונה לכל המסופים.
            guard let pick = body["pick"] as? String, !pick.isEmpty,
                  let tty = body["tty"] as? String, !tty.isEmpty else { return }
            // A free answer goes through the free-text row (answerFree), never
            // as a digit followed by a prompt-line message.
            let follow = (body["text"] as? String) ?? ""
            lastPaint = ""
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                // choose(): arrows to the row + one Return, then waits for the
                // picker to move on, submits the review screen its answer
                // opened, and presses Return once more if nothing moved.
                let done = follow.isEmpty
                    ? Terminals.choose(pick, tty: tty)
                    : Terminals.answerFree(follow, tty: tty)
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !done { self.reportSendFailure(Terminals.failure(tty), tty: tty) }
                    self.scan()
                }
            }
        case "raiseTty":
            guard let tty = body["tty"] as? String, !tty.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async { Terminals.raise(tty: tty) }
        case "pageError":
            let line = ISO8601DateFormatter().string(from: Date()) + " " + (body["text"] as? String ?? "") + "\n"
            let url = Terminals.home.appendingPathComponent(".claude/peach-page-errors.log")
            if let h = try? FileHandle(forWritingTo: url) {
                _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(line.utf8)); try? h.close()
            } else { try? Data(line.utf8).write(to: url) }
        case "log":
            note(Lang.t("דף: ", "page: ") + String(describing: body["text"] ?? ""))
        case "raise":
            raiseTerminal()
        case "openDoc":
            guard let path = body["path"] as? String else { return }
            loadDoc(path, reader: openSID.isEmpty || worksOpen || body["reader"] as? Bool == true)
        case "closeDoc":
            readerOpen = false
            docPath = ""
            docText = ""
            docEditing = false
            docNote = ""
            lastPaint = ""
            scan()
        case "editDoc":
            guard !docPath.isEmpty else { return }
            docEditing = true
            docNote = Lang.t("בעריכה", "editing")
            docWarn = false
            docStamp += 1
            lastPaint = ""
            scan()
        case "saveDoc":
            guard let text = body["text"] as? String, !docPath.isEmpty else { return }
            let error = Documents.write(docPath, text: text)
            docText = text
            // ⌘S keeps the editor open, and the stamp unchanged so the page
            // does not reset the textarea (and its caret and undo) under the typist.
            if body["stay"] as? Bool != true || !error.isEmpty {
                docEditing = false
                docStamp += 1
            }
            docWarn = !error.isEmpty
            docNote = error.isEmpty ? Lang.t("נשמר ", "saved ") + Panel.clock() : error
            lastPaint = ""
            scan()
        case "asset":
            guard let path = body["path"] as? String else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let payload = Documents.asset(path)
                DispatchQueue.main.async { self?.pushAsset(payload) }
            }
        case "saveAsset":
            guard let path = body["path"] as? String,
                  let text = body["text"] as? String else { return }
            let error = Documents.write(path, text: text)
            var payload = Documents.asset(path)
            payload["note"] = error.isEmpty ? Lang.t("נשמר ", "saved ") + Panel.clock() : error
            payload["warn"] = !error.isEmpty
            if body["stay"] as? Bool == true { payload["stay"] = true }   // ⌘S keeps the card editor open
            pushAsset(payload)
        case "stash":
            guard let data = body["data"] as? String,
                  let name = body["name"] as? String else { return }
            let path = Documents.stash(base64: data, name: name)
            guard !path.isEmpty else { note(Lang.t("שמירת הקובץ שהודבק נכשלה", "Saving the pasted file failed")); return }
            web.evaluateJavaScript("attached(" + jsString(path) + ")", completionHandler: nil)
        case "reveal":
            guard let raw = body["path"] as? String else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: Documents.expand(raw)))
        case "openURL":
            guard let raw = body["url"] as? String, let url = URL(string: raw) else { return }
            NSWorkspace.shared.open(url)
        default:
            break
        }
    }

    // MARK: - קיצור־מקלדת גלובלי

    /// ‏⌘⌥P פותח וסוגר. מראה יושבת על ⌘⌥M, ולכן אין התנגשות.
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            DispatchQueue.main.async {
                let app = NSApp.delegate as? AppDelegate
                if key.id == 2 { app?.findAnywhere() } else { app?.toggleWindow() }
            }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x50454348), id: 1)   // 'PECH'
        RegisterEventHotKey(UInt32(kVK_ANSI_P),
                            UInt32(cmdKey | optionKey),
                            id, GetApplicationEventTarget(), 0, &hotKey)
        // ⌘⌥F from any app: Peach comes forward with the cursor in the finder.
        // Requested 7.10: "find a conversation or an artifact in a second".
        let find = EventHotKeyID(signature: OSType(0x50454348), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_F),
                            UInt32(cmdKey | optionKey),
                            find, GetApplicationEventTarget(), 0, &findKey)
    }

    @objc func findAnywhere() {
        showWindow()
        searchOpen = true
        lastPaint = ""
        scan()
        web.evaluateJavaScript("focusFind()", completionHandler: nil)
    }

    // MARK: - תפריט

    private func buildMenu() {
        let main = NSMenu()

        // תפריט־האפליקציה
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: Lang.t("על אודות פיץ׳", "About Peach"), action: #selector(about), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        // ⇒ הדף נבנה כמחרוזת אחת ומוזרק פעם אחת. החלפה חיה הייתה דורשת
        //   לבנות אותו מחדש באמצע ⇒ שומרים, ומבקשים הפעלה־מחדש.
        let langItem = NSMenuItem(title: Lang.isHebrew ? "Switch to English" : "מעבר לעברית",
                                  action: #selector(flipLanguage), keyEquivalent: "")
        langItem.target = self
        appMenu.addItem(langItem)

        let login = appMenu.addItem(withTitle: Lang.t("הפעלה בהתחברות", "Open at Login"),
                                    action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.enabled ? .on : .off
        loginMenuItem = login
        let relay = appMenu.addItem(withTitle: Lang.t("מסירה כשההקשר מתמלא", "Hand-off when the context fills"),
                                    action: #selector(toggleRelay), keyEquivalent: "")
        relay.target = self
        relay.state = Relay.on ? .on : .off
        let autoItem = appMenu.addItem(withTitle: Lang.t("המשך אוטומטי כשהמסירה מוכנה", "Continue automatically when the hand-off is ready"),
                                       action: #selector(toggleAutoContinue(_:)), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = Relay.autoContinue ? .on : .off
        let closeItem = appMenu.addItem(withTitle: Lang.t("סגירת שיחות שדוממות 24 שעות", "Close conversations idle for 24 hours"),
                                        action: #selector(toggleIdleClose(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.state = Relay.idleClose ? .on : .off
        // Today's one line: what was reset and what was closed.
        hygieneItem = appMenu.addItem(withTitle: Relay.todayLine(), action: nil, keyEquivalent: "")
        hygieneItem?.isEnabled = false
        // The line where Peach asks for a hand-off; the badge lights 5 points earlier.
        let lineItem = appMenu.addItem(withTitle: Lang.t("סף המסירה", "Hand-off threshold"), action: nil, keyEquivalent: "")
        let lineMenu = NSMenu()
        for pct in Relay.choices {
            let it = lineMenu.addItem(withTitle: "\(pct)%", action: #selector(setRelayLine(_:)), keyEquivalent: "")
            it.target = self
            it.tag = pct
            it.state = pct == Relay.askPercent ? .on : .off
        }
        lineItem.submenu = lineMenu
        let notifyItem = appMenu.addItem(withTitle: Lang.t("התראות על שאלות", "Question notifications"),
                                         action: #selector(toggleNotify(_:)), keyEquivalent: "")
        notifyItem.target = self
        notifyItem.state = Notify.enabled ? .on : .off
        let waitItem = appMenu.addItem(withTitle: Lang.t("להתריע רק אחרי המתנה של", "Notify only after waiting"),
                                       action: nil, keyEquivalent: "")
        let waitMenu = NSMenu()
        for sec in Notify.waitChoices {
            let label = sec == 0 ? Lang.t("מיד", "at once")
                : (sec < 60 ? Lang.t("\(sec) שניות", "\(sec) s") : Lang.t("\(sec / 60) דק׳", "\(sec / 60) min"))
            let it = waitMenu.addItem(withTitle: label, action: #selector(setNotifyWait(_:)), keyEquivalent: "")
            it.target = self
            it.tag = sec
            it.state = sec == Notify.minWait ? .on : .off
        }
        waitItem.submenu = waitMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Lang.t("הסתרת פיץ׳", "Hide Peach"), action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: Lang.t("הסתרת אחרים", "Hide Others"),
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Lang.t("יציאה מפיץ׳", "Quit Peach"), action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        // תפריט "עריכה" — בלעדיו אין ⌘C, ⌘V, ⌘X ו-⌘A בשום מקום באפליקציה.
        // מק מחווט את קיצורי־העריכה דרך התפריט הזה בלבד: בלי פריט־תפריט
        // שנושא את הקיצור, ההקשה פשוט אינה מגיעה לשרשרת־המגיבים.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: Lang.t("עריכה", "Edit"))
        editMenu.addItem(withTitle: Lang.t("ביטול", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: Lang.t("ביצוע חוזר", "Redo"), action: Selector(("redo:")),
                                    keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: Lang.t("גזירה", "Cut"), action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: Lang.t("העתקה", "Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: Lang.t("הדבקה", "Paste"), action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: Lang.t("בחירת הכל", "Select All"), action: Selector(("selectAll:")),
                         keyEquivalent: "a")
        editItem.submenu = editMenu

        // תפריט "תצוגה"
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: Lang.t("תצוגה", "View"))
        viewMenu.addItem(withTitle: Lang.t("חיפוש בכל השיחות", "Search every conversation"), action: #selector(focusSearch),
                         keyEquivalent: "f").target = self
        viewMenu.addItem(withTitle: Lang.t("פקודות המסוף", "Terminal commands"), action: #selector(openPalette),
                         keyEquivalent: "k").target = self
        // ⌘G is the agents screen, except while a search's highlights are
        // showing in a conversation: then it steps to the next match.
        viewMenu.addItem(withTitle: Lang.t("סוכני־הרקע", "Background agents"), action: #selector(agentsOrNext),
                         keyEquivalent: "g").target = self
        let prevHit = viewMenu.addItem(withTitle: Lang.t("ההתאמה הקודמת בשיחה", "Previous match in conversation"),
                                       action: #selector(findPrev), keyEquivalent: "G")
        prevHit.keyEquivalentModifierMask = [.command, .shift]
        prevHit.target = self
        viewMenu.addItem(withTitle: Lang.t("ספר־היכולות", "Capability book"), action: #selector(toggleBook),
                         keyEquivalent: "b").target = self
        viewMenu.addItem(withTitle: Lang.t("תוצרים", "Artifacts"), action: #selector(toggleWorks),
                         keyEquivalent: "y").target = self
        viewMenu.addItem(withTitle: Lang.t("שאלות שממתינות לך", "Questions waiting for you"), action: #selector(toggleAsks),
                         keyEquivalent: "i").target = self
        viewMenu.addItem(withTitle: Lang.t("צריכה", "Usage"), action: #selector(toggleSpend),
                         keyEquivalent: "j").target = self
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: Lang.t("מסוף חדש", "New terminal"), action: #selector(newTerminal),
                         keyEquivalent: "n").target = self
        let wake = viewMenu.addItem(withTitle: Lang.t("להעיר את כל הממתינים", "Wake everyone who is waiting"),
                                    action: #selector(wakeAll), keyEquivalent: "A")
        wake.keyEquivalentModifierMask = [.command, .shift]
        wake.target = self
        viewMenu.addItem(withTitle: Lang.t("להודעה האחרונה שלי", "To my last message"), action: #selector(myLast),
                         keyEquivalent: "u").target = self
        // Collapsed view: requests as headers, answers folded (requested 21.10).
        // The page owns the state and remembers it; the menu only flips it.
        let fold = viewMenu.addItem(withTitle: Lang.t("תצוגה מקופלת", "Collapsed view"),
                                    action: #selector(toggleFold), keyEquivalent: "C")
        fold.keyEquivalentModifierMask = [.command, .shift]
        fold.target = self
        viewMenu.addItem(.separator())
        let prev = viewMenu.addItem(withTitle: Lang.t("השיחה הקודמת", "Previous conversation"), action: #selector(stepBack),
                                    keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        prev.keyEquivalentModifierMask = [.option]
        prev.target = self
        let next = viewMenu.addItem(withTitle: Lang.t("השיחה הבאה", "Next conversation"), action: #selector(stepOn),
                                    keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        next.keyEquivalentModifierMask = [.option]
        next.target = self
        let livePrev = viewMenu.addItem(withTitle: Lang.t("המסוף הפעיל הקודם", "Previous active terminal"),
                                        action: #selector(stepLiveBack),
                                        keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        livePrev.keyEquivalentModifierMask = [.option, .shift]
        livePrev.target = self
        let liveNext = viewMenu.addItem(withTitle: Lang.t("המסוף הפעיל הבא", "Next active terminal"),
                                        action: #selector(stepLiveOn),
                                        keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        liveNext.keyEquivalentModifierMask = [.option, .shift]
        liveNext.target = self
        viewMenu.addItem(withTitle: Lang.t("חזרה למדף", "Back to the rack"), action: #selector(goBack),
                         keyEquivalent: "l").target = self
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: Lang.t("רענון עכשיו", "Refresh Now"), action: #selector(refreshNow),
                         keyEquivalent: "r").target = self
        viewItem.submenu = viewMenu

        // תפריט "מסמך"
        let docItem = NSMenuItem()
        main.addItem(docItem)
        let docMenu = NSMenu(title: Lang.t("מסמך", "document"))
        docMenu.addItem(withTitle: Lang.t("פתיחת מסמך…", "Open document…"), action: #selector(openDocument),
                        keyEquivalent: "o").target = self
        docMenu.addItem(withTitle: Lang.t("עריכת המסמך", "Edit document"), action: #selector(editDocument),
                        keyEquivalent: "e").target = self
        docMenu.addItem(withTitle: Lang.t("שמירה", "Save"), action: #selector(saveDocument),
                        keyEquivalent: "s").target = self
        docMenu.addItem(withTitle: Lang.t("לפתוח קובצי md תמיד בפיץ׳", "Always open Markdown in Peach"),
                        action: #selector(claimMarkdown), keyEquivalent: "").target = self
        docMenu.addItem(.separator())
        docMenu.addItem(withTitle: Lang.t("סגירת המסמך", "Close document"), action: #selector(closeDocument),
                        keyEquivalent: "w").keyEquivalentModifierMask = [.command, .shift]
        docMenu.items.last?.target = self
        docItem.submenu = docMenu

        // תפריט "חלון" — בלעדיו אין ⌘W ואין מזעור, וזה מה שמסגיר שזו אינה
        // אפליקציה רגילה
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: Lang.t("חלון", "Window"))
        windowMenu.addItem(withTitle: Lang.t("מזעור", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: Lang.t("סגירה", "Close"), action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: Lang.t("הבאת פיץ׳ לחזית", "Bring Peach to Front"), action: #selector(bringToFront),
                           keyEquivalent: "").target = self
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    @objc private func focusSearch() {
        findAnywhere()
    }

    /// פותח את לוח־הפקודות: ממקד את שורת־ההקלדה ומתחיל אותה בלוכסן.
    @objc private func openPalette() {
        showWindow()
        web.evaluateJavaScript("startCommand()", completionHandler: nil)
    }

    @objc private func agentsOrNext() {
        if findActive { web.evaluateJavaScript("findStep(1)", completionHandler: nil) } else { toggleAgents() }
    }

    @objc private func findPrev() {
        if findActive { web.evaluateJavaScript("findStep(-1)", completionHandler: nil) }
    }

    @objc private func goBack() {
        if readerOpen { readerOpen = false }
        else if searchOpen { searchOpen = false; query = ""; hits = [] }
        else if !openSID.isEmpty { openSID = ""; pending.removeAll() }
        lastPaint = ""
        scan()
    }

    /// גלילה להודעה האחרונה שהמשתמש כתב. בשיחה עמוסת־כלים היא יכולה להיות
    /// מאות שורות למעלה, וחיפוש שלה בעין הוא בדיוק מה שמעייף.
    @objc private func myLast() {
        web.evaluateJavaScript("toMine()", completionHandler: nil)
    }

    @objc private func toggleFold() {
        web.evaluateJavaScript("toggleFold()", completionHandler: nil)
    }

    @objc private func stepBack() { step(by: -1) }
    @objc private func stepOn() { step(by: 1) }

    @objc private func bringToFront() { showWindow() }

    @objc private func setRelayLine(_ item: NSMenuItem) {
        Relay.askPercent = item.tag
        item.menu?.items.forEach { $0.state = $0.tag == item.tag ? .on : .off }
        lastPaint = ""
        scan()
    }

    private var hygieneItem: NSMenuItem?

    @objc private func toggleAutoContinue(_ item: NSMenuItem) {
        Relay.autoContinue = !Relay.autoContinue
        item.state = Relay.autoContinue ? .on : .off
        Relay.hygieneLog("menu: auto-continue " + (Relay.autoContinue ? "on" : "off"))
    }

    @objc private func toggleIdleClose(_ item: NSMenuItem) {
        Relay.idleClose = !Relay.idleClose
        item.state = Relay.idleClose ? .on : .off
        Relay.hygieneLog("menu: idle close " + (Relay.idleClose ? "on" : "off"))
    }

    @objc private func toggleRelay(_ item: NSMenuItem) {
        Relay.on = !Relay.on
        item.state = Relay.on ? .on : .off
    }

    @objc private func toggleLoginItem() {
        let now = !LoginItem.enabled
        LoginItem.enabled = now
        loginMenuItem?.state = now ? .on : .off
    }

    /// אין לאן לשלוח — השיחה נפתחה מחיפוש והמסוף שלה כבר סגור.
    /// מקפיץ את חלון־המסוף של השיחה הפתוחה. זה המוצא לכל מה שפיץ׳ אינו
    /// יכול לעשות: בוררים, אסקייפ להפסקה, ושליטה ישירה במקלדת.
    /// מעבר לשיחה הקודמת או הבאה, לפי סדר המדף כפי שהוא מוצג.
    private func step(by delta: Int) {
        guard !order.isEmpty else { return }
        guard let at = order.firstIndex(of: openSID) else {
            openSID = order.first ?? ""
            pending.removeAll(); lastPaint = ""; scan(); return
        }
        let next = (at + delta + order.count) % order.count
        openSID = order[next]
        chatWant = Transcript.turns
        pending.removeAll()
        lastPaint = ""
        scan()
    }

    @objc private func stepLiveBack() { stepLive(by: -1) }
    @objc private func stepLiveOn() { stepLive(by: 1) }

    /// דפדוף בין המסופים ה**פעילים** בלבד — עובד, ממתין לך, או שואל.
    ///
    /// ⇒ ‏⌥ עם חץ עובר על כל המדף, ובמדף שיש בו עשרים מסופים דוממים זה
    ///   דפדוף ארוך אל מה שאינו קורה. כאן עוברים רק על מה שחי.
    private func stepLive(by delta: Int) {
        let current = openSID
        let shelf = order
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let live = Panel.units().compactMap { unit -> String? in
                guard (unit["state"] as? String ?? "quiet") != "quiet" else { return nil }
                let sid = unit["sid"] as? String ?? ""
                return sid.isEmpty ? nil : sid
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard !live.isEmpty else { self.note(Lang.t("אין מסוף פעיל לדלג אליו", "No active terminal to jump to")); return }
                // הסדר הוא סדר המדף כפי שהוא מוצג, כדי שהדילוג לא יקפוץ אקראית
                let ranked = shelf.filter { live.contains($0) }
                let list = ranked.isEmpty ? live : ranked
                let next: String
                if let at = list.firstIndex(of: current) {
                    next = list[(at + delta + list.count) % list.count]
                } else {
                    next = delta > 0 ? list[0] : list[list.count - 1]
                }
                self.openSID = next
                self.chatWant = Transcript.turns
                self.searchOpen = false; self.agentsOpen = false; self.bookOpen = false
                self.worksOpen = false; self.asksOpen = false; self.spendOpen = false
                self.pending.removeAll()
                self.lastPaint = ""
                self.scan()
            }
        }
    }

    private func raiseTerminal() {
        let sid = openSID
        guard !sid.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let tty = Terminals.open().first(where: { $0.sessionID == sid })?.tty else { return }
            Terminals.raise(tty: tty)
        }
    }

    private func loadDoc(_ path: String, reader: Bool = false) {
        if reader { readerOpen = true }
        // ⇒ ‏PDF אינו טקסט. פתיחה בלוח הייתה מציגה בתים גולמיים במקום מסמך.
        if Documents.kind(of: path) == "pdf" {
            NSWorkspace.shared.open(URL(fileURLWithPath: Documents.expand(path)))
            return
        }
        let result = Documents.read(path)
        docPath = Documents.expand(path)
        docText = result.text
        docEditing = false
        docWarn = !result.error.isEmpty
        docNote = result.error
        docStamp += 1
        lastPaint = ""
        scan()
    }

    @objc private func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Paths.workRoot
        panel.message = Lang.t("איזה מסמך לפתוח בגוף השיחה", "Which document to open inside the conversation")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadDoc(url.path, reader: openSID.isEmpty)
    }

    /// עריכה מהתפריט: קודם הכרטיס הפתוח בשיחה, ורק אם אין — הלוח הצדדי.
    @objc private func editDocument() {
        web.evaluateJavaScript("editTopCard()") { [weak self] handled, _ in
            guard let self, (handled as? Bool) != true else { return }
            self.editSidePane()
        }
    }

    private func editSidePane() {
        guard !docPath.isEmpty, !docEditing else { return }
        docEditing = true
        docNote = Lang.t("בעריכה", "editing")
        docWarn = false
        docStamp += 1
        lastPaint = ""
        scan()
    }

    @objc private func closeDocument() {
        guard !docPath.isEmpty else { return }
        // Unsaved edits are guarded on the page; the menu goes through it too.
        if docEditing { web.evaluateJavaScript("closeDocAsked()", completionHandler: nil); return }
        readerOpen = false
        docPath = ""
        docText = ""
        docEditing = false
        docNote = ""
        lastPaint = ""
        scan()
    }

    /// שמירה מהתפריט. הדף מחליט מה נערך — כרטיס או לוח — ושולח בחזרה את
    /// הבקשה המתאימה. שתי דרכי־שמירה שמכריעות בנפרד היו נפרדות גם בבאגים.
    @objc private func saveDocument() {
        web.evaluateJavaScript("saveAnything()", completionHandler: nil)
    }

    private func reportClosedTerminal() {
        let alert = NSAlert()
        alert.messageText = Lang.t("המסוף של השיחה הזאת סגור", "The terminal for this conversation is closed")
        alert.informativeText = Lang.t("אפשר לקרוא אותה, אבל אין לאן לשלוח. ", "You can read it, but there is nowhere to send to. ")
            + Lang.t("כדי להמשיך בה צריך לפתוח אותה מחדש במסוף.", "To carry on you need to reopen it in a terminal.")
        alert.runModal()
    }

    /// שליחה שנכשלה חייבת להיאמר. הודעה שנעלמת בשקט נראית כאילו נשלחה.
    /// An answer to a question that did not go through, with the measured
    /// reason, and one button to the terminal where it can be finished.
    private func reportSendFailure(_ reason: String, tty: String) {
        guard !reason.isEmpty else { reportSendFailure(); return }
        lastPaint = ""
        let alert = NSAlert()
        alert.messageText = Lang.t("התשובה לא נשלחה", "The answer was not sent")
        alert.informativeText = reason
        alert.addButton(withTitle: Lang.t("לחלון־המסוף", "Open the terminal"))
        alert.addButton(withTitle: Lang.t("סגירה", "Close"))
        if alert.runModal() == .alertFirstButtonReturn {
            DispatchQueue.global(qos: .userInitiated).async { Terminals.raise(tty: tty) }
        }
        scan()
    }

    private func reportSendFailure() {
        pending.removeAll()
        lastPaint = ""
        let alert = NSAlert()
        alert.messageText = Lang.t("ההודעה לא נשלחה", "The message was not sent")
        alert.informativeText = Lang.t("לא הצלחתי להגיע לחלון־המסוף. בדרך כלל זה חסר אישור ", "Could not reach the terminal window. Usually this is a missing permission for ")
            + Lang.t("אוטומציה: הגדרות המערכת ← פרטיות ואבטחה ← אוטומציה ← פיץ׳ ← מסוף.", "Automation: System Settings → Privacy & Security → Automation → Peach → Terminal.")
        alert.runModal()
        scan()
    }

    /// רענון גם מסדר את המדף מחדש לפי הפעילות עכשיו. זו הדרך היחידה
    /// שהסדר משתנה, וזו הכוונה.
    @objc private func refreshNow() {
        order = []
        lastPaint = ""
        scan()
    }

    @objc private func toggleAgents() {
        agentsOpen = !agentsOpen
        if agentsOpen { searchOpen = false; bookOpen = false; spendOpen = false }
        lastPaint = ""
        scan()
    }

    @objc private func toggleBook() {
        bookOpen = !bookOpen
        if bookOpen { searchOpen = false; agentsOpen = false; worksOpen = false; spendOpen = false }
        lastPaint = ""
        scan()
    }

    @objc private func toggleAsks() {
        asksOpen = !asksOpen
        if asksOpen { searchOpen = false; agentsOpen = false; bookOpen = false
                      worksOpen = false; spendOpen = false }
        lastPaint = ""
        scan()
    }

    @objc private func toggleWorks() {
        worksOpen = !worksOpen
        if worksOpen { searchOpen = false; agentsOpen = false; bookOpen = false
                       asksOpen = false; spendOpen = false }
        lastPaint = ""
        scan()
    }

    /// ‏**תשובה קצרה ישר מהמדף**, בלי להיכנס לשיחה.
    ///
    /// ⇒ נמדד על 21 יום: מתוך 5,138 הודעות שהמשתמש הקליד, ‏376 קצרות מעשרים
    ///   תווים — וכמעט כולן שלוש משפחות: ״תמשיך״, ״נסה שוב״ ו״בוצע״.
    ///   כל אחת מהן הייתה פתיחת שיחה, הקלדה, וחזרה למדף.
    private func quickSend(sid: String, text: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let tty = Terminals.open().first(where: { $0.sessionID == sid })?.tty else {
                DispatchQueue.main.async { self?.note(Lang.t("המסוף של השיחה הזאת כבר סגור", "The terminal for this conversation is already closed")) }
                return
            }
            let ok = Terminals.send(text, tty: tty)
            DispatchQueue.main.async {
                guard let self else { return }
                if !ok { self.reportSendFailure(); return }
                // ההודעה מוצגת מיד רק כשהשיחה פתוחה; מהמדף היא תופיע ביומן
                if self.openSID == sid { self.pending.append((text: text, at: Date())) }
                self.lastPaint = ""
                self.scan()
            }
        }
    }

    /// ‏**להעיר את כל מי שממתין לך, במקש אחד.**
    ///
    /// ⛔ ‏**רק "ממתין לך".** מסוף שעובד אינו זקוק לדחיפה, ומסוף ש**שואל**
    ///    פתח בורר — ״תמשיך״ שם נחת כטקסט־חופשי במקום תשובה, כלומר תשובה
    ///    אחרת לגמרי. שקט לגמרי גם אינו נכלל: שיחה שנגמרה לפני שעתיים אינה
    ///    ממתינה לכלום, והעדתה היא הודעה מיותרת בשיחה שאיש לא פתח.
    @objc private func wakeAll() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let waiting = Panel.units().filter { ($0["state"] as? String ?? "") == "wait" }
            let pairs = waiting.compactMap { unit -> (sid: String, tty: String)? in
                guard let sid = unit["sid"] as? String, !sid.isEmpty,
                      let tty = unit["tty"] as? String, !tty.isEmpty else { return nil }
                return (sid, tty)
            }
            guard !pairs.isEmpty else {
                DispatchQueue.main.async { self?.note(Lang.t("אין מסוף שממתין לך", "No terminal is waiting for you")) }
                return
            }
            var sent = 0
            for pair in pairs where Terminals.send(Lang.t("תמשיך", "continue"), tty: pair.tty) { sent += 1 }
            DispatchQueue.main.async {
                guard let self else { return }
                if sent < pairs.count {
                    self.note(Lang.t("נשלח ל-\(sent) מתוך \(pairs.count)", "Sent to \(sent) of \(pairs.count)"))
                }
                self.lastPaint = ""
                self.scan()
            }
        }
    }

    /// מסוף חדש. התיקייה היא זו של השיחה הפתוחה, ואם אין — הבית.
    ///
    /// ⚠ ‏**מסך־האישור של מצב־עקיפת־ההרשאות הוא בורר, ופיץ׳ אינו עונה
    ///   לבוררים.** לכן חלון־המסוף מוקפז לחזית מיד, והתשובה נמסרת שם.
    @objc private func newTerminal() {
        var folder = ""
        if !openSID.isEmpty, let cwd = Sessions.state(id: openSID)?.cwd, !cwd.isEmpty {
            folder = cwd
        }
        let where_ = folder
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = Terminals.spawn(cwd: where_, bypass: true)
            DispatchQueue.main.async {
                guard let self else { return }
                if error.isEmpty {
                    // המסוף החדש נרשם רק אחרי שקלוד עלה; סריקה מיד אחר־כך
                    // הייתה מציגה מדף בלי השורה החדשה
                    self.lastPaint = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.scan() }
                    return
                }
                let alert = NSAlert()
                alert.messageText = Lang.t("לא נפתח מסוף חדש", "No new terminal opened")
                alert.informativeText = error
                alert.runModal()
            }
        }
    }

    @objc private func toggleSpend() {
        spendOpen = !spendOpen
        if spendOpen {
            searchOpen = false; agentsOpen = false
            bookOpen = false; asksOpen = false; worksOpen = false
            // המסך נפתח על נתונים טריים, לא על מה שנשמר מהפעם הקודמת
            DispatchQueue.global(qos: .userInitiated).async { Spend.refresh(force: true) }
        }
        lastPaint = ""
        scan()
    }

    @objc private func flipLanguage() {
        Lang.set(Lang.isHebrew ? "en" : "he")
        let alert = NSAlert()
        alert.messageText = Lang.t("השפה הוחלפה", "Language changed")
        alert.informativeText = Lang.t("צריך לפתוח את פיץ׳ מחדש כדי לראות אותה.",
                                       "Reopen Peach to see it.")
        alert.addButton(withTitle: Lang.t("סגירה", "Close"))
        alert.runModal()
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = Lang.t("פיץ׳", "Peach")
        alert.informativeText = Lang.t("מסך־המצב של המסופים הפתוחים.\nהכול נקרא מהדיסק — אין שרת ואין רשת.", "A status screen for every open terminal.\nEverything is read from disk — no server, no network.")
        alert.runModal()
    }
}
