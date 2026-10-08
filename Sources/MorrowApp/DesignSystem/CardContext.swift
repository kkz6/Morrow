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
    var top: CGFloat
    var bottom: CGFloat
    static func resolve(button: CGRect, card: CGSize?, inset: CGFloat = 6) -> ActionCorners {
        let normal = ActionCorners(top: DS.Radius.action, bottom: DS.Radius.action)
        guard let card, card.width > 0, card.height > 0, button.width > 0,
              button.minX <= inset + 1, button.maxX >= card.width - inset - 1 else { return normal }
        let radius = min(DS.Radius.actionEdge, max(0, DS.Radius.card - inset))
        // Inset actions keep a small radius even between rows. Card-edge
        // corners expand to follow the containing card automatically.
        return ActionCorners(top: button.minY <= inset + 1 ? radius : DS.Radius.actionInterior,
                             bottom: button.maxY >= card.height - inset - 1 ? radius : DS.Radius.actionInterior)
    }
    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                               bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }
}
