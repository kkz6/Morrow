import SwiftUI
import MorrowCore

struct DatabasePopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettingsWindow) private var openSettings
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Morrow").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.runningCount) running").font(.system(size: 11)).foregroundStyle(.secondary)
                Button { model.requestCreation(); openSettings() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 22)
                }.buttonStyle(SettingsButtonStyle(height: 26, iconOnly: true)).help("New instance").disabled(model.busy)
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            if model.instances.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus").font(.system(size: 28, weight: .light)).foregroundStyle(.teal)
                    Text("Your workspace starts here").font(.system(size: 13, weight: .medium))
                    Text("Create an instance. Installation is handled for you.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Create Instance") { model.requestCreation(); openSettings() }.settingsButton(expands: true)
                        .padding(.horizontal, 16).padding(.top, 6)
                }.frame(maxWidth: .infinity).padding(.vertical, 25)
            } else if !model.instances.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.instances.enumerated()), id: \.element.id) { index, instance in
                            PopoverInstanceRow(instance: instance)
                            if index < model.instances.count - 1 { Divider().padding(.leading, 54).opacity(0.5) }
                        }
                    }
                }.frame(height: CGFloat(min(model.instances.count, 6)) * 58).scrollBounceBehavior(.basedOnSize)
            }
            if let activity = model.activity {
                HStack(spacing: 8) { ProgressView().controlSize(.mini); Text(activity).font(.system(size: 11)).lineLimit(2); Spacer() }
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            if let error = model.error { ErrorCard(message: error) { model.error = nil }.padding(10) }
            Divider().opacity(0.4)
            HStack(spacing: 12) {
                Text("Native · Local").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button { openSettings() } label: { Image(systemName: "gearshape").frame(width: 26, height: 26) }
                    .buttonStyle(SettingsButtonStyle(height: 28, iconOnly: true)).help("Settings").keyboardShortcut(",", modifiers: .command)
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power").frame(width: 26, height: 26) }
                    .buttonStyle(SettingsButtonStyle(height: 28, iconOnly: true)).help("Quit Morrow — databases stay running").disabled(model.busy)
            }.foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 5)
        }.frame(width: 340)
            .task { await model.refresh() }
    }
}

private struct PopoverInstanceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettingsWindow) private var openSettings
    let instance: DatabaseInstance
    private var status: InstanceStatus { model.statuses[instance.id] ?? .unknown }
    private var active: Bool { [.running, .starting].contains(status) }
    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: instance.engine.symbol, color: instance.engine.color, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("\(instance.engine.title) · :\(String(instance.port))").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Circle().fill(status == .running ? Color.green : status == .starting ? .orange : .secondary.opacity(0.4)).frame(width: 6, height: 6).help(status.title)
            Button {
                let id = instance.id, shouldStop = active
                model.perform(active ? "Stopping \(instance.name)…" : "Starting \(instance.name)…") { manager in
                    if shouldStop { try manager.stop(id) } else { try manager.start(id) }
                }
            } label: { Image(systemName: active ? "stop.fill" : "play.fill").font(.system(size: 10)) }
                .buttonStyle(SettingsButtonStyle(height: 26, iconOnly: true)).help(active ? "Stop" : "Start").disabled(model.busy || status == .missingBinary)
            Button { model.showLogs(for: instance); openSettings() } label: {
                Image(systemName: "terminal").font(.system(size: 11))
            }.buttonStyle(SettingsButtonStyle(height: 26, iconOnly: true)).help("View logs in Morrow")
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(instance.connectionURL, forType: .string)
            } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }.buttonStyle(SettingsButtonStyle(height: 26, iconOnly: true)).help("Copy connection address")
        }.padding(.horizontal, 16).frame(height: 58)
    }
}
