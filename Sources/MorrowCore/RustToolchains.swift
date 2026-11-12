import Foundation

enum RustToolchains {
    // Official Rust standalone bundle, pinned to the arm64 checksum in
    // channel-rust-1.99.1.toml. Catalog releases can supply newer versions.
    static let standalone = BinaryRelease(
        package: "rust", version: "1.99.1", architecture: "arm64", minimumMacOS: "14.0",
        url: URL(string: "https://static.rust-lang.org/dist/2026-10-15/rust-1.99.1-aarch64-apple-darwin.tar.xz")!,
        sha256: "30976378b6aaefd1861ba475905c6ba22a44c981418ce52285006af26337f98c",
        archive: "tar", rootDirectory: "rust-1.99.1-aarch64-apple-darwin",
        executables: ["bin/rustc", "bin/cargo", "bin/rustdoc", "bin/rustfmt", "bin/cargo-clippy"]
    )

    static func installed() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let override = ProcessInfo.processInfo.environment["RUSTUP_HOME"]
        let root = override.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ?? home.appendingPathComponent(".rustup")
        return ((try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("toolchains"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix("-aarch64-apple-darwin") }
    }

    /// Assemble the official installer components as a private prefix without
    /// running install.sh or writing into rustup's directories.
    static func assemble(_ upstream: URL, at prefix: URL) throws {
        let fm = FileManager.default
        func merge(_ source: URL, into destination: URL) throws {
            let kind = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if kind.isDirectory == true && kind.isSymbolicLink != true {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    try merge(child, into: destination.appendingPathComponent(child.lastPathComponent))
                }
            } else {
                try fm.copyItem(at: source, to: destination)
            }
        }
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        for component in ["rustc", "cargo", "rust-std-aarch64-apple-darwin", "rustfmt-preview", "clippy-preview"] {
            for item in try fm.contentsOfDirectory(at: upstream.appendingPathComponent(component), includingPropertiesForKeys: nil)
                where item.lastPathComponent != "manifest.in" {
                try merge(item, into: prefix.appendingPathComponent(item.lastPathComponent))
            }
        }
        for notice in ["COPYRIGHT", "LICENSE-APACHE", "LICENSE-MIT"] {
            try fm.copyItem(at: upstream.appendingPathComponent(notice), to: prefix.appendingPathComponent(notice))
        }
        guard let paths = fm.enumerator(at: prefix, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw MorrowError.message("The Rust toolchain could not be inspected.")
        }
        for case let path as URL in paths {
            if try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true,
               !path.resolvingSymlinksInPath().path.hasPrefix(prefix.resolvingSymlinksInPath().path + "/") {
                throw MorrowError.message("A Rust toolchain link escapes the installation.")
            }
        }
    }
}
