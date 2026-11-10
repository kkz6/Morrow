import SwiftUI

struct SettingsZoomControl: View {
    @Binding var zoom: Double
    var body: some View {
        ControlGroup {
            Button { zoom = max(0.5, (zoom * 10 - 1).rounded() / 10) } label: {
                Image(systemName: "minus")
            }.disabled(zoom <= 0.5).help("Zoom out (⌘−)").accessibilityLabel("Zoom out")
                .keyboardShortcut("-", modifiers: .command)
            Button { zoom = 1 } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .monospacedDigit().frame(width: 38)
            }.help("Reset to actual size (⌘0)").accessibilityLabel("Reset zoom to 100 percent")
                .accessibilityValue("\(Int((zoom * 100).rounded())) percent").keyboardShortcut("0", modifiers: .command)
            Button { zoom = min(2, (zoom * 10 + 1).rounded() / 10) } label: {
                Image(systemName: "plus")
            }.disabled(zoom >= 2).help("Zoom in (⌘+)").accessibilityLabel("Zoom in")
                .keyboardShortcut("=", modifiers: .command)
        }
        .controlGroupStyle(.automatic).controlSize(.small)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Email zoom")
    }
}
