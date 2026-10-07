import AppKit

/// One icon resolver for SwiftUI tiles and native popup controls.
@MainActor enum BrandIcons {
    private static var images: [String: NSImage] = [:]
    static func image(for symbol: String) -> NSImage? {
        guard ["morrow.redis", "morrow.valkey"].contains(symbol) else { return nil }
        if let cached = images[symbol] { return cached }
        let name = String(symbol.dropFirst("morrow.".count))
        guard let url = Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Assets"), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false; images[symbol] = image
        return image
    }
    static func fit(_ size: NSSize, in rect: NSRect) -> NSRect {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
    static func menuImage(for symbol: String) -> NSImage? {
        guard let image = image(for: symbol) else { return nil }
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            image.draw(in: fit(image.size, in: rect), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
    static func fallbackSymbol(_ symbol: String) -> String {
        switch symbol { case "morrow.redis": return "square.stack.3d.up.fill"; case "morrow.valkey": return "hexagon.fill"; default: return symbol }
    }
}
