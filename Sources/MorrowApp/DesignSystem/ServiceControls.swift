import SwiftUI
import MorrowCore

/// Small consistent controls for every managed service. Tooltips describe the
/// action; lifecycle state is presented separately from the control itself.
struct ServiceActionButton: View {
    enum Action { case start, stop, logs, configuration, copy, refresh, open, remove
        var symbol: String {
            switch self { case .start: return "play.fill"; case .stop: return "stop.fill"; case .logs: return "terminal"; case .configuration: return "slider.horizontal.3"; case .copy: return "doc.on.doc"; case .refresh: return "arrow.clockwise"; case .open: return "arrow.up.right.square"; case .remove: return "trash" }
        }
    }
    let kind: Action
    let title: String
    var compact = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: kind.symbol).font(.system(size: 12, weight: .medium)).frame(width: compact ? MenuLayout.actionSize : 28, height: compact ? MenuLayout.actionSize : 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(kind == .stop || kind == .remove ? Color.red : Color.secondary)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.action))
        .help(title).accessibilityLabel(title)
    }
}

struct ServiceStatusView: View {
    let status: InstanceStatus
    var compact = false
    var body: some View {
        HStack(spacing: 6) {
            if status == .starting { ProgressView().controlSize(.mini) }
            else { Circle().fill(color).frame(width: 6, height: 6) }
            if !compact { Text(status.title).font(.system(size: 11, weight: .medium)) }
        }.foregroundStyle(color).help(status.title).accessibilityLabel(status.title).accessibilityElement(children: .combine)
    }
    private var color: Color {
        switch status { case .running: return .green; case .starting: return .orange; case .failed, .missingBinary: return .red; default: return .secondary }
    }
}
