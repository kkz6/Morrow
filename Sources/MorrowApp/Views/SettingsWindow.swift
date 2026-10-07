import SwiftUI
import MorrowCore

enum SettingsSection: String, Identifiable, SettingsDestination {
    case instances, logs, storage, general, commandLine, menuBar, appearance, about
    var id: String { rawValue }
    var title: LocalizedStringKey { LocalizedStringKey(textTitle) }
    var textTitle: String {
        switch self {
        case .instances: return "Databases"
        case .commandLine: return "Command Line"
        case .logs: return "Logs"
        case .storage: return "Storage"
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .appearance: return "Appearance"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .instances: return "externaldrive.fill"
        case .commandLine: return "chevron.left.forwardslash.chevron.right"
        case .logs: return "terminal.fill"
        case .storage: return "folder.fill"
        case .general: return "gearshape.fill"
        case .menuBar: return "menubar.rectangle"
        case .appearance: return "paintbrush.fill"
        case .about: return "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .instances: return .teal
        case .commandLine: return .indigo
        case .logs: return .gray
        case .storage: return .orange
        case .general: return .gray
        case .menuBar: return .blue
        case .appearance: return .purple
        case .about: return .gray
        }
    }
}

struct SettingsWindow: View {
    @Environment(AppModel.self) private var model
    private let groups: [SettingsSidebarGroup<SettingsSection>] = [
        .init("databases", header: "Workspace", destinations: [.instances, .logs, .storage]),
        .init("app", header: "App", destinations: [.general, .commandLine, .menuBar, .appearance, .about]),
    ]
    var body: some View {
        @Bindable var model = model
        SettingsShell(selection: $model.selection, groups: groups) { section in
            VStack(spacing: 0) {
                detail(section)
                if let activity = model.activity {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(activity).font(.system(size: 12)) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                if let error = model.error { ErrorCard(message: error) { model.error = nil }.padding(.horizontal, 16).padding(.bottom, 16) }
            }
        }
        .sheet(item: $model.creationRequest) { version in
            InstanceEditor(installation: version.installation, engine: version.engine, version: version.version).environment(model)
        }
    }
    @ViewBuilder private func detail(_ section: SettingsSection) -> some View {
        switch section {
        case .instances: InstancesPane()
        case .commandLine: CommandLinePane()
        case .logs: LogsPane()
        case .storage: StoragePane()
        case .general: GeneralPane()
        case .menuBar: MenuBarPane()
        case .appearance: AppearancePane()
        case .about: AboutPane()
        }
    }
}

struct SettingsPane<Destination: SettingsDestination, Content: View>: View {
    let section: Destination
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.detailSectionSpacing) {
            // The floating shell draws the title. Retain its exact space so
            // the first content group stays on the existing 53pt top grid.
            Color.clear.frame(height: SettingsLayout.detailHeaderHeight).accessibilityHidden(true)
            content
        }
        .padding(.horizontal, SettingsLayout.detailHorizontalInset)
        .padding(.top, SettingsLayout.detailTopInset)
        .padding(.bottom, SettingsLayout.detailBottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsGroup<Content: View>: View {
    var header: LocalizedStringKey?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.groupHeaderSpacing) {
            if let header { SectionHeader(title: header) }
            SettingsCard { content }
        }
    }
}

struct ErrorCard: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss")
        }.padding(12).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
