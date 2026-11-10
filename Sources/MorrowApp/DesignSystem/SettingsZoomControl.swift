import SwiftUI

struct SettingsZoomControl: View {
    @Binding var zoom: Double
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 0) {
            Button { zoom = max(0.5, (zoom * 10 - 1).rounded() / 10) } label: {
                Image(systemName: "minus").frame(width: 25, height: ControlLayout.height)
            }.disabled(zoom <= 0.5).help("Zoom out (⌘−)").accessibilityLabel("Zoom out")
                .keyboardShortcut("-", modifiers: .command)
            Button { zoom = 1 } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .monospacedDigit().frame(width: 42, height: ControlLayout.height)
            }.help("Reset to actual size (⌘0)").accessibilityLabel("Reset zoom to 100 percent")
                .accessibilityValue("\(Int((zoom * 100).rounded())) percent").keyboardShortcut("0", modifiers: .command)
            Button { zoom = min(2, (zoom * 10 + 1).rounded() / 10) } label: {
                Image(systemName: "plus").frame(width: 25, height: ControlLayout.height)
            }.disabled(zoom >= 2).help("Zoom in (⌘+)").accessibilityLabel("Zoom in")
                .keyboardShortcut("=", modifiers: .command)
        }
        .font(.system(size: 11)).buttonStyle(.plain)
        .background(DS.Surface.control(colorScheme), in: RoundedRectangle(cornerRadius: ControlLayout.radius))
        .overlay(RoundedRectangle(cornerRadius: ControlLayout.radius).strokeBorder(DS.Surface.border(colorScheme), lineWidth: DS.Stroke.border))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Email zoom")
    }
}
