// Render a page in real WebKit (the engine Peach uses), run a JS probe, and save
// a snapshot. Usage: swift shoot.swift page.html probe.js out.png [width] [height]
// The probe must define `window.__probe()` returning a JSON-serialisable value,
// possibly a Promise. Its result is printed to stdout.
import AppKit
import WebKit

let a = CommandLine.arguments
let page = URL(fileURLWithPath: a[1])
let probe = try! String(contentsOfFile: a[2], encoding: .utf8)
let out = URL(fileURLWithPath: a[3])
let w = a.count > 4 ? Double(a[4])! : 1100
let h = a.count > 5 ? Double(a[5])! : 1400

final class D: NSObject, WKNavigationDelegate {
    var web: WKWebView!
    func webView(_ v: WKWebView, didFinish n: WKNavigation!) {
        v.evaluateJavaScript(probe + "\n;0") { _, e in
            if let e = e { print("probe load error:", e); exit(1) }
            v.callAsyncJavaScript("return JSON.stringify(await window.__probe())", arguments: [:], in: nil, in: .page) { r in
                switch r {
                case .success(let s): print(s as? String ?? "null")
                case .failure(let e): print("probe error:", e)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let cfg = WKSnapshotConfiguration()
                    v.takeSnapshot(with: cfg) { img, _ in
                        if let img = img, let t = img.tiffRepresentation,
                           let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                            try? png.write(to: out)
                        }
                        exit(0)
                    }
                }
            }
        }
    }
}
let app = NSApplication.shared
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
let d = D()
let cfg = WKWebViewConfiguration()
// PEACH_USERSCRIPT=<file>: inject it the way AppDelegate does (document start,
// page loaded as a string with no base URL), to test the app's real path.
let userScript = ProcessInfo.processInfo.environment["PEACH_USERSCRIPT"]
if let us = userScript, let js = try? String(contentsOfFile: us, encoding: .utf8) {
    cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
}
let web = WKWebView(frame: win.contentView!.bounds, configuration: cfg)
web.navigationDelegate = d
win.contentView!.addSubview(web)
if userScript != nil {
    web.loadHTMLString(try! String(contentsOf: page, encoding: .utf8), baseURL: nil)
} else {
    web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("timeout"); exit(2) }
app.run()
