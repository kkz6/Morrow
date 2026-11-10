import SwiftUI
import AppKit

enum FloatingHeaderMetrics {
    static let height = SettingsLayout.detailTopInset + SettingsLayout.detailHeaderHeight + SettingsLayout.detailSectionSpacing
    static let fullStrengthEnd = SettingsLayout.detailTopInset + SettingsLayout.detailHeaderHeight / 2
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
    var toolbar: AnyView? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let toolbar { SettingsToolbar { toolbar } }
        }
        .frame(height: SettingsLayout.detailHeaderHeight)
        .padding(.horizontal, SettingsLayout.detailHorizontalInset)
        .padding(.top, SettingsLayout.detailTopInset)
        .padding(.bottom, SettingsLayout.detailSectionSpacing)
        .background(SettingsEdgeBackdrop(edge: .top).allowsHitTesting(false))
    }
}

/// These backdrops remain mounted at full opacity. Scrolling changes the sampled
/// content, never the visibility of the effect, so returning to an edge cannot
/// leave a delayed shadow behind. No motion is introduced with Reduce Motion.
enum SettingsScrollEdge {
    case top, bottom

    var height: CGFloat {
        self == .top ? FloatingHeaderMetrics.height : SettingsLayout.detailBottomInset
    }

    func maskAlpha(at distanceFromTop: CGFloat) -> CGFloat {
        if self == .top { return FloatingHeaderMetrics.maskAlpha(at: distanceFromTop) }
        let progress = min(1, max(0, distanceFromTop / height))
        return progress * progress * (3 - 2 * progress)
    }
}

struct SettingsEdgeBackdrop: NSViewRepresentable {
    let edge: SettingsScrollEdge
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> SettingsEdgeEffectView { SettingsEdgeEffectView(edge: edge) }
    func updateNSView(_ effect: SettingsEdgeEffectView, context: Context) {
        effect.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}

/// Native backdrop sampling and an alpha mask avoid bright fringes, solid
/// blocks, and hard borders. Only the background is blurred, never the title.
final class SettingsEdgeEffectView: NSVisualEffectView {
    let edge: SettingsScrollEdge

    init(edge: SettingsScrollEdge) {
        self.edge = edge
        super.init(frame: .zero)
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        isEmphasized = false
        maskImage = Self.makeMask(edge: edge)
    }
    required init?(coder: NSCoder) { nil }

    private var maskWidth: CGFloat = 0
    override func layout() {
        super.layout()
        if bounds.width > 0 && bounds.width != maskWidth {
            maskWidth = bounds.width
            maskImage = Self.makeMask(edge: edge, width: bounds.width)
        }
    }
    static func makeMask(edge: SettingsScrollEdge, width: CGFloat = 1) -> NSImage {
        let pixelHeight = Int(edge.height * 2)
        let pixelWidth = max(2, Int(ceil(width * 2)))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: pixelWidth * 4, bitsPerPixel: 32)!
        let pixels = bitmap.bitmapData!
        for row in 0..<pixelHeight {
            let y = CGFloat(row) / CGFloat(pixelHeight - 1) * edge.height
            let alpha = UInt8((edge.maskAlpha(at: y) * 255).rounded())
            for column in 0..<pixelWidth {
                let index = row * pixelWidth * 4 + column * 4
                pixels[index] = 255; pixels[index + 1] = 255; pixels[index + 2] = 255; pixels[index + 3] = alpha
            }
        }
        let image = NSImage(size: NSSize(width: width, height: edge.height))
        image.addRepresentation(bitmap)
        image.resizingMode = .stretch
        return image
    }
}
