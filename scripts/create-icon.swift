import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let inset = CGFloat(pixels) * 0.08
        let rect = NSRect(x: inset, y: inset, width: CGFloat(pixels) - 2 * inset, height: CGFloat(pixels) - 2 * inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: CGFloat(pixels) * 0.20, yRadius: CGFloat(pixels) * 0.20)
        NSGradient(starting: NSColor(red: 0.22, green: 0.63, blue: 0.55, alpha: 1), ending: NSColor(red: 0.08, green: 0.28, blue: 0.26, alpha: 1))!.draw(in: path, angle: -90)
        if let symbol = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil) {
            let symbolRect = NSRect(x: CGFloat(pixels) * 0.23, y: CGFloat(pixels) * 0.29, width: CGFloat(pixels) * 0.54, height: CGFloat(pixels) * 0.42)
            let config = NSImage.SymbolConfiguration(pointSize: CGFloat(pixels) * 0.40, weight: .medium).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            symbol.withSymbolConfiguration(config)?.draw(in: symbolRect)
        }
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try representation.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
