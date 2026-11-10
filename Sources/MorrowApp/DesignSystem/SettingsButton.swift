import SwiftUI

private struct ToolbarActionsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var morrowToolbarActions: Bool {
        get { self[ToolbarActionsKey.self] }
        set { self[ToolbarActionsKey.self] = newValue }
    }
}

/// Glass is reserved for navigation and toolbar controls, above the content.
/// Controls within cards retain the platform's quiet bordered appearance.
struct SettingsToolbar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) { content }
            .environment(\.morrowToolbarActions, true)
    }
}

struct ToolbarIconButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14, weight: .medium)) }
            .buttonStyle(SettingsButtonStyle(height: 28, iconOnly: true))
            .help(title).accessibilityLabel(title)
    }
}

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
    var height: CGFloat = 28
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
    @Environment(\.morrowToolbarActions) private var toolbar
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var height: CGFloat = 28
    var iconOnly = false

    @ViewBuilder func body(content: Content) -> some View {
        if toolbar, #available(macOS 26, *), !reduceTransparency {
            content.buttonStyle(.glass(.regular)).tint(nil)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
        } else if toolbar {
            content.buttonStyle(.bordered).tint(nil).controlSize(.regular)
        } else if iconOnly {
            content.buttonStyle(.plain).tint(nil)
                .frame(width: height, height: height)
        } else {
            content.buttonStyle(.bordered).tint(nil)
                .controlSize(height < 32 ? .small : .regular)
        }
    }
}

extension View {
    func settingsButton(height: CGFloat = 28, expands: Bool = false) -> some View {
        buttonStyle(SettingsButtonStyle(height: height, expands: expands))
    }
    func settingsMenuControl(height: CGFloat = 28, iconOnly: Bool = true) -> some View {
        modifier(SettingsMenuControlStyle(height: height, iconOnly: iconOnly))
    }
}

private struct SettingsMenuControlStyle: ViewModifier {
    @Environment(\.morrowToolbarActions) private var toolbar
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var height: CGFloat
    var iconOnly: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if toolbar, #available(macOS 26, *), !reduceTransparency {
            content.menuStyle(.borderlessButton).menuIndicator(.visible)
                .tint(.primary).controlSize(.regular).fixedSize()
                .padding(.horizontal, 10).frame(height: height)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.menuStyle(.borderlessButton).menuIndicator(iconOnly ? .hidden : .visible)
                .fixedSize(horizontal: !iconOnly, vertical: true)
                .frame(width: iconOnly ? height : nil, height: height).tint(.primary)
        }
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
            .modifier(NativeActionStyle(height: MenuLayout.actionSize, iconOnly: true))
            .frame(width: MenuLayout.actionSize, height: MenuLayout.actionSize)
    }
}

struct MenuActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(SettingsButtonStyle(height: 28))
    }
}
