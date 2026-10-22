// Renders the AgentDeck app icon: a cascade of terminal mini-windows on a gradient squircle.
// Usage: swift scripts/make-icon.swift <out.png>   (1024×1024)
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = gc

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
func hex(_ h: UInt32, _ a: Double = 1) -> NSColor {
    rgb(Double((h >> 16) & 0xff) / 255, Double((h >> 8) & 0xff) / 255, Double(h & 0xff) / 255, a)
}

// Background squircle (macOS icon grid: 824 pt centred on a 1024 canvas)
let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 186, yRadius: 186)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = hex(0x000000, 0.35); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
hex(0x14172B).setFill(); bg.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colorsAndLocations: (hex(0x5B5FEF), 0.0), (hex(0x2E2FB0), 0.55), (hex(0x121433), 1.0))!.draw(in: bg, angle: -62)
// soft glow top-left
NSGraphicsContext.saveGraphicsState()
bg.addClip()
NSGradient(colors: [hex(0x8DE0FF, 0.35), hex(0x8DE0FF, 0.0)])!.draw(fromCenter: NSPoint(x: 300, y: 780), radius: 0,
                                                                     toCenter: NSPoint(x: 300, y: 780), radius: 520, options: [])
NSGraphicsContext.restoreGraphicsState()

// Terminal cards cascading from back (upper-left) to front (lower-right)
struct Card { var origin: NSPoint; var alpha: Double; var front: Bool }
let cardSize = NSSize(width: 520, height: 372)
let cards = [Card(origin: NSPoint(x: 176, y: 352), alpha: 0.55, front: false),
             Card(origin: NSPoint(x: 220, y: 302), alpha: 0.8, front: false),
             Card(origin: NSPoint(x: 264, y: 252), alpha: 1.0, front: true)]
let titleH: CGFloat = 52

for c in cards {
    let r = NSRect(origin: c.origin, size: cardSize)
    let path = NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = hex(0x000000, 0.45); sh.shadowBlurRadius = 26; sh.shadowOffset = NSSize(width: 0, height: -10)
    sh.set()
    hex(0x0C0E17, c.alpha).setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    // title bar
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    hex(0x262A3D, c.alpha).setFill()
    NSRect(x: r.minX, y: r.maxY - titleH, width: r.width, height: titleH).fill()
    hex(0xFFFFFF, 0.08 * c.alpha).setFill()
    NSRect(x: r.minX, y: r.maxY - titleH - 2, width: r.width, height: 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    // traffic lights
    for (i, col) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        hex(UInt32(col), c.alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + 30 + CGFloat(i) * 30, y: r.maxY - titleH / 2 - 9, width: 18, height: 18)).fill()
    }
    // border
    hex(0xFFFFFF, 0.10 * c.alpha).setStroke(); path.lineWidth = 2; path.stroke()

    if c.front {
        // prompt line
        let font = NSFont.monospacedSystemFont(ofSize: 128, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: hex(0x5AF78E)]
        NSAttributedString(string: "❯", attributes: attrs).draw(at: NSPoint(x: r.minX + 46, y: r.minY + 118))
        // blinking cursor block
        hex(0xE6E8F0).setFill()
        NSRect(x: r.minX + 150, y: r.minY + 126, width: 54, height: 118).fill()
        // faint second line (output)
        hex(0x8E93A8, 0.6).setFill()
        NSRect(x: r.minX + 46, y: r.minY + 60, width: 220, height: 20).fill()
        hex(0x8E93A8, 0.35).setFill()
        NSRect(x: r.minX + 290, y: r.minY + 60, width: 120, height: 20).fill()
    } else {
        // dim content lines
        hex(0x8E93A8, 0.35 * c.alpha).setFill()
        NSRect(x: r.minX + 46, y: r.maxY - titleH - 70, width: 180, height: 18).fill()
    }
}

// Status beacons (sessions talking to the deck): three dots bottom-right
for (i, col) in [0x28C840, 0x3A8DFF, 0xFFA629].enumerated() {
    let p = NSPoint(x: 700 + CGFloat(i) * 52, y: 196)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = hex(UInt32(col), 0.9); sh.shadowBlurRadius = 18; sh.set()
    hex(UInt32(col)).setFill()
    NSBezierPath(ovalIn: NSRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)).fill()
    NSGraphicsContext.restoreGraphicsState()
}

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
