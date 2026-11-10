import SwiftUI

/// Compact native choices for content views, using the same control sizing as inputs.
struct SettingsTabs<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [SelectOption<Value>]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options) { option in Text(option.title).tag(option.value) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .accessibilityLabel(title)
    }
}
