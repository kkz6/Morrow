import SwiftUI

/// Toolbar selection uses a native menu with native checked choices and glass.
struct SettingsMenuPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    private var selected: SelectOption<Value>? { options.first { $0.value == selection } }

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options) { option in Text(option.title).tag(option.value) }
            }.pickerStyle(.inline)
        } label: {
            Label(selected?.title ?? label, systemImage: selected?.symbol ?? "line.3.horizontal.decrease")
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 170)
        }
        .settingsMenuControl(iconOnly: false)
        .disabled(options.isEmpty)
        .accessibilityLabel(label)
        .accessibilityValue(selected?.title ?? label)
    }
}
