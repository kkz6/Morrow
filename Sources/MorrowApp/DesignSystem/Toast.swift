import SwiftUI

struct ToastAction {
    let title: String
    let perform: () -> Void
}

struct ToastNotice: Identifiable {
    enum Kind { case success, information, error }
    let id = UUID()
    let text: String
    var title: String? = nil
    var kind: Kind = .success
    var action: ToastAction? = nil
    var error: Bool { kind == .error }
    var readingDuration: Double { max(action == nil ? 6 : 8, min(12, Double(text.count) / 24)) }
    var announcement: String { [title, text].compactMap { $0 }.joined(separator: ". ") }
}

/// One centered macOS-style HUD for Settings and service sheets.
/// Its opaque neutral surface remains legible over both window appearances.
struct ToastView: View {
    let notice: ToastNotice
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var closeHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(accent).frame(height: 32)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                if let title = notice.title {
                    Text(title).font(.system(size: 13, weight: .semibold))
                }
                Text(notice.text)
                    .font(.system(size: 12, weight: notice.title == nil ? .medium : .regular))
                    .foregroundStyle(.white.opacity(notice.title == nil ? 1 : 0.88))
                    .lineLimit(5).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).help(notice.text)
                if let action = notice.action {
                    Button(action.title) { action.perform(); dismiss() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .environment(\.colorScheme, .dark).padding(.top, 4)
                        .accessibilityIdentifier("morrow.toast.action")
                }
            }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26).padding(.vertical, 18)
        .background(DS.Surface.feedback(colorScheme), in: RoundedRectangle(cornerRadius: DS.Radius.actionEdge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.actionEdge, style: .continuous)
            .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0.14), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(closeHovered ? 1 : 0.7))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(closeHovered ? 0.12 : 0), in: RoundedRectangle(cornerRadius: DS.Radius.action))
            }.buttonStyle(.plain).onHover { closeHovered = $0 }
                .help("Dismiss notification").accessibilityLabel("Dismiss notification")
                .accessibilityIdentifier("morrow.toast.dismiss")
                .padding(6)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.2), radius: 12, y: 5)
        .accessibilityElement(children: .contain).accessibilityIdentifier("morrow.toast")
        .accessibilityAction(.escape, dismiss)
    }
    private var symbol: String {
        switch notice.kind { case .success: return "checkmark.circle.fill"; case .information: return "info.circle.fill"; case .error: return "exclamationmark.circle.fill" }
    }
    private var accent: Color {
        switch notice.kind { case .success: return Color(red: 0.32, green: 0.85, blue: 0.69); case .information: return Color(red: 0.45, green: 0.76, blue: 1); case .error: return Color(red: 1, green: 0.68, blue: 0.34) }
    }
}

private struct ServiceFeedbackModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source = UUID()

    func body(content: Content) -> some View {
        content.overlay(alignment: .center) {
                if let notice = model.toast {
                    ToastView(notice: notice) { model.dismissToast(notice.id) }
                        .frame(width: 290).fixedSize(horizontal: false, vertical: true)
                        .onHover { model.setToastHovered($0, id: notice.id, source: source) }
                        .onDisappear { model.setToastHovered(false, id: notice.id, source: source) }
                        .id(notice.id)
                        .transition(reduceMotion ? .identity : .opacity)
                }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.toast?.id)
    }
}
extension View {
    func serviceFeedback() -> some View {
        modifier(ServiceFeedbackModifier())
    }
    func feedbackSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        sheet(item: item) { content($0).serviceFeedback() }
    }
    func feedbackSheet<Sheet: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet) -> some View {
        sheet(isPresented: isPresented) { content().serviceFeedback() }
    }
}
