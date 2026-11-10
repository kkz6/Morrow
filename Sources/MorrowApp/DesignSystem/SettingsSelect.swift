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
        Picker(label, selection: $selection) {
            if !options.contains(where: { $0.value == selection }) {
                Text(placeholder).tag(selection).disabled(true)
            }
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
        }
        .labelsHidden().pickerStyle(.menu)
        .tint(.primary).foregroundStyle(.primary).controlSize(.regular)
        .disabled(options.isEmpty)
        .accessibilityLabel(label)
        .accessibilityValue(options.first { $0.value == selection }?.title ?? placeholder)
    }
}
