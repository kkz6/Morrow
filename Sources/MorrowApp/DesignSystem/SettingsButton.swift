import SwiftUI

/// Full-row navigation uses the card itself as its surface.
struct SettingsLinkRow: View {
    let title: LocalizedStringKey
    let symbol: String
    var color: Color = .accentColor
    let url: URL

    var body: some View {
        Link(destination: url) {
            SettingRow(icon: symbol, iconColor: color, title: title) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(SettingsNavigationRowStyle())
    }
}

/// Navigation rows keep the system's borderless behavior, without a drawn bezel.
struct SettingsNavigationRowStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(.plain)
    }
}

/// Layout only: macOS owns each control's material, corners, focus, and feedback.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    var height: CGFloat = 32
    var expands = false
    var iconOnly = false
    var alignment: Alignment = .center

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .frame(minWidth: iconOnly ? max(12, height - 16) : nil,
                       maxWidth: expands ? .infinity : nil,
                       minHeight: max(12, height - 12), alignment: alignment)
        }
        .modifier(NativeActionStyle(height: height, iconOnly: iconOnly))
    }
}

/// Standard platform controls, matching the shared settings framework.
private struct NativeActionStyle: ViewModifier {
    var height: CGFloat = 32
    var iconOnly = false

    @ViewBuilder func body(content: Content) -> some View {
        if iconOnly {
            content.buttonStyle(.plain).tint(nil)
                .frame(width: height, height: height)
        } else {
            content.buttonStyle(.bordered).tint(nil)
                .controlSize(height < 32 ? .small : .regular)
        }
    }
}

extension View {
    func settingsButton(height: CGFloat = 32, expands: Bool = false) -> some View {
        buttonStyle(SettingsButtonStyle(height: height, expands: expands))
    }
    func settingsMenuControl(height: CGFloat = 28, iconOnly: Bool = true) -> some View {
        menuStyle(.borderlessButton).menuIndicator(iconOnly ? .hidden : .visible)
            .fixedSize(horizontal: !iconOnly, vertical: true)
            .frame(width: iconOnly ? height : nil, height: height).tint(.primary)
    }
}

/// A settings action is a row of the card, without a second nested bezel.
struct SettingsActionRow: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    var detail: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            SettingRow(icon: symbol, title: title) {
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Inset peer actions share one gutter and the native action style.
struct SettingsActionGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: SettingsLayout.actionSpacing) { content }
            .buttonStyle(SettingsButtonStyle(expands: true))
            .padding(SettingsLayout.actionInset)
    }
}

/// Compact native actions used in the menu bar and contextual feedback.
struct MenuIconButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.plain).tint(nil)
            .controlSize(.small)
            .frame(width: MenuLayout.actionSize, height: MenuLayout.actionSize)
    }
}

struct MenuActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(SettingsButtonStyle(height: 28))
    }
}
