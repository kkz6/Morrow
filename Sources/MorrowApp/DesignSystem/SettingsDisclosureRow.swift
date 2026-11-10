import SwiftUI

/// A quiet, full-width disclosure that shares the card's content gutters.
struct SettingsDisclosureRow: View {
    let title: String
    var subtitle: String?
    @Binding var isExpanded: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).frame(width: 12)
                Image(systemName: "arrow.triangle.branch")
                Text(title).fontWeight(.medium)
                Spacer(minLength: DS.Spacing.sm)
                if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
            }
            .font(.system(size: 11))
            .settingsCellPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help(isExpanded ? "Hide worktrees" : "Show worktrees")
    }
}
