import Foundation

/// A PHP requirement from the project's root Composer manifest.
public struct ComposerPHPRequirement: Sendable {
    public let constraints: [String]
    public let platformVersion: String?

    public var description: String {
        (constraints + (platformVersion.map { ["Platform " + $0] } ?? []))
            .map { String($0.prefix(160)) }.joined(separator: " · ")
    }

    public var canRecommend: Bool {
        constraints.allSatisfy { ComposerVersionConstraint($0) != nil }
            && (platformVersion.map { ComposerVersionConstraint.version($0) != nil } ?? true)
    }

    public func matches(_ version: String) -> Bool {
        guard let installed = SoftwareVersion(version), installed.components.count >= 2,
              let release = ComposerVersionConstraint.version(installed.components.map(String.init).joined(separator: ".")),
              constraints.allSatisfy({ ComposerVersionConstraint($0)?.matches(release) == true }) else { return false }
        // Composer's platform setting simulates a PHP version. Suggest a patch
        // in that series at or above the target, within the declared requirements.
        guard let platformVersion else { return true }
        guard let platform = ComposerVersionConstraint.version(platformVersion) else { return false }
        return release >= platform
            && release.components[0] == platform.components[0]
            && release.components[1] == (platform.components.dropFirst().first ?? 0)
    }

    public func recommendation(installed: [RuntimeInstallation], available: [RuntimeChannel]) -> ComposerPHPRecommendation? {
        if let item = installed.filter({
            $0.engine == .php && matches($0.version) && $0.phpFPM != nil
                && FileManager.default.isExecutableFile(atPath: $0.executable)
        }).max(by: { $0.version.localizedStandardCompare($1.version) == .orderedAscending }) {
            return ComposerPHPRecommendation(version: item.version, request: item.id, installed: true)
        }
        guard let channel = available.filter({ $0.engine == .php && matches($0.version) })
            .max(by: { $0.version.localizedStandardCompare($1.version) == .orderedAscending }) else { return nil }
        return ComposerPHPRecommendation(version: channel.version, request: "managed:php@" + channel.version, installed: false)
    }
}

public struct ComposerPHPRecommendation: Sendable {
    public let version: String
    public let request: String
    public let installed: Bool
}

/// Composer's numeric constraints evaluated against stable PHP releases.
/// Unknown syntax is displayed in the UI but never used to pick a runtime.
private struct ComposerVersionConstraint {
    private enum Operator: String { case equal = "=", notEqual = "!=", less = "<", atMost = "<=", greater = ">", atLeast = ">=" }
    private struct Comparison {
        let operation: Operator
        let bound: SoftwareVersion
        init(_ operation: Operator, _ bound: SoftwareVersion) { self.operation = operation; self.bound = bound }
        func matches(_ release: SoftwareVersion) -> Bool {
            switch operation {
            case .equal: return release == bound
            case .notEqual: return release != bound
            case .less: return release < bound
            case .atMost: return release <= bound
            case .greater: return release > bound
            case .atLeast: return release >= bound
            }
        }
    }
    private let alternatives: [[Comparison]]

    init?(_ constraint: String) {
        guard constraint.utf8.count <= 160 else { return nil }
        let groups = constraint.replacingOccurrences(of: "||", with: "|").components(separatedBy: "|")
        var alternatives: [[Comparison]] = []
        for group in groups {
            let terms = group
                .replacingOccurrences(of: "([<>=!~^]+)\\s+(?=[vV0-9])", with: "$1", options: .regularExpression)
                .split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
            guard !terms.isEmpty else { return nil }
            var comparisons: [Comparison] = []
            var index = 0
            while index < terms.count {
                if index + 2 < terms.count, terms[index + 1] == "-" {
                    guard let lower = Self.version(terms[index]), let upper = Self.version(terms[index + 2]) else { return nil }
                    comparisons.append(.init(.atLeast, lower))
                    if upper.components.count < 3 {
                        guard let next = Self.next(upper, at: upper.components.count - 1) else { return nil }
                        comparisons.append(.init(.less, next))
                    } else {
                        comparisons.append(.init(.atMost, upper))
                    }
                    index += 3
                } else {
                    guard let predicates = Self.parse(terms[index]) else { return nil }
                    comparisons += predicates
                    index += 1
                }
            }
            alternatives.append(comparisons)
        }
        self.alternatives = alternatives
    }

    func matches(_ release: SoftwareVersion) -> Bool {
        alternatives.contains { $0.allSatisfy { $0.matches(release) } }
    }

    static func version(_ value: String) -> SoftwareVersion? {
        let normalized = value.lowercased()
        guard normalized.range(of: "^v?[0-9]+(?:\\.[0-9]+){0,3}$", options: .regularExpression) != nil else { return nil }
        return SoftwareVersion(normalized.hasPrefix("v") ? String(normalized.dropFirst()) : normalized)
    }

    private static func next(_ version: SoftwareVersion, at index: Int) -> SoftwareVersion? {
        var parts = Array(version.components.prefix(index + 1))
        let (increment, overflow) = parts[index].addingReportingOverflow(1)
        guard !overflow else { return nil }
        parts[index] = increment
        return SoftwareVersion(parts.map(String.init).joined(separator: "."))
    }

    private static func parse(_ term: String) -> [Comparison]? {
        let symbol = String(term.prefix { "<>=!~^".contains($0) })
        let value = String(term.dropFirst(symbol.count))
        if symbol.isEmpty {
            let parts = value.lowercased().split(separator: ".", omittingEmptySubsequences: false)
            if let firstWildcard = parts.firstIndex(where: { $0 == "*" || $0 == "x" }) {
                guard parts.count <= 4, parts[firstWildcard...].allSatisfy({ $0 == "*" || $0 == "x" }) else { return nil }
                if firstWildcard == 0 { return [] }
                guard let lower = version(parts[..<firstWildcard].joined(separator: ".")),
                      let upper = next(lower, at: firstWildcard - 1) else { return nil }
                return [.init(.atLeast, lower), .init(.less, upper)]
            }
        }
        guard let bound = version(value) else { return nil }
        if symbol == "^" || symbol == "~" {
            let index = symbol == "^"
                ? bound.components.firstIndex(where: { $0 != 0 }) ?? bound.components.count - 1
                : max(0, bound.components.count - 2)
            guard let upper = next(bound, at: index) else { return nil }
            return [.init(.atLeast, bound), .init(.less, upper)]
        }
        let normalized = ["", "=="].contains(symbol) ? "=" : symbol == "<>" ? "!=" : symbol
        guard let operation = Operator(rawValue: normalized) else { return nil }
        return [.init(operation, bound)]
    }
}
