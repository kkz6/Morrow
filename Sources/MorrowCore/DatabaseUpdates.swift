import Foundation

private struct UpgradeJournal: Codable {
    let original: DatabaseInstance
    let wasRunning: Bool
    let backup: String
    var phase: String
}

extension DatabaseManager {
    func upgradeJournal(_ id: UUID) -> URL { store.root.appendingPathComponent("updates/\(id.uuidString.lowercased()).json") }
    func requireRecovered(_ id: UUID) throws {
        guard !FileManager.default.fileExists(atPath: upgradeJournal(id).path) else {
            throw MorrowError.message("An interrupted update needs recovery. Run morrow db recover with this instance name.")
        }
    }
    public func needsUpdateRecovery(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: upgradeJournal(id).path) }
    public func databaseUpdates(refresh: Bool = false) throws -> [DatabaseUpdate] {
        let installer = try installer()
        if refresh { try installer.refreshMetadata() }
        var packages: [String: Result<BrewPackage, Error>] = [:]
        return try store.load().instances.map { instance in
            let current = instance.installation.packageVersion
            func row(_ available: String? = nil, formula: String? = nil, allowed: Bool = false, _ message: String) -> DatabaseUpdate {
                DatabaseUpdate(instanceID: instance.id, name: instance.name, currentVersion: current,
                               availableVersion: available, formula: formula, canUpgrade: allowed, message: message)
            }
            func row(_ message: String) -> DatabaseUpdate { row(nil, message) }
            if needsUpdateRecovery(instance.id) { return row("Interrupted update — recover before continuing.") }
            let formula = instance.installation.formula
            do {
                let releases = try installer.managed.releases(package: instance.engine.rawValue)
                if let old = SoftwareVersion(current), let release = releases.first,
                   let next = SoftwareVersion(release.version) {
                    if next > old {
                        let compatible = next.isMaintenanceRelease(of: old, engine: instance.engine)
                        let candidate = releases.first { SoftwareVersion($0.version).map { $0 > old && $0.isMaintenanceRelease(of: old, engine: instance.engine) } == true }
                        if let candidate { return row(candidate.version, formula: candidate.channel, allowed: true, "Maintenance update available") }
                        return row(release.version, formula: release.channel, allowed: compatible, "New release series — create an instance and migrate your data.")
                    }
                    if formula.hasPrefix("managed:") { return row(release.version, formula: release.channel, "Up to date") }
                } else if formula.hasPrefix("managed:") { return row("This managed release is not currently in the catalog.") }
            } catch { return row("Catalog check failed: \(error.localizedDescription)") }
            guard HomebrewInstaller.isAllowedFormula(formula, engine: instance.engine) else {
                return row("External installation — update through its original installer.")
            }
            guard installer.allowsHomebrew else { return row("Existing installation preserved; Homebrew compatibility is off") }
            if packages[formula] == nil { packages[formula] = Result { try installer.package(formula) } }
            do {
                let package = try packages[formula]!.get()
                guard let old = SoftwareVersion(current), let next = SoftwareVersion(package.packageVersion) else {
                    return row("The release version could not be compared.")
                }
                guard next > old else { return row(package.packageVersion, formula: package.name, "Up to date") }
                let compatible = next.isMaintenanceRelease(of: old, engine: instance.engine)
                return row(package.packageVersion, formula: package.name, allowed: compatible,
                           compatible ? (next.components == old.components ? "Package rebuild available" : "Maintenance update available") : "New release series — create an instance and migrate your data.")
            } catch { return row("Update check failed: \(error.localizedDescription)") }
        }
    }
    /// Upgrades one owned instance. Data is copied while the server is stopped.
    /// A durable journal prevents normal startup after an interrupted operation.
    @discardableResult public func upgrade(_ id: UUID, expectedVersion: String? = nil) throws -> DatabaseInstance {
        try store.operation {
            try requireRecovered(id)
            let original = try current(id)
            let update = try databaseUpdates().first { $0.instanceID == id }
            guard let update, update.canUpgrade, let available = update.availableVersion, let formula = update.formula else {
                throw MorrowError.message(update?.message ?? "No compatible update is available.")
            }
            if let expectedVersion, expectedVersion != available { throw MorrowError.message("The available release changed. Check updates again before upgrading.") }
            let binaryInstaller = try installer()
            let release = formula.hasPrefix("managed:") ? try binaryInstaller.managed.release(package: original.engine.rawValue, request: formula) : nil
            let package = formula.hasPrefix("managed:") ? nil : try binaryInstaller.package(formula)
            guard (release?.version ?? package?.packageVersion) == available else { throw MorrowError.message("Release metadata changed. Check updates again.") }
            // A local copy cannot cover external tablespaces or linked data.
            try validateBackupSource(original)
            let active = [.running, .starting].contains(status(original))
            let backup = store.root.appendingPathComponent("backups/\(id.uuidString.lowercased())/\(UUID().uuidString.lowercased())")
            var journal = UpgradeJournal(original: original, wasRunning: active, backup: backup.path, phase: "prepared")
            try saveJournal(journal)
            do {
                // Disable login startup before changing data or its executable.
                var paused = original; paused.autoStart = false
                try syncLoginJob(paused)
                try unload(original)
                guard Self.portAvailable(original.port) else { throw MorrowError.message("The database port is still occupied. Update cancelled.") }
                try validateBackupSource(original)
                try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.copyItem(at: store.instanceDirectory(original), to: backup)
                journal.phase = "backedUp"; try saveJournal(journal)
                let installed: Installation
                if let release {
                    let managed = try binaryInstaller.managed.install(release)
                    installed = Installation(engine: original.engine, formula: release.channel, version: release.version, prefix: managed.prefix)
                } else {
                    guard let package else { throw MorrowError.message("Release unavailable.") }
                    try binaryInstaller.upgradePackage(package)
                    guard let found = try binaryInstaller.installations().first(where: {
                        $0.engine == original.engine && BinaryInstaller.matches($0, request: formula) && $0.version == available
                    }) else { throw MorrowError.message("The requested release was not found after installation.") }
                    installed = found
                }
                let validated = try NativeInstallationDetector(runner: runner).validate(installed)
                guard validated.version == available else { throw MorrowError.message("The upgraded binary reports an unexpected version.") }
                var upgraded = original; upgraded.installation = validated
                try NativeProvider(store: store, runner: runner).writeConfiguration(upgraded)
                try writeJob(upgraded)
                // Keep login disabled until the operation is verified.
                try store.update { state in
                    guard let index = state.instances.firstIndex(where: { $0.id == id }) else { throw MorrowError.message("This instance was removed.") }
                    state.instances[index] = upgraded
                }
                journal.phase = "switched"; try saveJournal(journal)
                if active {
                    try startUnlocked(id, syncLogin: false)
                    for _ in 0..<270 {
                        let state = status(upgraded)
                        if state == .running { break }
                        if state == .failed || state == .stopped { break }
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    guard status(upgraded) == .running else { throw MorrowError.message("The updated server did not become ready.\n\(try logs(upgraded))") }
                }
                journal.phase = "completed"; try saveJournal(journal)
                try syncLoginJob(upgraded)
                try FileManager.default.removeItem(at: upgradeJournal(id))
                return upgraded
            } catch {
                let reason = error.localizedDescription
                if journal.phase == "completed" {
                    throw MorrowError.message("The update was applied, but finalizing it failed: \(reason)\nRun morrow db recover \(original.name) to finish. Backup: \(backup.path)")
                }
                do { try recoverUnlocked(id) }
                catch {
                    throw MorrowError.message("Update failed: \(reason)\nRecovery needs attention: \(error.localizedDescription)\nRun morrow db recover \(original.name). Backup: \(backup.path)")
                }
                throw MorrowError.message("Update failed: \(reason)\nThe previous instance was restored. Backup: \(backup.path)")
            }
        }
    }
    public func recoverUpdate(_ id: UUID) throws { try store.operation { try recoverUnlocked(id) } }
    private func saveJournal(_ journal: UpgradeJournal) throws {
        let url = upgradeJournal(journal.original.id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func recoverUnlocked(_ id: UUID) throws {
        let url = upgradeJournal(id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw MorrowError.message("No interrupted update exists for this instance.") }
        var journal = try JSONDecoder().decode(UpgradeJournal.self, from: Data(contentsOf: url))
        guard journal.original.id == id, ["prepared", "backedUp", "switched", "restoring", "completed"].contains(journal.phase) else {
            throw MorrowError.message("The update journal is invalid. Files have been preserved.")
        }
        if journal.phase == "completed" {
            let selected = try current(id)
            try writeJob(selected)
            if journal.wasRunning && ![.running, .starting].contains(status(selected)) { try startUnlocked(id, syncLogin: false) }
            try syncLoginJob(selected)
            try FileManager.default.removeItem(at: url)
            return
        }
        let original = journal.original
        let backup = URL(fileURLWithPath: journal.backup)
        guard backup.standardizedFileURL.path.hasPrefix(store.root.appendingPathComponent("backups").standardizedFileURL.path + "/") else { throw MorrowError.message("Invalid update backup path.") }
        try unload(original)
        if journal.phase == "backedUp" || journal.phase == "switched" || journal.phase == "restoring" {
            let directory = store.instanceDirectory(original)
            guard FileManager.default.fileExists(atPath: backup.path) else { throw MorrowError.message("The update backup is missing. Files have been preserved.") }
            journal.phase = "restoring"; try saveJournal(journal)
            if FileManager.default.fileExists(atPath: directory.path) {
                let preserved = backup.deletingLastPathComponent().appendingPathComponent("failed-\(UUID().uuidString.lowercased())")
                try FileManager.default.moveItem(at: directory, to: preserved)
            }
            try FileManager.default.copyItem(at: backup, to: directory)
        }
        try NativeProvider(store: store, runner: runner).writeConfiguration(original)
        try writeJob(original)
        try store.update { state in
            guard let index = state.instances.firstIndex(where: { $0.id == id }) else { throw MorrowError.message("The original instance is missing from state.") }
            state.instances[index] = original
        }
        if journal.wasRunning {
            try startUnlocked(id, syncLogin: false)
            for _ in 0..<270 {
                let current = status(original)
                if current == .running || current == .failed || current == .stopped { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard status(original) == .running else { throw MorrowError.message("The previous version could not restart. Its files have been restored; check its logs and dependencies.") }
        }
        try syncLoginJob(original)
        try FileManager.default.removeItem(at: url)
    }
    private func validateBackupSource(_ instance: DatabaseInstance) throws {
        let data = store.dataDirectory(instance)
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard try data.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              try store.instanceDirectory(instance).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw MorrowError.message("Linked instance directories require a manual backup and upgrade.")
        }
        var readError: Error?
        guard let files = FileManager.default.enumerator(at: data, includingPropertiesForKeys: keys, options: [], errorHandler: { _, error in readError = error; return false }) else { throw MorrowError.message("Cannot read this instance's data directory.") }
        for case let file as URL in files {
            if try file.resourceValues(forKeys: Set(keys)).isSymbolicLink == true {
                throw MorrowError.message("This instance uses linked data or external tablespaces. Use the database's own backup and upgrade tools.")
            }
        }
        if let readError { throw readError }
    }
}
