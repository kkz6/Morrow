import SwiftUI

/// A text-only toolbar menu; the native menu supplies selection checkmarks.
struct SettingsMenuPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options) { option in Text(option.title).tag(option.value) }
            }.pickerStyle(.inline)
        } label: {
            Text(options.first { $0.value == selection }?.title ?? label)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 170)
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton).menuIndicator(.visible)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, DS.Spacing.md).frame(height: ControlLayout.height)
        .background(DS.Surface.control(colorScheme, state: !enabled ? .disabled : hovering ? .hovered : .normal), in: RoundedRectangle(cornerRadius: ControlLayout.radius))
        .overlay(RoundedRectangle(cornerRadius: ControlLayout.radius).strokeBorder(DS.Surface.border(colorScheme, enabled: enabled), lineWidth: DS.Stroke.border))
        .onHover { hovering = $0 }
        .tint(.primary).accessibilityLabel(label)
    }
}
