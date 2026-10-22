import AppKit
import SwiftUI

struct AgentDeckIcon: View {
    private static let image = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "rectangle.3.group").resizable().scaledToFit()
        }
    }
}
