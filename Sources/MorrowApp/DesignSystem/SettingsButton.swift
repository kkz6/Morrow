import SwiftUI

/// Neutral bordered action controls matching the supplied macOS reference.
/// Settings actions can expand across a card; compact icon controls share the
/// same border, surface, pressed state, and shadow.
struct SettingsButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    var expands = false
    var iconOnly = false
    var alignment: Alignment = .center
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false
    @State private var boundsInCard = CGRect.zero
    @Environment(\.settingsCardContext) private var card
    private var corners: ActionCorners { ActionCorners.resolve(button: boundsInCard, card: card?.size) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height < 32 ? 12 : 13, weight: .medium))
            .foregroundStyle(foreground(role: configuration.role))
            .padding(.horizontal, iconOnly ? 0 : 12)
            .frame(minWidth: iconOnly ? height : 64,
                   maxWidth: expands ? .infinity : nil,
                   minHeight: height, maxHeight: height, alignment: alignment)
            .background(surface(pressed: configuration.isPressed), in: corners.shape)
            .overlay(corners.shape.strokeBorder(Color.primary.opacity(enabled ? 0.13 : 0.07), lineWidth: 0.75))
            .contentShape(corners.shape)
            .background {
                if let card {
                    GeometryReader { geometry in
                        Color.clear.onAppear { boundsInCard = geometry.frame(in: .named(card.id)) }
                            .onChange(of: geometry.frame(in: .named(card.id))) { _, frame in boundsInCard = frame }
                    }
                }
            }
            .onHover { hovering = $0 }
    }
    private func foreground(role: ButtonRole?) -> Color {
        if !enabled { return .secondary.opacity(0.6) }
        return role == .destructive ? .red : .primary
    }
    private func surface(pressed: Bool) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(!enabled ? 0.025 : pressed ? 0.12 : hovering ? 0.085 : 0.055)
        }
        if pressed && enabled { return Color.black.opacity(0.035) }
        return Color.white.opacity(!enabled ? 0.35 : hovering ? 0.95 : 0.75)
    }
}

extension View {
    func settingsButton(height: CGFloat = 32, expands: Bool = false) -> some View {
        buttonStyle(SettingsButtonStyle(height: height, expands: expands))
    }
    func settingsMenuControl(height: CGFloat = 28) -> some View {
        menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: height, height: height)
            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.75))
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

/// Menu controls are quieter than card actions: no raised icon backplates,
/// compact typography, and a translucent action surface that fits the popover.
struct MenuIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? (hovering ? Color.primary : .secondary) : .secondary.opacity(0.4))
            .frame(width: 26, height: 26)
            .background(Color.primary.opacity(enabled && configuration.isPressed ? 0.09 : enabled && hovering ? 0.045 : 0),
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct MenuActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? Color.primary : .secondary)
            .padding(.horizontal, 16).frame(minWidth: 146, minHeight: 30, maxHeight: 30)
            .background(Color.primary.opacity(configuration.isPressed ? 0.08 : hovering ? 0.05 : 0.025),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}
