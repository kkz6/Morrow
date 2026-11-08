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

/// The title remains SwiftUI content above a native, masked backdrop. Keeping
/// both inside the pane gives them the same lifetime as its scroll view.
struct FloatingSettingsHeader<Destination: SettingsDestination>: View {
    let section: Destination
    let scrolled: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            IconTile(symbol: section.symbol, color: section.color, size: 22)
            Text(section.title)
                .font(.system(size: 18, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .frame(height: SettingsLayout.detailHeaderHeight)
        .padding(.horizontal, SettingsLayout.detailHorizontalInset)
        .padding(.top, SettingsLayout.detailTopInset)
        .padding(.bottom, SettingsLayout.detailSectionSpacing)
        .background(SettingsHeaderBackdrop(scrolled: scrolled))
        .allowsHitTesting(false)
    }
}

private struct SettingsHeaderBackdrop: NSViewRepresentable {
    let scrolled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> HeaderEffectView { HeaderEffectView() }
    func updateNSView(_ effect: HeaderEffectView, context: Context) {
        effect.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        effect.setVisible(scrolled, animated: !reduceMotion)
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
