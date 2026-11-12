import Foundation

public struct RustProjectRequirement: Equatable, Sendable {
    public let channel: String?
    public let minimum: String?
    public let source: String
    public let needsCustomToolchain: Bool

    public var description: String {
        [channel ?? (needsCustomToolchain ? "Custom toolchain" : nil), minimum.map { "Minimum " + $0 }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    public static func read(at path: String) throws -> Self? {
        let files = ProjectFiles(path: path)
        let legacy = try files.text("rust-toolchain", limit: 16_384)
        let modern = try legacy == nil ? files.text("rust-toolchain.toml", limit: 16_384) : nil
        let toolchain = legacy ?? modern
        let cargo = try files.text("Cargo.toml", limit: 1_048_576)
        let minimum = cargo.flatMap { quoted("rust-version", in: $0, sections: ["package", "workspace.package"]) }
        let channel: String?
        if let legacy, !legacy.contains("[") {
            let value = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
            channel = value.isEmpty ? nil : String(value.prefix(160))
        } else {
            channel = toolchain.flatMap { quoted("channel", in: $0, sections: ["toolchain"]) }
        }
        let custom = toolchain.map { text in
            channel == nil || hasCustomSettings(text)
        } ?? false
        guard channel != nil || minimum != nil || custom else { return nil }
        return Self(channel: channel, minimum: minimum, source: legacy != nil ? "rust-toolchain" : modern != nil ? "rust-toolchain.toml" : "Cargo.toml", needsCustomToolchain: custom)
    }

    public func matches(_ version: String) -> Bool {
        guard !needsCustomToolchain, let release = SoftwareVersion(version) else { return false }
        if let minimum {
            guard let floor = SoftwareVersion(minimum), release >= floor else { return false }
        }
        guard let channel else { return true }
        let target = "-aarch64-apple-darwin"
        let pin = channel.hasSuffix(target) ? String(channel.dropLast(target.count)) : channel
        if pin == "stable" { return true }
        guard let pinned = SoftwareVersion(pin), (2...3).contains(pinned.components.count) else { return false }
        return release.components.prefix(pinned.components.count).elementsEqual(pinned.components)
    }

    public var canRecommend: Bool {
        guard !needsCustomToolchain else { return false }
        guard let channel else { return minimum.flatMap(SoftwareVersion.init) != nil }
        let pin = channel.replacingOccurrences(of: "-aarch64-apple-darwin$", with: "", options: .regularExpression)
        return pin == "stable" || SoftwareVersion(pin).map { (2...3).contains($0.components.count) } == true
    }

    private static func entries(in text: String, sections: Set<String>) -> [Substring] {
        var section = ""
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.drop(while: \.isWhitespace)
            if trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") {
                section = trimmed.dropFirst().prefix(upTo: end).trimmingCharacters(in: .whitespaces)
                return nil
            }
            return sections.contains(section) ? trimmed : nil
        }
    }

    private static func quoted(_ key: String, in text: String, sections: Set<String>) -> String? {
        let pattern = "^" + key + "\\s*=\\s*(['\"])([A-Za-z0-9._-]{1,160})\\1\\s*(?:#.*)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for entry in entries(in: text, sections: sections) {
            let line = String(entry)
            if let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let value = Range(match.range(at: 2), in: line) { return String(line[value]) }
        }
        return nil
    }

    private static func hasCustomSettings(_ text: String) -> Bool {
        entries(in: text, sections: ["toolchain"]).contains { entry in
            let pieces = entry.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { return false }
            let key = pieces[0].trimmingCharacters(in: .whitespaces)
            if key == "path" { return true }
            if key == "profile" {
                return pieces[1].range(of: "^\\s*(['\"])(minimal|default)\\1\\s*(?:#.*)?$", options: .regularExpression) == nil
            }
            if key == "components" || key == "targets" {
                return pieces[1].range(of: "^\\s*\\[\\s*\\]\\s*(?:#.*)?$", options: .regularExpression) == nil
            }
            return false
        }
    }
}
