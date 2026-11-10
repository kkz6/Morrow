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
        Button(configuration).buttonStyle(.borderless)
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

/// Both Button and Menu use the same platform-supplied styles. There is no
/// custom glass approximation on older systems.
private struct NativeActionStyle: ViewModifier {
    var height: CGFloat = 32
    var iconOnly = false

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
                .buttonBorderShape(iconOnly ? .circle : .capsule)
                .controlSize(height <= 24 ? .mini : height < 32 ? .small : .regular)
        } else {
            content.buttonStyle(.bordered)
                .controlSize(height <= 24 ? .mini : height < 32 ? .small : .regular)
        }
    }
}

extension View {
    func settingsButton(height: CGFloat = 32, expands: Bool = false) -> some View {
        buttonStyle(SettingsButtonStyle(height: height, expands: expands))
    }
    func settingsMenuControl(height: CGFloat = 28) -> some View {
        menuStyle(.button).menuIndicator(.hidden)
            .modifier(NativeActionStyle(height: height, iconOnly: true))
    }
    func settingsPickerControl() -> some View {
        menuStyle(.button).menuIndicator(.visible)
            .modifier(NativeActionStyle())
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
            .buttonStyle(SettingsButtonStyle(height: MenuLayout.actionSize, iconOnly: true))
    }
}

struct MenuActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(SettingsButtonStyle(height: 28))
    }
}
