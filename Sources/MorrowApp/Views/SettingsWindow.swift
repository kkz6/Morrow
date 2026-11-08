import SwiftUI
import MorrowCore

enum SettingsSection: String, Identifiable, SettingsDestination {
    case instances, sites, applications, mail, logs, storage, general, commandLine, sync, menuBar, appearance, about
    var id: String { rawValue }
    var feedbackSection: SettingsSection {
        switch self {
        case .commandLine, .sync, .menuBar, .appearance: return .general
        case .logs: return .instances
        default: return self
        }
    }
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
            detail(section)
        }
        .feedbackSheet(item: $model.logRequest) { ServiceLogSheet(request: $0).environment(model) }
        .feedbackSheet(item: $model.configurationRequest) { ConfigurationEditorSheet(request: $0).environment(model) }
        .feedbackSheet(item: $model.creationRequest) { version in
            InstanceEditor(installation: version.installation, engine: version.engine, version: version.version).environment(model)
        }
        .feedbackSheet(item: $model.upgradeRequest) { update in
            DatabaseUpgradeSheet(update: update).environment(model)
        }
        .feedbackSheet(isPresented: $model.onboardingPresented) { OnboardingSheet().environment(model) }
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
    @Environment(AppModel.self) private var model

    var body: some View {
        if embedded {
            paneContent
        } else {
            ZStack(alignment: .top) {
                ScrollView {
                    paneContent
                        .padding(.horizontal, SettingsLayout.detailHorizontalInset)
                        .padding(.top, FloatingHeaderMetrics.height)
                        .padding(.bottom, SettingsLayout.detailBottomInset)
                }
                .scrollContentBackground(.hidden)

                FloatingSettingsHeader(section: section)
            }
            .overlay(alignment: .bottom) {
                SettingsEdgeBackdrop(edge: .bottom)
                    .frame(height: SettingsScrollEdge.bottom.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var paneContent: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.detailSectionSpacing) {
            if !embedded, let section = section as? SettingsSection {
                SettingsPageFeedback(section: section)
            }
            content
            if !embedded {
                if let activity = model.activity {
                    HStack(spacing: DS.Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(activity).font(.system(size: 12))
                    }
                }
                if let error = model.error, model.toast?.text != error {
                    ErrorCard(message: error) { model.error = nil }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section title stays close to its content, including embedded preferences.
struct SettingsSubsection<Content: View>: View {
    var header: LocalizedStringKey?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.groupHeaderSpacing) {
            if let header { SectionHeader(title: header) }
            content
        }
    }
}

struct SettingsGroup<Content: View>: View {
    var header: LocalizedStringKey?
    @ViewBuilder var content: Content
    var body: some View {
        SettingsSubsection(header: header) {
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
