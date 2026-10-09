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
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: kind.symbol).font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28)
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

struct ToastNotice: Identifiable {
    let id = UUID()
    let text: String
    var error = false
}
struct ToastView: View {
    let notice: ToastNotice
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.error ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(notice.error ? Color.orange : Color.teal)
            Text(notice.text).font(.system(size: 12)).lineLimit(3)
        }.padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.actionEdge))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.actionEdge).strokeBorder(DS.borderColor, lineWidth: 0.5))
            .padding(14).accessibilityElement(children: .combine)
    }
}

private struct ServiceFeedbackModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let notice = model.toast { ToastView(notice: notice).allowsHitTesting(false).transition(.opacity) }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.toast?.id)
    }
}
extension View {
    func serviceFeedback() -> some View { modifier(ServiceFeedbackModifier()) }
}
