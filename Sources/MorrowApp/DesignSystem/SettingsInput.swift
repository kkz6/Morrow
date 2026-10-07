import SwiftUI

enum ControlLayout {
    static let height: CGFloat = 32
    static let radius: CGFloat = 8
    static let inset: CGFloat = 10
}

struct SettingsInput: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String? = nil
    var clearable = false
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 14) }
            TextField("", text: $text, prompt: Text(placeholder)).labelsHidden()
                .textFieldStyle(.plain).font(.system(size: 13)).multilineTextAlignment(.leading).focused($focused)
                .accessibilityLabel(placeholder)
            if clearable && !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Clear search")
            }
        }
        .padding(.horizontal, ControlLayout.inset).frame(height: ControlLayout.height)
        .background(Color(nsColor: .textBackgroundColor).opacity(enabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: ControlLayout.radius))
        .overlay(RoundedRectangle(cornerRadius: ControlLayout.radius).strokeBorder(focused ? Color.morrowAccent.opacity(0.7) : DS.dividerColor, lineWidth: 1))
    }
}

struct ControlIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12)).frame(width: ControlLayout.height, height: ControlLayout.height) }
            .buttonStyle(.plain)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: ControlLayout.radius))
            .overlay(RoundedRectangle(cornerRadius: ControlLayout.radius).strokeBorder(DS.dividerColor, lineWidth: 1))
            .help(help).accessibilityLabel(help)
    }
}
