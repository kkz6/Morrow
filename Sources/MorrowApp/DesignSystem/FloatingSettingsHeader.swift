import SwiftUI
import AppKit
import QuartzCore

enum FloatingHeaderMetrics {
    static let height = SettingsLayout.detailTopInset + SettingsLayout.detailHeaderHeight + SettingsLayout.detailSectionSpacing
    static let fullStrengthEnd = SettingsLayout.detailTopInset + SettingsLayout.detailHeaderHeight / 2
    static let animationDuration = 0.18
    static func maskAlpha(at distanceFromTop: CGFloat) -> CGFloat {
        guard distanceFromTop > fullStrengthEnd else { return 1 }
        let progress = min(1, max(0, (distanceFromTop - fullStrengthEnd) / (height - fullStrengthEnd)))
        // Smoothstep keeps the fade's endpoints soft without an abrupt seam.
        return 1 - progress * progress * (3 - 2 * progress)
    }
}

struct FloatingSettingsHeader<Destination: SettingsDestination>: NSViewRepresentable {
    let section: Destination
    let scrolled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> HeaderAnchorView { HeaderAnchorView() }
    func updateNSView(_ anchor: HeaderAnchorView, context: Context) {
        anchor.overlay.title.heading = NSLocalizedString(section.textTitle, comment: "Settings title")
        anchor.overlay.title.symbol = section.symbol
        anchor.overlay.title.tint = NSColor(section.color)
        anchor.overlay.title.needsDisplay = true
        anchor.overlay.effect.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        anchor.overlay.effect.setVisible(scrolled, animated: !reduceMotion)
        anchor.syncFrame()
    }
}

/// Native sibling hosting keeps the blur above all SwiftUI scroll content and
/// its title above the blur, including text rendered in SwiftUI's backing layer.
final class HeaderAnchorView: NSView {
    let overlay = HeaderOverlayView()
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); syncFrame() }
    override func layout() { super.layout(); syncFrame() }
    func syncFrame() {
        guard let container = window?.contentView else { overlay.removeFromSuperview(); return }
        if overlay.superview !== container {
            overlay.removeFromSuperview()
            container.addSubview(overlay)
        }
        overlay.frame = convert(bounds, to: container)
        overlay.layoutSubtreeIfNeeded()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class HeaderOverlayView: NSView {
    let effect = HeaderEffectView()
    let title = HeaderTitleView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(effect)
        addSubview(title)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        effect.frame = bounds
        title.frame = bounds
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class HeaderTitleView: NSView {
    var heading = ""
    var symbol = "gearshape.fill"
    var tint = NSColor.gray
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: SettingsLayout.detailHorizontalInset, y: SettingsLayout.detailTopInset + 2, width: 22, height: 22)
        let tile = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSGradient(starting: tint, ending: tint.blended(withFraction: 0.1, of: .black) ?? tint)?.draw(in: tile, angle: -90)
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let titleSymbol = symbol == "info.circle.fill" ? "info.circle" : symbol
        NSImage(systemSymbolName: titleSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)?.draw(in: rect.insetBy(dx: 5, dy: 5))
        let text = NSAttributedString(string: heading, attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.labelColor])
        text.draw(at: NSPoint(x: rect.maxX + DS.Spacing.sm,
            y: SettingsLayout.detailTopInset + (SettingsLayout.detailHeaderHeight - text.size().height) / 2))
        setAccessibilityLabel(heading)
        setAccessibilityRole(.staticText)
    }
}

/// Native backdrop sampling and an alpha mask avoid the bright fringes caused
/// by blurring a SwiftUI background or masking a flattened material snapshot.
final class HeaderEffectView: NSVisualEffectView {
    private var shown = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .underWindowBackground
        blendingMode = .withinWindow
        state = .active
        isEmphasized = false
        alphaValue = 0
        maskImage = Self.makeMask()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func setVisible(_ visible: Bool, animated: Bool) {
        let target: CGFloat = visible ? 1 : 0
        if !animated {
            shown = visible
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                animator().alphaValue = target
            }
            return
        }
        guard visible != shown else { return }
        shown = visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FloatingHeaderMetrics.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = target
        }
    }
    private var maskWidth: CGFloat = 0
    override func layout() {
        super.layout()
        if bounds.width > 0 && bounds.width != maskWidth {
            maskWidth = bounds.width
            maskImage = Self.makeMask(width: bounds.width)
        }
    }
    static func makeMask(width: CGFloat = 1) -> NSImage {
        let pixelHeight = Int(FloatingHeaderMetrics.height * 2)
        let pixelWidth = max(2, Int(ceil(width * 2)))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: pixelWidth * 4, bitsPerPixel: 32)!
        let pixels = bitmap.bitmapData!
        for row in 0..<pixelHeight {
            let y = CGFloat(row) / CGFloat(pixelHeight - 1) * FloatingHeaderMetrics.height
            let alpha = UInt8((FloatingHeaderMetrics.maskAlpha(at: y) * 255).rounded())
            for column in 0..<pixelWidth {
                let index = row * pixelWidth * 4 + column * 4
                pixels[index] = 255; pixels[index + 1] = 255; pixels[index + 2] = 255; pixels[index + 3] = alpha
            }
        }
        let image = NSImage(size: NSSize(width: width, height: FloatingHeaderMetrics.height))
        image.addRepresentation(bitmap)
        image.resizingMode = .stretch
        return image
    }
}

/// Track the actual clip view rather than a cached SwiftUI geometry snapshot.
/// This also handles keyboard scrolling and programmatic scroll restoration.
struct SettingsScrollObserver: NSViewRepresentable {
    @Binding var scrolled: Bool
    func makeNSView(context: Context) -> ScrollTrackingView { ScrollTrackingView() }
    func updateNSView(_ view: ScrollTrackingView, context: Context) {
        view.changed = { scrolled = $0 }
        view.attach()
    }
}

final class ScrollTrackingView: NSView {
    var changed: ((Bool) -> Void)?
    private weak var clip: NSClipView?
    private var token: NSObjectProtocol?
    private var last: Bool?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); attach() }
    func attach() {
        guard let scroll = enclosingScrollView else { return }
        if clip !== scroll.contentView {
            if let token { NotificationCenter.default.removeObserver(token) }
            clip = scroll.contentView
            scroll.contentView.postsBoundsChangedNotifications = true
            token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main) { [weak self] _ in self?.report() }
            last = nil
        }
        report()
    }
    private func report() {
        guard let clip, let document = clip.documentView else { return }
        let distance = document.isFlipped ? clip.bounds.minY - document.bounds.minY : document.bounds.maxY - clip.bounds.maxY
        let value = distance > 0.5
        guard value != last else { return }
        last = value
        DispatchQueue.main.async { [weak self] in self?.changed?(value) }
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}
