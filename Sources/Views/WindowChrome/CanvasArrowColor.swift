import AppKit
import SwiftUI

enum CanvasArrowColor {
    static func color(hex: String) -> Color {
        let value = hex.count == 6 ? UInt32(hex, radix: 16) : nil
        let rgb = value ?? 0xB96B35
        return Color(
            .sRGB, red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }

    static func hex(color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return AppSettings().arrowColorHex }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
            Int((min(1, max(0, $0)) * 255).rounded())
        }
        return String(format: "%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}
