import Foundation

enum GitWorktree {
    /// A gitfile alone also identifies submodules and separate git directories.
    /// Linked worktrees additionally have a common directory and a back-pointer.
    /// Read metadata only; discovery never runs Git or invokes repository hooks.
    static func isLinked(at folder: URL) -> Bool {
        let gitfile = folder.appendingPathComponent(".git")
        guard let contents = smallText(gitfile), contents.hasPrefix("gitdir: ") else { return false }
        let path = String(contents.dropFirst(8))
        guard !path.isEmpty else { return false }
        let directory = resolve(path, relativeTo: folder)
        guard let common = smallText(directory.appendingPathComponent("commondir")), !common.isEmpty,
              let backPointer = smallText(directory.appendingPathComponent("gitdir")), !backPointer.isEmpty else { return false }
        return resolve(backPointer, relativeTo: directory) == gitfile.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func resolve(_ path: String, relativeTo base: URL) -> URL {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path))
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func smallText(_ url: URL) -> String? {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 8193), data.count <= 8192 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
