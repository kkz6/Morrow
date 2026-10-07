import Foundation

struct BrewPackage: Sendable {
    let name: String
    let version: String
    let revision: Int
    let cask: Bool
    var packageVersion: String { revision > 0 ? "\(version)_\(revision)" : version }
}

extension HomebrewInstaller {
    func package(_ name: String, cask: Bool = false) throws -> BrewPackage {
        let output = try runner.run(requireExecutable(), ["info", "--json=v2", cask ? "--cask" : "--formula", name], environment: [:]).checked()
        guard let data = output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = (json[cask ? "casks" : "formulae"] as? [[String: Any]])?.first,
              item["disabled"] as? Bool != true,
              let canonical = item[cask ? "token" : "name"] as? String,
              let version = cask ? item["version"] as? String : (item["versions"] as? [String: Any])?["stable"] as? String else {
            throw MorrowError.message("Homebrew cannot install that release channel.")
        }
        let fullName = item["full_name"] as? String ?? canonical
        return BrewPackage(name: cask ? canonical : fullName, version: version,
                           revision: item["revision"] as? Int ?? 0, cask: cask)
    }
    public func refreshMetadata() throws {
        try runner.run(requireExecutable(), ["update"], environment: [:]).checked()
    }
    func upgradePackage(_ package: BrewPackage) throws {
        // Keep old kegs available to pinned instances. Other Homebrew
        // dependencies can still change; Morrow never claims isolated upgrades.
        let arguments = package.cask ? ["upgrade", "--cask", "--greedy", package.name] : ["upgrade", "--formula", package.name]
        try runner.run(requireExecutable(), arguments, environment: [:]).checked()
    }
}
