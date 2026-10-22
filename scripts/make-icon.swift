// Renders AgentDeck's stacked-card mark on the macOS icon grid.
// Usage: swift scripts/make-icon.swift <out.png> (1024×1024, transparent margins)
import AppKit

private enum IconRenderError: Error {
    case unavailableColorSpace, unavailableContext, unavailableGradient, unavailableImage
}

private func color(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((value >> 16) & 0xff) / 255,
        green: CGFloat((value >> 8) & 0xff) / 255,
        blue: CGFloat(value & 0xff) / 255, alpha: alpha)
}

private func withGraphicsState(_ drawing: () throws -> Void) rethrows {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    try drawing()
}

private func gradient(_ colors: [NSColor], in path: NSBezierPath, angle: CGFloat) throws {
    guard let gradient = NSGradient(colors: colors) else { throw IconRenderError.unavailableGradient }
    gradient.draw(in: path, angle: angle)
}

private func shadowedFill(
    _ path: NSBezierPath, fill: NSColor, opacity: CGFloat, blur: CGFloat, offset: CGFloat
) {
    withGraphicsState {
        let shadow = NSShadow()
        shadow.shadowColor = color(0x102D38, alpha: opacity)
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: offset)
        shadow.set()
        fill.setFill()
        path.fill()
    }
}

private func drawCard(center: NSPoint, angle: CGFloat, colors: [NSColor], foreground: Bool = false) throws {
    try withGraphicsState {
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: angle)
        transform.concat()

        let rect = NSRect(x: -272, y: -188, width: 544, height: 376)
        let card = NSBezierPath(roundedRect: rect, xRadius: 58, yRadius: 58)
        shadowedFill(card, fill: colors[0], opacity: foreground ? 0.28 : 0.12, blur: 30, offset: -14)
        try gradient(colors, in: card, angle: -75)

        // Fine inset rim catches light without adding a miniature window toolbar.
        let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 56, yRadius: 56)
        color(0xFFFFFF, alpha: foreground ? 0.16 : 0.55).setStroke()
        rim.lineWidth = 2
        rim.stroke()

        if foreground {
            let prompt = NSBezierPath()
            prompt.move(to: NSPoint(x: -132, y: 62))
            prompt.line(to: NSPoint(x: -60, y: 0))
            prompt.line(to: NSPoint(x: -132, y: -62))
            prompt.lineWidth = 38
            prompt.lineCapStyle = .round
            prompt.lineJoinStyle = .round
            color(0xF4FFFC).setStroke()
            prompt.stroke()

            let cursor = NSBezierPath(
                roundedRect: NSRect(x: 12, y: -81, width: 118, height: 38), xRadius: 19, yRadius: 19)
            color(0x78EAC7).setFill()
            cursor.fill()
        }
    }
}

private func renderIcon(to destination: URL) throws {
    let size = 1024
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw IconRenderError.unavailableColorSpace
    }
    guard
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw IconRenderError.unavailableContext }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    defer { NSGraphicsContext.current = previousContext }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let background = NSBezierPath(
        roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
    shadowedFill(background, fill: color(0xE7EFEF), opacity: 0.19, blur: 22, offset: -10)
    try gradient([color(0xD8E7E9), color(0xFAFCF9)], in: background, angle: 90)

    try withGraphicsState {
        background.addClip()
        guard let glow = NSGradient(colors: [color(0xFFFFFF, alpha: 0.9), color(0xFFFFFF, alpha: 0)]) else {
            throw IconRenderError.unavailableGradient
        }
        glow.draw(
            fromCenter: NSPoint(x: 310, y: 820), radius: 0,
            toCenter: NSPoint(x: 310, y: 820), radius: 650, options: [])
    }
    let edge = NSBezierPath(
        roundedRect: NSRect(x: 102, y: 102, width: 820, height: 820), xRadius: 182, yRadius: 182)
    color(0xFFFFFF, alpha: 0.8).setStroke()
    edge.lineWidth = 2
    edge.stroke()

    // Three distinct planes communicate the deck; the generous glyph survives downsampling.
    try drawCard(center: NSPoint(x: 530, y: 610), angle: 11, colors: [color(0xB4F4DF), color(0xD5FCEC)])
    try drawCard(center: NSPoint(x: 514, y: 542), angle: 2, colors: [color(0x37B8A4), color(0x70DFBE)])
    try drawCard(
        center: NSPoint(x: 500, y: 466), angle: -9,
        colors: [color(0x102832), color(0x244653)], foreground: true)

    guard let image = context.makeImage(),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw IconRenderError.unavailableImage }
    try png.write(to: destination, options: .atomic)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try renderIcon(to: URL(fileURLWithPath: output))
print("wrote \(output)")
