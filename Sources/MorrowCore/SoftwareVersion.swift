import Foundation

/// Numeric releases and packaging revisions are compared independently.
public struct SoftwareVersion: Comparable, Sendable {
    public let components: [Int]
    public let revision: Int
    public init?(_ value: String) {
        let parts = value.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard !numbers.isEmpty, numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              numbers.allSatisfy({ Int($0) != nil }) else { return nil }
        components = numbers.map { Int($0)! }
        if parts.count == 2 {
            guard let number = Int(parts[1]), number >= 0 else { return nil }; revision = number
        } else { revision = 0 }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let a = index < lhs.components.count ? lhs.components[index] : 0
            let b = index < rhs.components.count ? rhs.components[index] : 0
            if a != b { return a < b }
        }
        return lhs.revision < rhs.revision
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
    public func isMaintenanceRelease(of old: Self, engine: DatabaseEngine) -> Bool {
        let count = engine == .postgresql && (old.components.first ?? 0) >= 10 ? 1 : 2
        return components.count >= count && old.components.count >= count
            && Array(components.prefix(count)) == Array(old.components.prefix(count))
    }
}

public struct DatabaseUpdate: Codable, Identifiable, Sendable {
    public var id: UUID { instanceID }
    public let instanceID: UUID
    public let name: String
    public let currentVersion: String
    public let availableVersion: String?
    public let formula: String?
    public let canUpgrade: Bool
    public let message: String
    public init(instanceID: UUID, name: String, currentVersion: String, availableVersion: String?, formula: String?, canUpgrade: Bool, message: String) {
        self.instanceID = instanceID; self.name = name; self.currentVersion = currentVersion
        self.availableVersion = availableVersion; self.formula = formula; self.canUpgrade = canUpgrade; self.message = message
    }
}
