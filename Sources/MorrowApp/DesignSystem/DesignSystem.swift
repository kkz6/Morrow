import SwiftUI

// MARK: - Design Tokens

enum DS {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 17
        static let row: CGFloat = 13
        static let control: CGFloat = 13
        static let selection: CGFloat = 11
        static let tile: CGFloat = 8
        static let action: CGFloat = 5
        static let actionInterior: CGFloat = 3
        static let actionEdge: CGFloat = 6
    }

    enum Size {
        static let rowHeight: CGFloat = 46
        static let tile: CGFloat = 26
        static let popoverWidth: CGFloat = 320
    }

    /// Visible, theme-adaptive border used on every card and input.
    static let borderColor = Color.gray.opacity(0.30)
    /// Lighter hairline used to separate rows inside a card.
    static let dividerColor = Color.gray.opacity(0.28)
}

// MARK: - Icon Tile

/// SF Symbol on a rounded, tinted square — the colored icons in the sidebar / rows.
struct IconTile: View {
    let symbol: String
    var color: Color = .accentColor
    var size: CGFloat = DS.Size.tile

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
            .fill(BrandIcons.image(for: symbol) == nil ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
            .frame(width: size, height: size)
            .overlay {
                if let image = BrandIcons.image(for: symbol) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: size * 0.76, height: size * 0.76)
                } else {
                    Image(systemName: BrandIcons.fallbackSymbol(symbol))
                        .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .shadow(color: color.opacity(0.25), radius: 1, y: 0.5)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// Supplemental copy below a settings group. It intentionally adds no
/// horizontal padding so its text shares the pane's content gutter.
struct SettingsNote: View {
    let text: LocalizedStringKey
    var fontSize: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings Card

/// Grouped card that lays its children out as rows separated by hairline dividers,
/// matching the rounded grouped lists in the reference design.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var cardID = UUID()
    @State private var cardSize = CGSize.zero

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .coordinateSpace(name: cardID)
        .environment(\.settingsCardContext, SettingsCardContext(id: cardID, size: cardSize))
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { cardSize = geometry.size }
                    .onChange(of: geometry.size) { _, size in cardSize = size }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.035), radius: 2, y: 1)
    }
}

/// Public-API separator for rows inside `SettingsCard`.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.dividerColor)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Setting Row

/// One row inside a SettingsCard: optional leading icon, title + optional subtitle,
/// and a trailing control (toggle, picker, value, chevron…).
struct SettingRow<Trailing: View>: View {
    var icon: String?
    var iconColor: Color = .accentColor
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if let icon {
                IconTile(symbol: icon, color: iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: DS.Spacing.md)

            trailing
        }
        .padding(.horizontal, SettingsLayout.cardHorizontalInset)
        .frame(minHeight: DS.Size.rowHeight)
    }
}

extension SettingRow where Trailing == EmptyView {
    init(
        icon: String? = nil,
        iconColor: Color = .accentColor,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

// MARK: - Brand accent

extension Color {
    /// Mint/seafoam accent used across toggles and controls.
    static let morrowAccent = Color(red: 0.29, green: 0.66, blue: 0.57)
}

// MARK: - Toggle styling helper

extension View {
    /// Standard compact toggle used by settings rows. It inherits the app's
    /// environment tint, so the settings framework is reusable across brands.
    func settingsToggle() -> some View {
        self.toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}
