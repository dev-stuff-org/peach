// אייקון פיץ׳: מקלט־טלוויזיה ישן בקו אחד, ובתוכו אפרסק. אותו סמליל שבאפליקציה.
import AppKit
import Foundation

private func path(_ points: [(CGFloat, CGFloat)], _ s: CGFloat, close: Bool = true) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: points[0].0 * s, y: points[0].1 * s))
    var i = 1
    while i + 2 < points.count + 1 && i + 2 <= points.count {
        p.curve(to: NSPoint(x: points[i + 2].0 * s, y: points[i + 2].1 * s),
                controlPoint1: NSPoint(x: points[i].0 * s, y: points[i].1 * s),
                controlPoint2: NSPoint(x: points[i + 1].0 * s, y: points[i + 1].1 * s))
        i += 3
    }
    if close { p.close() }
    return p
}

/// הצורות מוגדרות ביחידות 0..1, ומוכפלות בגודל המבוקש — כך אותו קובץ
/// מייצר את כל המידות בלי לצייר מחדש.
func drawIcon(size s: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // רקע
    let inset = s * 0.06
    let card = NSBezierPath(roundedRect: NSRect(x: inset, y: inset,
                                                width: s - inset * 2, height: s - inset * 2),
                            xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor(calibratedRed: 0.055, green: 0.063, blue: 0.070, alpha: 1).setFill()
    card.fill()

    let shell = NSColor(calibratedRed: 0.33, green: 0.37, blue: 0.39, alpha: 1)
    let glass = NSColor(calibratedRed: 0.027, green: 0.031, blue: 0.039, alpha: 1)
    let peach = NSColor(calibratedRed: 0.95, green: 0.64, blue: 0.38, alpha: 1)
    let cleft = NSColor(calibratedRed: 0.72, green: 0.44, blue: 0.23, alpha: 1)
    let leaf  = NSColor(calibratedRed: 0.39, green: 0.82, blue: 0.55, alpha: 1)

    // המקלט — מלבן מעוגל עם התכווצות קלה, וקו־שיער אחד
    let m = s * 0.17
    let box = NSRect(x: m, y: m * 1.35, width: s - m * 2, height: s - m * 2.3)
    let set = NSBezierPath(roundedRect: box, xRadius: s * 0.09, yRadius: s * 0.09)
    glass.setFill(); set.fill()
    shell.setStroke(); set.lineWidth = max(1, s * 0.028); set.stroke()

    // רגליים
    shell.setFill()
    let footW = s * 0.10, footH = s * 0.028
    NSBezierPath(rect: NSRect(x: box.minX + box.width * 0.18, y: box.minY - footH,
                              width: footW, height: footH)).fill()
    NSBezierPath(rect: NSRect(x: box.maxX - box.width * 0.18 - footW, y: box.minY - footH,
                              width: footW, height: footH)).fill()

    // קו־הסריקה
    peach.withAlphaComponent(0.32).setStroke()
    let scan = NSBezierPath()
    scan.move(to: NSPoint(x: box.minX + box.width * 0.16, y: box.maxY - box.height * 0.11))
    scan.line(to: NSPoint(x: box.maxX - box.width * 0.16, y: box.maxY - box.height * 0.11))
    scan.lineWidth = max(1, s * 0.012)
    scan.stroke()

    // האפרסק
    let r = box.width * 0.25
    let c = NSPoint(x: box.midX, y: box.midY - box.height * 0.04)
    peach.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()

    cleft.setStroke()
    let groove = NSBezierPath()
    groove.move(to: NSPoint(x: c.x, y: c.y + r * 0.94))
    groove.curve(to: NSPoint(x: c.x, y: c.y - r * 0.94),
                 controlPoint1: NSPoint(x: c.x - r * 0.55, y: c.y + r * 0.4),
                 controlPoint2: NSPoint(x: c.x - r * 0.55, y: c.y - r * 0.4))
    groove.lineWidth = max(1, s * 0.014)
    groove.stroke()

    leaf.setFill()
    let sprout = NSBezierPath()
    sprout.move(to: NSPoint(x: c.x, y: c.y + r * 0.92))
    sprout.curve(to: NSPoint(x: c.x + r * 0.86, y: c.y + r * 1.28),
                 controlPoint1: NSPoint(x: c.x + r * 0.28, y: c.y + r * 1.42),
                 controlPoint2: NSPoint(x: c.x + r * 0.70, y: c.y + r * 1.46))
    sprout.curve(to: NSPoint(x: c.x, y: c.y + r * 0.92),
                 controlPoint1: NSPoint(x: c.x + r * 0.72, y: c.y + r * 1.02),
                 controlPoint2: NSPoint(x: c.x + r * 0.34, y: c.y + r * 0.84))
    sprout.fill()

    image.unlockFocus()
    return image
}

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x")
]
let dir = "/tmp/peach.iconset"
try? FileManager.default.removeItem(atPath: dir)
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (px, name) in sizes {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
print("✓ נוצר \(dir)")
