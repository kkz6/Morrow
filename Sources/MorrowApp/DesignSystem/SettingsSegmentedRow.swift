import SwiftUI

/// Visible choices for small preference sets; runtime/version lists continue
/// to use SettingsSelect's native popup menu.
struct SettingsSegmentedRow<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title).font(.system(size: 13))
            HStack(spacing: DS.Spacing.sm) {
                ForEach(options) { option in
                    let selected = option.value == selection
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            selection = option.value
                        }
                    } label: {
                        VStack(spacing: DS.Spacing.sm) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 17, weight: .medium))
                            Text(option.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                        }
                        .foregroundStyle(selected ? Color.primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SettingsLayout.cardVerticalInset)
                        .background {
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .fill(selected ? AnyShapeStyle(.tint.opacity(0.10)) : AnyShapeStyle(DS.Surface.control(colorScheme)))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(DS.Surface.border(colorScheme)), lineWidth: selected ? 2 : 0.75)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
        .settingsCellPadding()
    }
}
