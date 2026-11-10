import SwiftUI
import MorrowCore

struct ProjectHealthSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let site: LocalSite
    @State private var report: ProjectInspection?
    @State private var issue: String?
    @State private var loading = false
    @State private var versions = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconTile(symbol: "stethoscope", color: .morrowAccent, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Project Health").font(.system(size: 18, weight: .semibold))
                    Text(site.domain).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                ServiceActionButton(kind: .refresh, title: "Check project again") { Task { await refresh() } }.disabled(loading)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report {
                        SettingsGroup {
                            SettingRow(title: LocalizedStringKey(report.profile.name), subtitle: LocalizedStringKey(report.path)) {
                                Text(report.warningCount == 0 ? "Checks passed" : "\(report.warningCount) to review")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(report.warningCount == 0 ? Color.secondary : Color.orange)
                            }
                        }
                        if !report.checks.isEmpty {
                            SettingsGroup(header: "Setup checks") {
                                ForEach(Array(report.checks.enumerated()), id: \.element.id) { index, check in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: check.level == .passed ? "checkmark.circle" : check.level == .warning ? "exclamationmark.circle" : "info.circle")
                                            .foregroundStyle(check.level == .warning ? Color.orange : check.level == .passed ? Color.morrowAccent : Color.secondary)
                                            .frame(width: 16).padding(.top, 1)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(check.title).font(.system(size: 12, weight: .medium))
                                            Text(check.detail).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.settingsCellPadding()
                                    if index < report.checks.count - 1 { SettingsDivider() }
                                }
                            }
                        }
                        if !report.requirements.isEmpty {
                            SettingsGroup(header: "Declared requirements") {
                                ForEach(Array(report.requirements.enumerated()), id: \.element.id) { index, requirement in
                                    SettingRow(title: LocalizedStringKey(requirement.name), subtitle: LocalizedStringKey(requirement.source)) {
                                        Text(requirement.version).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                                    }
                                    if index < report.requirements.count - 1 { SettingsDivider() }
                                }
                            }
                        }
                    }
                    if let issue { ErrorCard(message: issue) { self.issue = nil } }
                    SettingsNote(text: "Checks local files and saved runtime choices. It does not verify installed PHP extensions, dependency versions, database access, or live application health. Requirements are shown for review; project files and services stay unchanged.")
                }.padding(.vertical, 2)
            }
            HStack {
                Button("Folder Versions…") { versions = true }.settingsButton()
                Button("Reveal Folder") { NSWorkspace.shared.open(URL(fileURLWithPath: site.path)) }.settingsButton()
                Spacer()
                Button("Done") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 600, height: 520)
        .task { await refresh() }
        .feedbackSheet(isPresented: $versions) { ProjectVersionEditor(path: site.path).environment(model) }
        .onChange(of: versions) { _, presented in if !presented { Task { await refresh() } } }
    }
    private func refresh() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        let store = model.manager.store, site = site
        do {
            let report = try await Task.detached { try ProjectInspection.inspect(path: site.path, store: store, site: site) }.value
            try Task.checkCancellation(); self.report = report; issue = nil
        } catch { if !Task.isCancelled { report = nil; issue = error.localizedDescription } }
    }
}
