import SwiftUI

struct SelectOption<Value: Hashable>: Identifiable, Equatable {
    let value: Value
    let title: String
    let symbol: String
    var id: Value { value }
}

/// Native menus provide the selected state, keyboard navigation and accessibility.
struct SettingsSelect<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    var placeholder = "Choose…"
    var placeholderSymbol = "square.stack.3d.up"

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options) { option in
                    Label {
                        Text(option.title)
                    } icon: {
                        if let image = BrandIcons.menuImage(for: option.symbol) {
                            Image(nsImage: image)
                        } else {
                            Image(systemName: BrandIcons.fallbackSymbol(option.symbol))
                        }
                    }.tag(option.value)
                }
            }.pickerStyle(.inline)
        } label: {
            Text(options.first { $0.value == selection }?.title ?? placeholder)
                .lineLimit(1).truncationMode(.middle)
        }
        .settingsPickerControl()
        .disabled(options.isEmpty)
        .accessibilityLabel(label)
        .accessibilityValue(options.first { $0.value == selection }?.title ?? placeholder)
    }
}
