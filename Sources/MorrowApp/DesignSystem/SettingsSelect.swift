import SwiftUI
import AppKit

struct SelectOption<Value: Hashable>: Identifiable, Equatable {
    let value: Value
    let title: String
    let symbol: String
    var id: Value { value }
}

/// Shared compact selector: selected icon and label with an outlined capsule
/// containing neutral up/down chevrons. The popup retains native menu behavior.
struct SettingsSelect<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    var placeholder = "Choose…"
    var placeholderSymbol = "square.stack.3d.up"
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        NativeSettingsSelect(label: label, selection: $selection, options: options,
                             placeholder: placeholder, placeholderSymbol: placeholderSymbol,
                             enabled: isEnabled)
            .frame(height: ControlLayout.height)
    }
}

private struct NativeSettingsSelect<Value: Hashable>: NSViewRepresentable {
    let label: String
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    let placeholder: String
    let placeholderSymbol: String
    let enabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> SelectPopUpButton {
        let button = SelectPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.font = .systemFont(ofSize: 13)
        button.focusRingType = .default
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        return button
    }
    func updateNSView(_ button: SelectPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let selected = options.firstIndex { $0.value == selection }
        if context.coordinator.options != options || button.numberOfItems == 0 {
            context.coordinator.options = options
            button.removeAllItems()
            for (index, option) in options.enumerated() {
                button.addItem(withTitle: option.title)
                button.lastItem?.tag = index
                button.lastItem?.image = NSImage(systemSymbolName: option.symbol, accessibilityDescription: nil)
                button.lastItem?.image?.size = NSSize(width: 16, height: 16)
            }
        }
        if let selected { button.selectItem(at: selected) }
        else {
            if button.lastItem?.tag != -1 { button.addItem(withTitle: placeholder); button.lastItem?.tag = -1; button.lastItem?.isEnabled = false }
            button.selectItem(at: button.numberOfItems - 1)
        }
        button.selectedSymbol = selected.map { options[$0].symbol } ?? placeholderSymbol
        button.isEnabled = enabled && !options.isEmpty
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(selected.map { options[$0].title } ?? placeholder)
        button.invalidateIntrinsicContentSize()
        button.needsDisplay = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectPopUpButton, context: Context) -> CGSize? {
        CGSize(width: min(proposal.width ?? nsView.intrinsicContentSize.width, nsView.intrinsicContentSize.width), height: ControlLayout.height)
    }
    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Value>
        var options: [SelectOption<Value>] = []
        init(selection: Binding<Value>) { self.selection = selection }
        @objc func changed(_ sender: NSPopUpButton) {
            guard let index = sender.selectedItem?.tag, options.indices.contains(index) else { return }
            selection.wrappedValue = options[index].value
        }
    }
}

/// Draw the closed control to match the reference. NSPopUpButton supplies the
/// actual popup, selection checks, keyboard handling, and accessibility role.
private final class SelectPopUpButton: NSPopUpButton {
    var selectedSymbol = "square.stack.3d.up"
    override var intrinsicContentSize: NSSize {
        let width = ((selectedItem?.title ?? "") as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        return NSSize(width: ceil(width) + 55, height: ControlLayout.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        let textColor: NSColor = isEnabled ? .labelColor : .disabledControlTextColor
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        drawSymbol(selectedSymbol, rect: NSRect(x: 3, y: bounds.midY - 8, width: 17, height: 16), color: textColor, size: 14)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let title = NSAttributedString(string: selectedItem?.title ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: textColor, .paragraphStyle: paragraph,
        ])
        title.draw(in: NSRect(x: 28, y: bounds.midY - 8, width: max(0, bounds.width - 55), height: 17))
        let capsuleRect = NSRect(x: bounds.maxX - 19, y: bounds.midY - 11, width: 16, height: 22)
        let capsule = NSBezierPath(roundedRect: capsuleRect, xRadius: 8, yRadius: 8)
        NSColor.labelColor.withAlphaComponent(0.025).setFill()
        capsule.fill()
        NSColor.separatorColor.setStroke()
        capsule.lineWidth = 0.75
        capsule.stroke()
        drawSymbol("chevron.up.chevron.down", rect: capsuleRect.insetBy(dx: 4, dy: 5),
                   color: isEnabled ? .secondaryLabelColor : .disabledControlTextColor, size: 9)
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    private func drawSymbol(_ symbol: String, rect: NSRect, color: NSColor, size: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)?.draw(in: rect)
    }
}
