import SwiftUI
import MorrowCore

struct SitesPane: View {
    @Environment(AppModel.self) private var model
    @State private var directories = false
    @State private var settings = false
    @State private var adding = false
    @State private var editing: LocalSite?
    @State private var query = ""
    @State private var php: [RuntimeInstallation] = []
    private var projects: [LocalSite] { model.web.sites.filter { query.isEmpty || $0.domain.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        SettingsPane(section: SettingsSection.sites) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your local projects").font(.system(size: 13, weight: .medium))
                    Text("\(model.web.sites.count) sites · .\(model.web.suffix)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Project Directories…") { directories = true }.settingsButton().disabled(model.busy)
            }
            SettingsGroup {
                SettingRow(title: "Web server") {
                    HStack {
                        StatusBadge(status: model.webStatus?.proxy ?? .stopped)
                        ServiceActionButton(kind: model.web.enabled ? .stop : .start, title: model.web.enabled ? "Stop local hosting" : "Start local hosting") {
                            let stop = model.web.enabled, cli = model.cliURL
                            model.perform(stop ? "Stopping Sites…" : "Starting Sites…", success: stop ? "Local hosting stopped" : "Local hosting started") { manager in
                                let sites = SiteManager(store: manager.store, runner: manager.runner)
                                if stop { try sites.stop() } else { try sites.start(cli: cli) }
                            }
                        }.disabled(model.busy)
                    }
                }
                SettingsDivider()
                SettingRow(title: "Local DNS") {
                    HStack { ServiceStatusView(status: model.webStatus?.dns ?? .stopped); ServiceActionButton(kind: .logs, title: "Open DNS logs") { model.logRequest = ServiceLogRequest(title: "Local DNS", subtitle: "dnsmasq", url: model.sites.dnsLogURL) } }
                }
                SettingsDivider()
                SettingRow(title: "Default PHP") {
                    if php.isEmpty {
                        Button("Install PHP-FPM") { model.perform("Preparing PHP-FPM…") { try SiteManager(store: $0.store, runner: $0.runner).installPHP() } }.settingsButton(height: 28).disabled(model.busy)
                    } else {
                        SettingsSelect(label: "Sites PHP version", selection: Binding(get: { model.web.defaultPHPID ?? php.first?.id ?? "" }, set: { id in
                            guard let item = php.first(where: { $0.id == id }) else { return }
                            model.perform("Selecting PHP \(item.version)…") { try SiteManager(store: $0.store, runner: $0.runner).selectPHP(item) }
                        }), options: php.map { .init(value: $0.id, title: $0.version, symbol: "morrow.php") }).disabled(model.busy)
                    }
                }
                SettingsDivider()
                SettingsActionRow(title: "Hosting Settings…", symbol: "gearshape") { settings = true }.disabled(model.busy)
            }
            SettingsGroup(header: "Domain Setup") {
                Text(model.webStatus?.setupMessage ?? "Enable Local Domains for URLs without port numbers.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                SettingsDivider()
                SettingsActionRow(title: model.webStatus?.systemConfigured == true ? "Local Domains Configured" : "Enable Local Domains…", symbol: "network") { model.installSiteSystemSetup() }
                    .disabled(model.busy || model.webStatus?.systemConfigured == true)
                SettingsDivider()
                SettingsActionRow(title: "Trust Local HTTPS Certificate…", symbol: "lock.shield") {
                    model.trustHTTPS()
                }.disabled(model.busy)
                SettingsDivider()
                SettingsActionRow(title: "Check HTTPS", symbol: "checkmark.shield") { model.checkHTTPS() }.disabled(model.busy)
                if !model.httpsMessage.isEmpty { Text(model.httpsMessage).font(.system(size: 12)).foregroundStyle(.secondary).padding(12) }
            }
            HStack {
                SectionHeader(title: "Projects")
                Spacer()
                Button("Link Project…") { adding = true }.settingsButton().disabled(model.busy)
                Button { model.perform("Refreshing projects…") { try SiteManager(store: $0.store, runner: $0.runner).refreshProjects(force: true) } } label: { Image(systemName: "arrow.clockwise") }.settingsButton().disabled(model.busy)
            }
            if model.web.sites.isEmpty {
                SettingsCard {
                    Text("Park a parent directory to discover PHP and static sites automatically, or link a project to an app's local port.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }
            } else {
                SettingsInput(placeholder: "Find a project", text: $query, symbol: "magnifyingglass", clearable: true)
                SettingsGroup {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, site in
                        siteRow(site)
                        if index < projects.count - 1 { SettingsDivider() }
                    }
                }
            }
            SettingsGroup(header: "Development Commands") {
                Text("morrow site link --port 3000\nmorrow site secure folder-name.\(model.web.suffix)")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            SettingsNote(text: "Local hosting runs independently of the app. Directory changes are watched while Sites is enabled. HTTPS uses this Mac's private development CA; trust is a separate step.")
        }
        .sheet(isPresented: $directories) { ProjectDirectoriesSheet().environment(model) }
        .sheet(isPresented: $settings) { HostingSettingsSheet().environment(model) }
        .sheet(isPresented: $adding) { LinkSiteSheet().environment(model) }
        .sheet(item: $editing) { SiteEditor(site: $0, php: php).environment(model) }
        .task(id: model.inventory.runtimes.map(\.id)) { php = model.inventory.runtimes.filter { $0.engine == .php && $0.phpFPM != nil } }
    }
    private func siteRow(_ site: LocalSite) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: site.mode == .proxy ? "arrow.triangle.branch" : site.https ? "lock.fill" : "globe", color: .blue, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(site.domain).font(.system(size: 13, weight: .semibold))
                Text(site.mode == .proxy ? "127.0.0.1:\(site.proxyPort.map(String.init) ?? "—")" : site.documentRoot).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(site.ignored ? "Ignored for .\(model.web.suffix) hosting" : site.issue ?? model.webStatus?.sites[site.id]?.rawValue ?? "Stopped").font(.system(size: 11)).foregroundStyle(site.issue == nil ? Color.secondary : Color.orange).lineLimit(2)
            }
            Spacer()
            Toggle("HTTPS for \(site.domain)", isOn: Binding(get: { site.https }, set: { value in
                var changed = site; changed.https = value
                let saved = changed
                model.perform("Updating HTTPS…", success: value ? "HTTPS enabled. Trust the local certificate in Domain Setup, then check HTTPS." : "HTTPS disabled for this project") { try SiteManager(store: $0.store, runner: $0.runner).update(saved) }
            })).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.busy || site.issue != nil)
            ServiceActionButton(kind: .logs, title: "Open site routing logs") { model.showSiteLogs() }
            Menu {
                Button(site.ignored ? "Include in .\(model.web.suffix) hosting" : "Ignore for .\(model.web.suffix) hosting") {
                    let ignore = !site.ignored
                    model.perform(ignore ? "Ignoring project…" : "Including project…", success: ignore ? "Project ignored for local domains; folder preserved" : "Project included in local hosting") { try SiteManager(store: $0.store, runner: $0.runner).ignore(site.id, ignored: ignore) }
                }
                Button("Open Site") { NSWorkspace.shared.open(model.sites.url(site, web: model.web)) }
                Button("Project Settings…") { editing = site }
                Button("Reveal Project") { NSWorkspace.shared.open(URL(fileURLWithPath: site.path)) }
                Button("View Routing Log") { model.showSiteLogs() }
                if site.directoryID == nil { Button("Unlink", role: .destructive) { model.perform("Removing route…") { try SiteManager(store: $0.store, runner: $0.runner).unlink(site.id) } } }
            } label: { Image(systemName: "ellipsis").frame(width: 16) }.settingsMenuControl().disabled(model.busy)
        }.padding(.horizontal, 12).padding(.vertical, 14)
    }
}

private struct ProjectDirectoriesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Project Directories").font(.system(size: 18, weight: .semibold))
            Text("Each immediate project folder receives a domain. Removing a directory removes its discovered routes and preserves the folders.").font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                SettingsGroup {
                    ForEach(Array(model.web.directories.enumerated()), id: \.element.id) { index, directory in
                        HStack(spacing: 10) {
                            Image(systemName: "folder").foregroundStyle(.orange)
                            Text(directory.path).font(.system(size: 12)).lineLimit(2).textSelection(.enabled)
                            Spacer()
                            Toggle("Enable directory", isOn: Binding(get: { directory.enabled }, set: { enabled in
                                model.perform("Updating directory…") { try SiteManager(store: $0.store, runner: $0.runner).setDirectory(directory.id, enabled: enabled) }
                            })).labelsHidden().settingsToggle()
                            ServiceActionButton(kind: .remove, title: "Unpark directory; preserve its project folders") { let path = directory.path; model.perform("Removing directory…", success: "Directory unparked; project folders preserved") { try SiteManager(store: $0.store, runner: $0.runner).unpark(path) } }
                        }.padding(12).disabled(model.busy)
                        if index < model.web.directories.count - 1 { SettingsDivider() }
                    }
                    if model.web.directories.isEmpty { Text("No directories parked yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(16) }
                    SettingsDivider()
                    SettingsActionRow(title: "Add Project Directory…", symbol: "folder.badge.plus") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        model.perform("Discovering projects…") { try SiteManager(store: $0.store, runner: $0.runner).park(url.path) }
                    }.disabled(model.busy)
                }
            }.frame(maxHeight: 330)
            if let error = model.error { ErrorCard(message: error) { model.error = nil } }
            HStack { Spacer(); Button("Done") { dismiss() }.settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy) }
        }.padding(20).frame(width: 540)
    }
}

private struct HostingSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var suffix = "test"
    @State private var http = "8080"
    @State private var https = "8443"
    @State private var dns = "5354"
    @State private var secure = false
    @State private var autoStart = true
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hosting Settings").font(.system(size: 18, weight: .semibold))
            SettingsGroup {
                SettingRow(title: "Development suffix") { SettingsInput(placeholder: "test", text: $suffix).frame(width: 180) }
                SettingsDivider()
                SettingRow(title: "HTTPS for new sites") { Toggle("HTTPS for new sites", isOn: $secure).settingsToggle() }
                SettingsDivider()
                SettingRow(title: "Start hosting at login") { Toggle("Start hosting at login", isOn: $autoStart).settingsToggle() }
                SettingsDivider()
                SettingRow(title: "HTTP listener") { SettingsInput(placeholder: "8080", text: $http).frame(width: 100) }.disabled(model.web.enabled)
                SettingsDivider()
                SettingRow(title: "HTTPS listener") { SettingsInput(placeholder: "8443", text: $https).frame(width: 100) }.disabled(model.web.enabled)
                SettingsDivider()
                SettingRow(title: "DNS listener") { SettingsInput(placeholder: "5354", text: $dns).frame(width: 100) }.disabled(model.web.enabled)
            }.disabled(model.busy)
            Text("Use test, internal, localhost, or a namespace such as morrow.test. Stop Sites to change listener ports. Changing suffixes may require local-domain setup again.").font(.system(size: 12)).foregroundStyle(.secondary)
            if let error = issue ?? model.error { ErrorCard(message: error) { issue = nil; model.error = nil } }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction).disabled(model.busy)
                Button("Save") {
                    guard let http = Int(http), let https = Int(https), let dns = Int(dns) else { issue = "Enter numeric listener ports."; return }
                    let suffix = suffix, secure = secure, auto = autoStart
                    model.perform("Saving hosting defaults…", operation: { try SiteManager(store: $0.store, runner: $0.runner).configure(suffix: suffix, defaultHTTPS: secure, http: http, https: https, dns: dns, autoStart: auto) }, completion: { dismiss() })
                }.settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy)
            }
        }.padding(20).frame(width: 480).onAppear {
            suffix = model.web.suffix; http = String(model.web.httpPort); https = String(model.web.httpsPort); dns = String(model.web.dnsPort)
            secure = model.web.defaultHTTPS; autoStart = model.web.autoStart
        }
    }
}

private struct LinkSiteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var domain = ""
    @State private var port = ""
    @State private var secure = false
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link Project").font(.system(size: 18, weight: .semibold))
            SettingsGroup {
                SettingRow(title: "Project folder") {
                    HStack {
                        Text(path.isEmpty ? "Choose a folder" : URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 12)).lineLimit(1)
                        Button("Choose…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                            guard panel.runModal() == .OK, let selected = panel.url else { return }
                            path = selected.path; domain = (try? SiteManager.domain(for: path, suffix: model.web.suffix)) ?? ""
                        }.settingsButton(height: 28)
                    }
                }
                SettingsDivider()
                SettingRow(title: "Domain") { SettingsInput(placeholder: "folder-name.\(model.web.suffix)", text: $domain).frame(width: 220) }
                SettingsDivider()
                SettingRow(title: "Application port", subtitle: "Leave empty for PHP or static hosting") { SettingsInput(placeholder: "3000", text: $port).frame(width: 100) }
                SettingsDivider()
                SettingRow(title: "HTTPS") { Toggle("HTTPS", isOn: $secure).settingsToggle() }
            }.disabled(model.busy)
            Text("For npm scripts, run morrow site link --port 3000 from your project directory. Start your app on that local port; Morrow manages its hostname and TLS.").font(.system(size: 12)).foregroundStyle(.secondary)
            if let error = issue ?? model.error { ErrorCard(message: error) { issue = nil; model.error = nil } }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction).disabled(model.busy)
                Button("Link Project") {
                    let path = path, domain = domain, secure = secure
                    let number: Int?
                    if port.trimmingCharacters(in: .whitespaces).isEmpty { number = nil }
                    else { guard let value = Int(port) else { issue = "Enter a numeric application port."; return }; number = value }
                    let generated = try? SiteManager.domain(for: path, suffix: model.web.suffix)
                    let custom = domain.isEmpty || domain == generated ? nil : domain
                    model.perform("Linking project…", operation: { _ = try SiteManager(store: $0.store, runner: $0.runner).link(path: path, port: number, domain: custom, https: secure) }, completion: { dismiss() })
                }.settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy || path.isEmpty)
            }
        }.padding(20).frame(width: 490).onAppear { secure = model.web.defaultHTTPS }
    }
}

private struct SiteEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let site: LocalSite
    let php: [RuntimeInstallation]
    @State private var domain = ""
    @State private var root = ""
    @State private var mode = SiteMode.php
    @State private var port = ""
    @State private var secure = false
    @State private var phpID = ""
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Project Settings").font(.system(size: 18, weight: .semibold))
            Text(site.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            SettingsGroup {
                SettingRow(title: "Domain") { SettingsInput(placeholder: "project.\(model.web.suffix)", text: $domain).frame(width: 230) }
                SettingsDivider()
                SettingRow(title: "Hosting") {
                    SettingsSelect(label: "Hosting mode", selection: $mode, options: [
                        .init(value: .php, title: "PHP", symbol: "chevron.left.forwardslash.chevron.right"),
                        .init(value: .files, title: "Static files", symbol: "doc"),
                        .init(value: .proxy, title: "App port", symbol: "arrow.triangle.branch")])
                }
                SettingsDivider()
                if mode == .proxy {
                    SettingRow(title: "Application port") { SettingsInput(placeholder: "3000", text: $port).frame(width: 100) }
                } else {
                    SettingRow(title: "Document root") { SettingsInput(placeholder: "public", text: $root).frame(width: 230) }
                }
                if mode == .php {
                    SettingsDivider()
                    SettingRow(title: "PHP version") {
                        SettingsSelect(label: "Project PHP version", selection: $phpID, options: [.init(value: "", title: "Sites default", symbol: "gearshape")] + php.map { .init(value: $0.id, title: $0.version, symbol: "morrow.php") })
                    }
                }
                SettingsDivider()
                SettingRow(title: "HTTPS") { Toggle("HTTPS", isOn: $secure).settingsToggle() }
            }.disabled(model.busy)
            if let error = issue ?? model.error { ErrorCard(message: error) { issue = nil; model.error = nil } }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction).disabled(model.busy)
                Button("Save") {
                    var proposed = site; proposed.domain = domain; proposed.mode = mode; proposed.https = secure; proposed.phpID = phpID.isEmpty ? nil : phpID
                    if mode == .proxy { guard let port = Int(port) else { issue = "Enter the application's numeric port."; return }; proposed.proxyPort = port }
                    proposed.documentRoot = root.hasPrefix("/") ? root : URL(fileURLWithPath: site.path).appendingPathComponent(root.isEmpty ? "." : root).standardizedFileURL.path
                    let saved = proposed
                    let runtime = php.first { $0.id == saved.phpID }
                    model.perform("Saving project route…", operation: { manager in
                        let sites = SiteManager(store: manager.store, runner: manager.runner)
                        if let runtime { try sites.registerPHP(runtime) }
                        try sites.update(saved)
                    }, completion: { dismiss() })
                }.settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy)
            }
        }.padding(20).frame(width: 490).onAppear {
            domain = site.domain; root = site.documentRoot; mode = site.mode; port = site.proxyPort.map(String.init) ?? ""; secure = site.https; phpID = site.phpID ?? ""
        }
    }
}
