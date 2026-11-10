import SwiftUI

/// Visible preference choices shared with the settings design framework.
struct SettingsSegmentedRow<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13))
            HStack(spacing: DS.Spacing.sm) {
                ForEach(options) { option in
                    let selected = option.value == selection
                    VStack(spacing: 8) {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { selection = option.value }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Color.primary.opacity(0.05)))
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(DS.borderColor), lineWidth: selected ? 2 : 1)
                                Image(systemName: option.symbol).font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(selected ? Color.primary : .secondary)
                            }.frame(height: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel(option.title)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        Text(option.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity)
                }
            }
        }.settingsCellPadding()
    }
}
