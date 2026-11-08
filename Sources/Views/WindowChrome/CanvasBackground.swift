import SwiftUI

struct CanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 16
            let opacity = contrast == .increased ? 0.4 : 0.14
            let color: Color = colorScheme == .dark ? .white : .black
            var dots = Path()
            for x in stride(from: step / 2, to: size.width, by: step) {
                for y in stride(from: step / 2, to: size.height, by: step) {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                }
            }
            context.fill(dots, with: .color(color.opacity(opacity)))
        }
        .background(
            colorScheme == .dark
                ? Color(red: 31 / 255, green: 31 / 255, blue: 33 / 255)
                : Color(nsColor: .underPageBackgroundColor)
        )
        .accessibilityHidden(true)
    }
}
