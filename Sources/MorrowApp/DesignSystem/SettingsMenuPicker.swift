import SwiftUI

/// A compact toolbar picker using the same native menu as settings selectors.
struct SettingsMenuPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [SelectOption<Value>]

    var body: some View {
        SettingsSelect(label: label, selection: $selection, options: options, placeholder: label)
            .frame(maxWidth: 190)
            .fixedSize(horizontal: true, vertical: false)
    }
}
