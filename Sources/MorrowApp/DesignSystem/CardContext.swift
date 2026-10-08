import SwiftUI

struct SettingsCardContext: Equatable {
    let id: UUID
    let size: CGSize
}

private struct SettingsCardContextKey: EnvironmentKey {
    static let defaultValue: SettingsCardContext? = nil
}

extension EnvironmentValues {
    var settingsCardContext: SettingsCardContext? {
        get { self[SettingsCardContextKey.self] }
        set { self[SettingsCardContextKey.self] = newValue }
    }
}

struct ActionCorners: Equatable {
    var topLeading: CGFloat
    var topTrailing: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat

    init(top: CGFloat, bottom: CGFloat) {
        topLeading = top; topTrailing = top; bottomLeading = bottom; bottomTrailing = bottom
    }
    init(topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat) {
        self.topLeading = topLeading; self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading; self.bottomTrailing = bottomTrailing
    }
    static func resolve(button: CGRect, card: CGSize?, inset: CGFloat = SettingsLayout.actionInset, grouped: Bool? = nil) -> ActionCorners {
        let normal = ActionCorners(top: DS.Radius.action, bottom: DS.Radius.action)
        guard let card, card.width > 0, card.height > 0, button.width > 0 else { return normal }
        let left = button.minX <= inset + 1
        let right = button.maxX >= card.width - inset - 1
        guard grouped ?? (left && right) else { return normal }
        let top = button.minY <= inset + 1
        let bottom = button.maxY >= card.height - inset - 1
        let edge = min(DS.Radius.actionEdge, max(0, DS.Radius.card - inset))
        let inner = DS.Radius.actionInterior
        // Each outside corner follows the card. Paired buttons retain small
        // corners where they meet; bottom action rows get larger lower edges.
        return ActionCorners(topLeading: top && left ? edge : inner,
                             topTrailing: top && right ? edge : inner,
                             bottomLeading: bottom && left ? edge : inner,
                             bottomTrailing: bottom && right ? edge : inner)
    }
    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: topLeading, bottomLeadingRadius: bottomLeading,
                               bottomTrailingRadius: bottomTrailing, topTrailingRadius: topTrailing, style: .continuous)
    }
}
