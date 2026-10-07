import Foundation

public enum CLIInstaller {
    public static var defaultDestination: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/morrow")
    }
    public static func install(source: URL, destination: URL = defaultDestination) throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: source.path) else { throw MorrowError.message("The bundled CLI is missing. Rebuild Morrow.app first.") }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) || (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            if let target = try? fm.destinationOfSymbolicLink(atPath: destination.path), URL(fileURLWithPath: target).standardizedFileURL == source.standardizedFileURL { return }
            throw MorrowError.message("A command already exists at \(destination.path). Choose another location or remove that command before installing Morrow's CLI.")
        }
        try fm.createSymbolicLink(at: destination, withDestinationURL: source)
    }
}
