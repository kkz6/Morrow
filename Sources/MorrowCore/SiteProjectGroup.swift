import Foundation

/// Presentation groups only: grouping never edits a site's hosting policy or routes.
public struct SiteProjectGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let project: LocalSite?
    public let worktrees: [LocalSite]

    public static func groups(for sites: [LocalSite]) -> [SiteProjectGroup] {
        var projects: [LocalSite] = []
        var worktrees: [URL: [LocalSite]] = [:]
        for site in sites {
            if let common = GitWorktree.linkedCommonDirectory(at: URL(fileURLWithPath: site.path)) {
                worktrees[common, default: []].append(site)
            } else {
                projects.append(site)
            }
        }
        var result = projects.map { site in
            let common = GitWorktree.mainDirectory(at: URL(fileURLWithPath: site.path))
            let children = common.flatMap { worktrees.removeValue(forKey: $0) } ?? []
            return SiteProjectGroup(id: site.id.uuidString, name: site.domain, project: site,
                                    worktrees: children.sorted(by: siteOrder))
        }
        // Keep worktrees accessible even when their main checkout is not a linked site.
        for (common, children) in worktrees {
            let repository = common.lastPathComponent == ".git" ? common.deletingLastPathComponent() : common
            result.append(SiteProjectGroup(id: common.path, name: repository.lastPathComponent,
                                           project: nil, worktrees: children.sorted(by: siteOrder)))
        }
        return result.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Keep the parent as context when a child matches; parent matches reveal all children.
    public func matching(_ query: String) -> SiteProjectGroup? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self }
        func matches(_ site: LocalSite) -> Bool {
            site.domain.localizedCaseInsensitiveContains(query) || site.path.localizedCaseInsensitiveContains(query)
        }
        if project.map(matches) == true || (project == nil && name.localizedCaseInsensitiveContains(query)) { return self }
        let children = worktrees.filter(matches)
        guard !children.isEmpty else { return nil }
        return SiteProjectGroup(id: id, name: name, project: project, worktrees: children)
    }

    private static func siteOrder(_ lhs: LocalSite, _ rhs: LocalSite) -> Bool {
        let order = lhs.domain.localizedStandardCompare(rhs.domain)
        return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
    }
}
