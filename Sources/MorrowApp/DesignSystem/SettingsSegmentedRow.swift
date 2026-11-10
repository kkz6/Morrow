import SwiftUI

/// Small preference sets use native segmented controls.
struct SettingsSegmentedRow<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [SelectOption<Value>]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title).font(.system(size: 13))
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Label(option.title, systemImage: option.symbol).tag(option.value)
                }
            }.pickerStyle(.segmented).labelsHidden()
        }.settingsCellPadding()
    }
}
