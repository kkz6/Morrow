import SwiftUI
import MorrowCore

enum SettingsSection: String, Identifiable, SettingsDestination {
    case instances, sites, applications, mail, logs, storage, general, commandLine, sync, menuBar, appearance, about
    var id: String { rawValue }
    var title: LocalizedStringKey { LocalizedStringKey(textTitle) }
    var textTitle: String {
        switch self {
        case .instances: return "Databases"
        case .sites: return "Sites"
        case .applications: return "Runtimes"
        case .mail: return "Mail"
        case .commandLine: return "Command Line"
        case .logs: return "Logs"
        case .storage: return "Object Storage"
        case .general: return "General"
        case .sync: return "iCloud Sync"
        case .menuBar: return "Menu Bar"
        case .appearance: return "Appearance"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .instances: return "externaldrive.fill"
        case .sites: return "globe"
        case .applications: return "chevron.left.forwardslash.chevron.right"
        case .mail: return "envelope.fill"
        case .commandLine: return "chevron.left.forwardslash.chevron.right"
        case .logs: return "terminal.fill"
        case .storage: return "externaldrive.badge.icloud"
        case .general: return "gearshape.fill"
        case .sync: return "icloud.fill"
        case .menuBar: return "menubar.rectangle"
        case .appearance: return "paintbrush.fill"
        case .about: return "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .instances: return .teal
        case .sites: return .blue
        case .applications: return .indigo
        case .mail: return .orange
        case .commandLine: return .indigo
        case .logs: return .gray
        case .storage: return .orange
        case .general: return .gray
        case .sync: return .blue
        case .menuBar: return .blue
        case .appearance: return .purple
        case .about: return .gray
        }
    }
}

struct SettingsWindow: View {
    @Environment(AppModel.self) private var model
    private let groups: [SettingsSidebarGroup<SettingsSection>] = [
        .init("projects", header: "Projects", destinations: [.sites]),
        .init("services", header: "Services", destinations: [.instances, .applications, .mail, .storage]),
        .init("app", header: "App", destinations: [.general, .about]),
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
        .serviceFeedback()
        .sheet(item: $model.logRequest) { ServiceLogSheet(request: $0).environment(model) }
        .sheet(item: $model.configurationRequest) { ConfigurationEditorSheet(request: $0).environment(model) }
        .sheet(item: $model.creationRequest) { version in
            InstanceEditor(installation: version.installation, engine: version.engine, version: version.version).environment(model)
        }
        .sheet(item: $model.upgradeRequest) { update in
            DatabaseUpgradeSheet(update: update).environment(model)
        }
    }
    @ViewBuilder private func detail(_ section: SettingsSection) -> some View {
        switch section {
        case .instances: InstancesPane()
        case .sites: SitesPane()
        case .applications: ApplicationsPane()
        case .mail: MailPane()
        case .commandLine: CommandLinePane()
        case .logs: LogsPane()
        case .storage: StoragePane()
        case .general: GeneralPane()
        case .sync: SyncPane()
        case .menuBar: MenuBarPane()
        case .appearance: AppearancePane()
        case .about: AboutPane()
        }
    }
}

struct SettingsPane<Destination: SettingsDestination, Content: View>: View {
    let section: Destination
    var embedded = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.detailSectionSpacing) {
            // The floating shell draws the title. Retain its exact space so
            // the first content group stays on the existing 53pt top grid.
            if !embedded { Color.clear.frame(height: SettingsLayout.detailHeaderHeight).accessibilityHidden(true) }
            content
        }
        .padding(.horizontal, embedded ? 0 : SettingsLayout.detailHorizontalInset)
        .padding(.top, embedded ? 0 : SettingsLayout.detailTopInset)
        .padding(.bottom, embedded ? 0 : SettingsLayout.detailBottomInset)
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
