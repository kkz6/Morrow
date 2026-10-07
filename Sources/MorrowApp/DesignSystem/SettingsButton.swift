import SwiftUI

/// Neutral bordered action controls matching the supplied macOS reference.
/// Settings actions can expand across a card; compact icon controls share the
/// same border, surface, pressed state, and shadow.
struct SettingsButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    var expands = false
    var iconOnly = false
    var alignment: Alignment = .center
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height < 32 ? 12 : 14, weight: .semibold))
            .foregroundStyle(foreground(role: configuration.role))
            .padding(.horizontal, iconOnly ? 0 : 12)
            .frame(minWidth: iconOnly ? height : 64,
                   maxWidth: expands ? .infinity : nil,
                   minHeight: height, maxHeight: height, alignment: alignment)
            .background(surface(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.dividerColor, lineWidth: 1))
            .shadow(color: .black.opacity(enabled ? 0.06 : 0.02), radius: 1, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
    private func foreground(role: ButtonRole?) -> Color {
        if !enabled { return .secondary.opacity(0.6) }
        return role == .destructive ? .red : .primary
    }
    private func surface(pressed: Bool) -> Color {
        if enabled && pressed { return Color(nsColor: .controlBackgroundColor).opacity(0.65) }
        if enabled && hovering { return Color(nsColor: .textBackgroundColor) }
        return Color(nsColor: .controlBackgroundColor)
    }
}

extension View {
    func settingsButton(height: CGFloat = 34, expands: Bool = false) -> some View {
        buttonStyle(SettingsButtonStyle(height: height, expands: expands))
    }
    func settingsMenuControl(height: CGFloat = 28) -> some View {
        menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: height, height: height)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.dividerColor, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            .tint(.primary)
    }
}

/// An inset, full-width button inside a settings card. Optional secondary text
/// occupies the trailing edge, like the version in the reference update row.
struct SettingsActionRow: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    var detail: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13)) }
                Text(title)
                Spacer(minLength: 8)
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(SettingsButtonStyle(expands: true, alignment: .leading))
        .padding(6)
    }
}
