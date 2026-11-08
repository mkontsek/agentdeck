import AppKit

// A synthetic workflow illustration. This script never connects to AgentDeck or a provider.
let size = 1080
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let icon = NSImage(contentsOfFile: CommandLine.arguments[2])!
let ink = NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.18, alpha: 1)
let muted = NSColor(calibratedRed: 0.32, green: 0.40, blue: 0.42, alpha: 1)
let mint = NSColor(calibratedRed: 0.46, green: 0.89, blue: 0.76, alpha: 1)
let canvas = NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.93, alpha: 1)
let panel = NSColor(calibratedRed: 0.10, green: 0.17, blue: 0.20, alpha: 1)
let secondary = NSColor(calibratedRed: 0.66, green: 0.74, blue: 0.75, alpha: 1)
let blue = NSColor(calibratedRed: 0.21, green: 0.58, blue: 1.0, alpha: 1)
let arrow = NSColor(calibratedRed: 0.65, green: 0.34, blue: 0.16, alpha: 1)

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: y, width: w, height: h)
}

func box(_ r: NSRect, _ color: NSColor, radius: CGFloat = 16, stroke: NSColor? = nil, width: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    color.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = width
        path.stroke()
    }
}

func text(
    _ value: String, _ x: CGFloat, _ y: CGFloat, _ fontSize: CGFloat,
    _ color: NSColor = ink, weight: NSFont.Weight = .regular, mono: Bool = false, width: CGFloat = 960
) {
    let font =
        mono
        ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        : NSFont.systemFont(ofSize: fontSize, weight: weight)
    (value as NSString).draw(
        in: rect(x, y, width, 180),
        withAttributes: [.font: font, .foregroundColor: color])
}

func line(_ points: [NSPoint], color: NSColor, width: CGFloat = 2) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

func ease(_ t: Double) -> CGFloat {
    let value = min(1, max(0, t))
    return CGFloat(value * value * (3 - 2 * value))
}

func connect(from: NSPoint, to: NSPoint, elbowX: CGFloat) {
    let radius: CGFloat = 10
    let path = NSBezierPath()
    let direction: CGFloat = to.y >= from.y ? 1 : -1
    path.move(to: from)
    path.line(to: NSPoint(x: elbowX - radius, y: from.y))
    path.curve(
        to: NSPoint(x: elbowX, y: from.y + direction * radius),
        controlPoint1: NSPoint(x: elbowX, y: from.y), controlPoint2: NSPoint(x: elbowX, y: from.y))
    path.line(to: NSPoint(x: elbowX, y: to.y - direction * radius))
    path.curve(
        to: NSPoint(x: elbowX + radius, y: to.y),
        controlPoint1: NSPoint(x: elbowX, y: to.y), controlPoint2: NSPoint(x: elbowX, y: to.y))
    path.line(to: to)
    path.lineWidth = 4
    arrow.setStroke()
    path.stroke()
    line([NSPoint(x: to.x - 11, y: to.y - 7), to, NSPoint(x: to.x - 11, y: to.y + 7)], color: arrow, width: 4)
}

func window(_ r: NSRect, title: String, focused: Bool = false) {
    box(r.offsetBy(dx: 0, dy: 8), ink.withAlphaComponent(0.09), radius: 18)
    box(r, panel, radius: 18, stroke: focused ? blue : panel, width: focused ? 4 : 1)
    box(rect(r.minX + 1, r.minY + 1, r.width - 2, 55), NSColor.white.withAlphaComponent(0.04), radius: 16)
    box(rect(r.minX + 18, r.minY + 23, 10, 10), mint, radius: 5)
    text(title, r.minX + 40, r.minY + 13, 24, .white, weight: .semibold, width: r.width - 80)
    text("···", r.maxX - 40, r.minY + 8, 27, secondary, weight: .bold, width: 32)
    line([NSPoint(x: r.maxX - 22, y: r.maxY - 10), NSPoint(x: r.maxX - 10, y: r.maxY - 22)], color: secondary)
    line([NSPoint(x: r.maxX - 15, y: r.maxY - 10), NSPoint(x: r.maxX - 10, y: r.maxY - 15)], color: secondary)
}

func base(title: String, caption: String, beat: Int) {
    box(rect(0, 0, 1080, 1080), NSColor(calibratedWhite: 0.97, alpha: 1), radius: 0)
    icon.draw(in: rect(54, 38, 60, 60))
    text("AgentDeck", 124, 48, 31, weight: .bold)
    text("0.1.26", 880, 55, 22, muted, mono: true, width: 150)
    text(title, 54, 142, 59, weight: .bold)
    text(caption, 57, 224, 27, muted)
    box(rect(36, 296, 1008, 672), canvas, radius: 28)
    for y in stride(from: 316, to: 954, by: 24) {
        for x in stride(from: 56, to: 1024, by: 24) {
            box(rect(CGFloat(x), CGFloat(y), 2, 2), ink.withAlphaComponent(0.12), radius: 1)
        }
    }
    text("Illustrated workflow · synthetic content", 54, 1006, 20, muted)
    for index in 0..<4 {
        box(rect(CGFloat(844 + index * 45), 1017, 32, 5), index == beat ? ink : ink.withAlphaComponent(0.16), radius: 3)
    }
}

func overview(_ t: Double) {
    base(title: "Your agents. One canvas.", caption: "Real CLIs. Connected mini-windows.", beat: 0)
    let main = rect(80, 430, 420, 310)
    window(main, title: "Main agent", focused: true)
    text("› Build the next feature", 104, 511, 24, .white, mono: true, width: 375)
    text("Plan → delegate → review", 104, 564, 23, mint, mono: true, width: 375)
    text("You stay here.", 104, 664, 26, secondary)
    let a = ease((t - 0.6) / 1.0)
    let b = ease((t - 1.5) / 1.0)
    let first = rect(620 + (1 - a) * 60, 358, 380, 210)
    let second = rect(620 + (1 - b) * 60, 658, 380, 210)
    if a > 0 {
        NSGraphicsContext.current?.cgContext.setAlpha(a)
        connect(from: NSPoint(x: 502, y: 535), to: NSPoint(x: first.minX - 5, y: 455), elbowX: 554)
        window(first, title: "Worker · UI")
        text("Implementing layout", first.minX + 22, 442, 25, mint)
        text("Task #12", first.minX + 22, 500, 22, secondary, mono: true)
    }
    if b > 0 {
        NSGraphicsContext.current?.cgContext.setAlpha(b)
        connect(from: NSPoint(x: 502, y: 633), to: NSPoint(x: second.minX - 5, y: 760), elbowX: 554)
        window(second, title: "Worker · Tests")
        text("Checking behavior", second.minX + 22, 742, 25, mint)
        text("Task #13", second.minX + 22, 800, 22, secondary, mono: true)
    }
    NSGraphicsContext.current?.cgContext.setAlpha(1)
}

func focusedDraft(_ t: Double) {
    base(title: "Keep typing. Stay focused.", caption: "Worker results have their own inbox.", beat: 1)
    window(rect(80, 350, 920, 300), title: "Main agent · your draft", focused: true)
    let draft = "› Make room for the next idea"
    let count = min(draft.count, 13 + Int(t * 6))
    let visible = String(draft.prefix(count))
    text(visible, 111, 457, 36, .white, mono: true, width: 850)
    if Int(t * 2) % 2 == 0 {
        box(rect(111 + CGFloat(count) * 21.6, 462, 3, 39), mint, radius: 1)
    }
    text("Your text and caret stay here", 111, 567, 25, secondary)
    text("COORDINATION INBOX", 82, 700, 20, muted, weight: .bold)
    for index in 0..<2 {
        let alpha = ease((t - Double(index) * 1.6 - 0.7) / 0.5)
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        let y = CGFloat(746 + index * 86) + (1 - alpha) * 12
        box(rect(80, y, 920, 70), .white, radius: 14)
        box(rect(101, y + 22, 26, 26), mint, radius: 13)
        text(index == 0 ? "UI worker: layout ready" : "Test worker: checks passed", 146, y + 18, 27, ink)
        text("Queued", 864, y + 22, 21, muted, width: 110)
    }
    NSGraphicsContext.current?.cgContext.setAlpha(1)
}

func connectedBrowser(_ t: Double) {
    base(title: "Every task stays connected.", caption: "A browser beside the work. Room to move.", beat: 2)
    window(rect(80, 375, 390, 215), title: "Main agent", focused: true)
    text("› Review the result", 104, 463, 26, .white, mono: true, width: 350)
    text("Your conversation", 104, 522, 25, secondary)
    let shift = ease((t - 1.0) / 1.4) * 72
    let worker = rect(160 + shift, 658, 760, 248)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 472, y: 483))
    path.line(to: NSPoint(x: 974, y: 483))
    path.curve(
        to: NSPoint(x: 984, y: 493), controlPoint1: NSPoint(x: 984, y: 483), controlPoint2: NSPoint(x: 984, y: 483))
    path.line(to: NSPoint(x: 984, y: 622))
    path.curve(
        to: NSPoint(x: 974, y: 632), controlPoint1: NSPoint(x: 984, y: 632), controlPoint2: NSPoint(x: 984, y: 632))
    path.line(to: NSPoint(x: worker.midX + 10, y: 632))
    path.curve(
        to: NSPoint(x: worker.midX, y: 642), controlPoint1: NSPoint(x: worker.midX, y: 632),
        controlPoint2: NSPoint(x: worker.midX, y: 632))
    path.line(to: NSPoint(x: worker.midX, y: 652))
    arrow.setStroke()
    path.lineWidth = 4
    path.stroke()
    line(
        [NSPoint(x: worker.midX - 7, y: 643), NSPoint(x: worker.midX, y: 652), NSPoint(x: worker.midX + 7, y: 643)],
        color: arrow, width: 4)
    text("Parent → worker", 572, 407, 26, muted)
    window(worker, title: "Worker · preview")
    text("TERMINAL", worker.minX + 24, 733, 18, secondary, weight: .bold)
    text("✓ Layout ready", worker.minX + 24, 778, 25, mint, mono: true, width: 340)
    text("✓ Tests passed", worker.minX + 24, 820, 25, mint, mono: true, width: 340)
    box(rect(worker.minX + 382, 723, 360, 163), .white, radius: 10)
    text("BROWSER · PREVIEW", worker.minX + 401, 739, 18, muted, weight: .bold, width: 325)
    text("Hello, next idea.", worker.minX + 401, 786, 27, ink, weight: .bold, width: 325)
    box(rect(worker.minX + 401, 837, 180, 26), mint, radius: 8)
}

func closing() {
    box(rect(0, 0, 1080, 1080), NSColor(calibratedWhite: 0.97, alpha: 1), radius: 0)
    text("Less switching.", 80, 115, 75, weight: .bold)
    text("More building.", 80, 206, 75, weight: .bold)
    icon.draw(in: rect(392, 355, 296, 296))
    text("AgentDeck", 340, 687, 67, weight: .bold)
    text("Open source. Native macOS.", 262, 794, 36, muted)
    box(rect(323, 889, 434, 68), ink, radius: 34)
    text("Find the link below ↓", 369, 905, 30, .white, weight: .medium)
    text("Illustrated workflow · synthetic content", 54, 1006, 20, muted)
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for frame in 0..<660 {
    try autoreleasepool {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
        else { fatalError("Could not allocate frame") }
        let context = graphics.cgContext
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let t = Double(frame) / 30
        if t < 5.5 {
            overview(t)
        } else if t < 12 {
            focusedDraft(t - 5.5)
        } else if t < 18 {
            connectedBrowser(t - 12)
        } else {
            closing()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
        try png.write(to: output.appendingPathComponent(String(format: "%04d.png", frame)))
    }
}
