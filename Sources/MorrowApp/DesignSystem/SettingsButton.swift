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
    private var corners: ActionCorners { ActionCorners.resolve(button: boundsInCard, card: card?.size, grouped: expands) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height < 32 ? 12 : 13, weight: .medium))
            .foregroundStyle(foreground(role: configuration.role))
            .padding(.horizontal, iconOnly ? 0 : SettingsLayout.cardHorizontalInset)
            .frame(minWidth: iconOnly ? height : 64,
                   maxWidth: expands ? .infinity : nil,
                   minHeight: height, maxHeight: height, alignment: alignment)
            .background(surface(pressed: configuration.isPressed), in: corners.shape)
            .overlay(corners.shape.strokeBorder(DS.Surface.border(colorScheme, enabled: enabled), lineWidth: 0.75))
            .shadow(color: DS.Surface.shadow(colorScheme, enabled: enabled, pressed: configuration.isPressed), radius: 1, y: 0.5)
            .contentShape(corners.shape)
            .background {
                if let card {
                    Color.clear.onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .named(card.id))
                    } action: { boundsInCard = $0 }
                }
            }
            .onHover { hovering = $0 }
    }
    private func foreground(role: ButtonRole?) -> Color {
        if !enabled { return .secondary.opacity(0.6) }
        return role == .destructive ? .red : .primary
    }
    private func surface(pressed: Bool) -> Color {
        DS.Surface.control(colorScheme, state: !enabled ? .disabled : pressed ? .pressed : hovering ? .hovered : .normal)
    }
}

extension View {
    func settingsButton(height: CGFloat = 32, expands: Bool = false) -> some View {
        buttonStyle(SettingsButtonStyle(height: height, expands: expands))
    }
    func settingsMenuControl(height: CGFloat = 28) -> some View {
        menuStyle(.borderlessButton).menuIndicator(.hidden)
            .modifier(SettingsMenuControlSurface(height: height)).tint(.primary)
    }
}

private struct SettingsMenuControlSurface: ViewModifier {
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.frame(width: height, height: height)
            .background(DS.Surface.control(colorScheme, state: !enabled ? .disabled : hovering ? .hovered : .normal), in: RoundedRectangle(cornerRadius: ControlLayout.radius))
            .overlay(RoundedRectangle(cornerRadius: ControlLayout.radius).strokeBorder(DS.Surface.border(colorScheme, enabled: enabled), lineWidth: 0.75))
            .onHover { hovering = $0 }
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
        .padding(SettingsLayout.actionInset)
    }
}

/// Inset peer actions share one gutter. Button geometry determines which
/// individual corners touch the card, without first/last styling at call sites.
struct SettingsActionGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: SettingsLayout.actionSpacing) { content }
            .buttonStyle(SettingsButtonStyle(expands: true))
            .padding(SettingsLayout.actionInset)
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
            .frame(width: MenuLayout.actionSize, height: MenuLayout.actionSize)
            .background(Color.primary.opacity(enabled && configuration.isPressed ? 0.09 : enabled && hovering ? 0.045 : 0),
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct MenuActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? Color.primary : .secondary)
            .padding(.horizontal, 14).frame(minWidth: 132, minHeight: 28, maxHeight: 28)
            .background(DS.Surface.control(colorScheme, state: !enabled ? .disabled : configuration.isPressed ? .pressed : hovering ? .hovered : .normal),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Surface.border(colorScheme, enabled: enabled), lineWidth: 0.75))
            .shadow(color: DS.Surface.shadow(colorScheme, enabled: enabled, pressed: configuration.isPressed), radius: 1, y: 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}
