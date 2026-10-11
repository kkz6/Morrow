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

/// One visible notification surface for Settings, service sheets, and the menu.
/// Its opaque neutral surface remains legible over both window appearances.
struct ToastView: View {
    let notice: ToastNotice
    var compact = false
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var closeHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 10 : 12) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 18 : 22, weight: .medium))
                .foregroundStyle(accent).frame(width: compact ? 22 : 26, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let title = notice.title {
                    Text(title).font(.system(size: compact ? 12 : 13, weight: .semibold))
                }
                Text(notice.text)
                    .font(.system(size: compact ? 11 : 13, weight: notice.title == nil ? .medium : .regular))
                    .foregroundStyle(.white.opacity(notice.title == nil ? 1 : 0.88))
                    .lineLimit(compact ? 3 : 5).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).help(notice.text)
                if let action = notice.action {
                    Button(action.title) { action.perform(); dismiss() }
                        .buttonStyle(ToastActionStyle()).padding(.top, 4)
                        .accessibilityIdentifier("morrow.toast.action")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(closeHovered ? 1 : 0.7))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(closeHovered ? 0.12 : 0), in: RoundedRectangle(cornerRadius: DS.Radius.action))
            }.buttonStyle(.plain).onHover { closeHovered = $0 }
                .help("Dismiss notification").accessibilityLabel("Dismiss notification")
                .accessibilityIdentifier("morrow.toast.dismiss")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 12 : 14).padding(.vertical, compact ? 10 : 12)
        .background(DS.Surface.feedback(colorScheme), in: RoundedRectangle(cornerRadius: DS.Radius.actionEdge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.actionEdge, style: .continuous)
            .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0.14), lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.2), radius: compact ? 8 : 14, y: 5)
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

private struct ToastActionStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 26)
            .background(.white.opacity(configuration.isPressed ? 0.22 : hovered ? 0.16 : 0.1), in: RoundedRectangle(cornerRadius: DS.Radius.action))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.action).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .onHover { hovered = $0 }
    }
}

enum FeedbackPlacement { case settings, sheet }
private struct ServiceFeedbackModifier: ViewModifier {
    var compact = false
    var placement: FeedbackPlacement = .sheet
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source = UUID()

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geometry in
                if let notice = model.toast {
                    let inset: CGFloat = compact ? 10 : 16
                    let available = geometry.size.width - inset * 2 - (placement == .settings ? SettingsLayout.sidebarWidth : 0)
                    ToastView(notice: notice, compact: compact) { model.dismissToast(notice.id) }
                        .frame(width: max(0, min(compact ? 280 : 360, available)))
                        .onHover { model.setToastHovered($0, id: notice.id, source: source) }
                        .onDisappear { model.setToastHovered(false, id: notice.id, source: source) }
                        .id(notice.id)
                        .padding(.horizontal, inset)
                        .padding(.top, compact ? 0 : placement == .settings ? FloatingHeaderMetrics.height + 8 : 56)
                        .padding(.bottom, compact ? MenuLayout.footerHeight + 6 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottomTrailing : .topTrailing)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: compact ? 6 : -6)))
                }
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.toast?.id)
    }
}
extension View {
    func serviceFeedback(compact: Bool = false, placement: FeedbackPlacement = .sheet) -> some View {
        modifier(ServiceFeedbackModifier(compact: compact, placement: placement))
    }
    func feedbackSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        sheet(item: item) { content($0).serviceFeedback() }
    }
    func feedbackSheet<Sheet: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet) -> some View {
        sheet(isPresented: isPresented) { content().serviceFeedback() }
    }
}
