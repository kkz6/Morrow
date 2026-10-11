import SwiftUI

struct ToastAction {
    let title: String
    let perform: () -> Void
}

struct FeedbackContext {
    var section: SettingsSection
    var sheet: UUID? = nil
}

struct ToastNotice: Identifiable {
    enum Kind { case success, information, error }
    let id = UUID()
    let text: String
    var title: String? = nil
    var kind: Kind = .success
    var action: ToastAction? = nil
    var section: SettingsSection = .general
    var sheet: UUID? = nil
    var error: Bool { kind == .error }
    var readingDuration: Double { max(action == nil ? 6 : 8, min(12, Double(text.count) / 24)) }
    var announcement: String { [title, text].compactMap { $0 }.joined(separator: ". ") }
}

/// Feedback is a normal settings card in the page's content flow.
/// It shares the approved surfaces, gutters, and actions in both appearances.
struct SettingsFeedbackCard: View {
    let text: String
    var title: String? = nil
    var kind: ToastNotice.Kind = .information
    var action: ToastAction? = nil
    var dismiss: (() -> Void)? = nil

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(accent).frame(width: 20, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    if let title { Text(title).font(.system(size: 12, weight: .medium)) }
                    Text(text).font(.system(size: 12))
                        .foregroundStyle(title == nil ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let action {
                    Button(action.title, action: action.perform)
                        .settingsButton(height: 28)
                        .accessibilityIdentifier("morrow.feedback.action")
                }
                if let dismiss {
                    Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(MenuIconButtonStyle())
                        .help("Dismiss message").accessibilityLabel("Dismiss message")
                        .accessibilityIdentifier("morrow.feedback.dismiss")
                }
            }.settingsCellPadding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("morrow.feedback")
    }
    private var symbol: String {
        switch kind { case .success: return "checkmark.circle"; case .information: return "info.circle"; case .error: return "exclamationmark.circle" }
    }
    private var accent: Color {
        switch kind { case .success: return .accentColor; case .information: return .secondary; case .error: return .orange }
    }
}

private struct NoticeCard: View {
    let notice: ToastNotice
    @Environment(AppModel.self) private var model
    @State private var source = UUID()

    var body: some View {
        SettingsFeedbackCard(text: notice.text, title: notice.title, kind: notice.kind,
            action: notice.action.map { action in
                ToastAction(title: action.title) { action.perform(); model.dismissToast(notice.id) }
            }, dismiss: { model.dismissToast(notice.id) })
            .onHover { model.setToastHovered($0, id: notice.id, source: source) }
            .onAppear { model.setToastVisible(true, id: notice.id, source: source) }
            .onDisappear { model.setToastVisible(false, id: notice.id, source: source) }
            .accessibilityAction(.escape) { model.dismissToast(notice.id) }
    }
}

/// Pages own their feedback. Setup reminders follow native permission status
/// and stay on the two pages that can resolve them.
struct SettingsPageFeedback: View {
    let section: SettingsSection
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let notice = model.toast, notice.sheet == nil, notice.section == section.feedbackSection {
                NoticeCard(notice: notice).id(notice.id)
            } else if (section == .general || section == .sites), model.setupNeedsAttention {
                SettingsFeedbackCard(
                    text: model.setupApprovalRequired
                        ? "Allow Morrow's setup helper in Login Items to configure local domains."
                        : "Morrow's local setup helper is not enabled. Retry setup to restore it.",
                    title: model.setupApprovalRequired ? "Setup approval needed" : "Local setup needs attention",
                    action: ToastAction(title: model.setupApprovalRequired ? "Review Permissions…" : "Retry Setup") {
                        if model.setupApprovalRequired { NativeSetupController.openApprovalSettings() }
                        else { model.refreshSetupHelper() }
                    }).disabled(model.setupHelperRefreshing)
            }
        }
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.toast?.id)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.setupNeedsAttention)
    }
}

private struct ServiceFeedbackModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source = UUID()
    @State private var contentWidth: CGFloat = 0

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if let notice = model.toast, notice.sheet == source {
                NoticeCard(notice: notice)
                    .padding(.horizontal, 20).padding(.top, 16)
                    .frame(width: contentWidth > 0 ? contentWidth : nil)
                    .id(notice.id).transition(.opacity)
            }
            content.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .onAppear { model.beginFeedbackSheet(source) }
        .onDisappear { model.endFeedbackSheet(source) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.toast?.id)
    }
}
extension View {
    func serviceFeedback() -> some View { modifier(ServiceFeedbackModifier()) }
    func feedbackSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        sheet(item: item) { content($0).serviceFeedback() }
    }
    func feedbackSheet<Sheet: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet) -> some View {
        sheet(isPresented: isPresented) { content().serviceFeedback() }
    }
}
