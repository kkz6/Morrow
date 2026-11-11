import Foundation

extension ComposerPHPRequirement {
    public static func read(at path: String) throws -> Self? {
        guard let manifest = try ProjectFiles(path: path).json("composer.json") else { return nil }
        let constraints = try ["require", "require-dev"].compactMap { section -> String? in
            guard let value = (manifest[section] as? [String: Any])?["php"] else { return nil }
            guard let constraint = value as? String, !constraint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MorrowError.message("composer.json has an invalid PHP requirement in \(section).")
            }
            return constraint
        }
        let config = manifest["config"] as? [String: Any]
        let platform = (config?["platform"] as? [String: Any])?["php"] as? String
        guard !constraints.isEmpty || platform != nil else { return nil }
        return Self(constraints: constraints, platformVersion: platform)
    }
}

/// Reads bounded project metadata only. Discovery never runs project commands,
/// package scripts, PHP configuration, or Git hooks.
public struct ProjectProfile: Codable, Sendable {
    public let name: String
    public let mode: SiteMode
    public let documentRoot: String
    public let requiresPublicDirectory: Bool

    public static func detect(at path: String) throws -> Self {
        let files = ProjectFiles(path: path)
        let composer = try files.json("composer.json")
        let packages = (composer?["require"] as? [String: Any] ?? [:])
            .merging(composer?["require-dev"] as? [String: Any] ?? [:]) { first, _ in first }
        let php: [(String, String, String)] = [
            ("statamic/cms", "Statamic", "public"), ("laravel/framework", "Laravel", "public"),
            ("roots/bedrock", "WordPress · Bedrock", "web"), ("roots/wordpress", "WordPress · Bedrock", "web"),
            ("drupal/core-recommended", "Drupal", "web"), ("drupal/core", "Drupal", "web"),
            ("magento/product-community-edition", "Magento", "pub"), ("magento/product-enterprise-edition", "Magento", "pub"),
            ("symfony/framework-bundle", "Symfony", "public"), ("cakephp/cakephp", "CakePHP", "webroot"),
            ("codeigniter4/framework", "CodeIgniter", "public"), ("yiisoft/yii2", "Yii", "web")
        ]
        if let match = php.first(where: { packages[$0.0] != nil }) {
            // Drupal also supports a traditional root-level installation.
            let root = match.1 == "Drupal" && files.exists("core/lib/Drupal.php") ? "" : match.2
            return Self(name: match.1, mode: .php, documentRoot: files.url(root).path, requiresPublicDirectory: !root.isEmpty)
        }
        if files.exists("artisan") { return Self(name: "Laravel", mode: .php, documentRoot: files.url("public").path, requiresPublicDirectory: true) }
        if files.exists("wp-includes/version.php") { return Self(name: "WordPress", mode: .php, documentRoot: files.root.path, requiresPublicDirectory: false) }
        let root = files.isDirectory("public") ? "public" : ""
        if files.exists(root.isEmpty ? "index.php" : "public/index.php") {
            return Self(name: "PHP", mode: .php, documentRoot: files.url(root).path, requiresPublicDirectory: false)
        }
        if let package = try files.json("package.json") {
            let dependencies = (package["dependencies"] as? [String: Any] ?? [:])
                .merging(package["devDependencies"] as? [String: Any] ?? [:]) { first, _ in first }
            let frameworks = [("nuxt", "Nuxt"), ("next", "Next.js"), ("@sveltejs/kit", "SvelteKit"), ("astro", "Astro"), ("@nestjs/core", "NestJS"), ("vite", "Vite")]
            return Self(name: frameworks.first(where: { dependencies[$0.0] != nil })?.1 ?? "Node.js", mode: .proxy, documentRoot: files.root.path, requiresPublicDirectory: false)
        }
        let servers = [("go.mod", "Go"), ("Cargo.toml", "Rust"), ("manage.py", "Django"), ("pyproject.toml", "Python"), ("requirements.txt", "Python"), ("Gemfile", "Ruby")]
        if let server = servers.first(where: { files.exists($0.0) }) {
            return Self(name: server.1, mode: .proxy, documentRoot: files.root.path, requiresPublicDirectory: false)
        }
        // A Composer project without a public entry point must never expose its
        // source directory as a static website.
        if composer != nil { return Self(name: "PHP", mode: .php, documentRoot: files.url(root).path, requiresPublicDirectory: false) }
        return Self(name: "Static files", mode: .files, documentRoot: files.url(root).path, requiresPublicDirectory: false)
    }
}

public struct ProjectCheck: Codable, Identifiable, Sendable {
    public enum Level: String, Codable, Sendable { case passed, information, warning }
    public let id: String
    public let level: Level
    public let title: String
    public let detail: String
}

public struct ProjectRequirement: Codable, Identifiable, Sendable {
    public var id: String { source + ":" + name }
    public let name: String
    public let version: String
    public let source: String
}

public struct ProjectInspection: Codable, Sendable {
    public let path: String
    public let profile: ProjectProfile
    public let requirements: [ProjectRequirement]
    public let checks: [ProjectCheck]
    public var warningCount: Int { checks.filter { $0.level == .warning }.count }

    public static func inspect(path: String, store: StateStore = StateStore(), site: LocalSite? = nil) throws -> Self {
        let path = try ProjectRuntimeStore.directory(path)
        let files = ProjectFiles(path: path), profile = try ProjectProfile.detect(at: path)
        let state = try store.load(), selections = try ProjectRuntimeStore(store: store).load()
        var checks: [ProjectCheck] = [], requirements: [ProjectRequirement] = []
        func check(_ id: String, _ good: Bool, _ title: String, _ goodText: String, _ badText: String) {
            checks.append(ProjectCheck(id: id, level: good ? .passed : .warning, title: title, detail: good ? goodText : badText))
        }
        if profile.requiresPublicDirectory {
            check("public-root", files.isDirectory(URL(fileURLWithPath: profile.documentRoot).lastPathComponent), "Public directory", "The framework's public directory exists.", "The expected \(URL(fileURLWithPath: profile.documentRoot).lastPathComponent) directory is missing. Finish setting up this checkout before hosting it.")
        }
        if let site {
            check("hosting", !site.isIgnoredForHosting, "Local hosting", "This project is included in local hosting.", "This project is excluded from local hosting. Its files are preserved.")
            if let issue = site.issue { checks.append(ProjectCheck(id: "route", level: .warning, title: "Site configuration", detail: issue)) }
            if profile.requiresPublicDirectory {
                check("configured-root", URL(fileURLWithPath: site.documentRoot).resolvingSymlinksInPath().path == profile.documentRoot, "Document root", "The site uses the framework's public directory.", "The current document root differs from \(profile.documentRoot). Review Project Settings if this is not intentional.")
            }
            if site.mode == .proxy { check("proxy", site.proxyPort != nil, "App port", "A local development port is linked. Start your app separately.", "Set the app's listening port in Project Settings. Morrow does not start its development command.") }
        }
        if let composer = try files.json("composer.json") {
            check("composer", files.exists("vendor/autoload.php"), "Composer dependencies", "vendor/autoload.php exists.", "Run composer install in this folder using its PHP version. Morrow has not run package scripts.")
            for section in ["require", "require-dev"] {
                for (name, value) in (composer[section] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) where name == "php" || name.hasPrefix("ext-") {
                    if let version = value as? String { requirements.append(.init(name: name, version: String(version.prefix(160)), source: "composer.json · " + section)) }
                }
            }
        }
        if let package = try files.json("package.json") {
            check("node-packages", files.isDirectory("node_modules") || files.exists(".pnp.cjs"), "JavaScript dependencies", "A local dependency directory or Yarn PnP loader exists.", "Install this project's dependencies with its chosen package manager. Existing files have not been changed.")
            for (name, value) in (package["engines"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                if let version = value as? String { requirements.append(.init(name: name, version: String(version.prefix(160)), source: "package.json · engines")) }
            }
            if let manager = package["packageManager"] as? String { requirements.append(.init(name: "Package manager", version: String(manager.prefix(160)), source: "package.json")) }
        }
        for (file, runtime) in [(".nvmrc", RuntimeEngine.node), (".node-version", .node), (".php-version", .php), (".python-version", .python), (".ruby-version", .ruby)] {
            if let content = try files.text(file, limit: 8192), let version = content.split(separator: "\n").map({ $0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
                requirements.append(.init(name: runtime.title, version: String(version.prefix(160)), source: file))
                let selected = selectedRuntime(runtime, path: path, site: site, state: state, selections: selections)
                let requested = version.hasPrefix("v") ? String(version.dropFirst()) : version
                if let requestedVersion = SoftwareVersion(requested), requestedVersion.components.count <= 3 {
                    let actual = selected.flatMap { SoftwareVersion($0.version) }
                    let matches = actual.map { Array($0.components.prefix(requestedVersion.components.count)) == requestedVersion.components } ?? false
                    check("version-" + file, matches, runtime.title + " project version", "The selected runtime matches \(file).", "\(file) asks for \(String(version.prefix(160))). \(selected.map { "Morrow selects \($0.version)." } ?? "No runtime is selected.") Choose a folder version to apply this requirement.")
                } else {
                    checks.append(.init(id: "version-" + file, level: .information, title: runtime.title + " version request", detail: "Review \(file) when choosing a folder version. Aliases and ranges are displayed without resolving or installing them."))
                }
            }
        }
        if profile.mode == .php {
            let php = selectedRuntime(.php, path: path, site: site, state: state, selections: selections)
            check("php", php.map { FileManager.default.isExecutableFile(atPath: $0.executable) } ?? false, "PHP runtime", php.map { "PHP \($0.version) is selected; its executable exists." } ?? "", "Choose an available PHP version for this folder in Folder Versions.")
            if site?.mode == .php { check("fpm", php?.phpFPM != nil, "PHP hosting", "The selected PHP installation includes PHP-FPM.", "PHP hosting needs a complete PHP installation with PHP-FPM.") }
        }
        if files.exists(".env.example") { check("env", files.exists(".env"), "Environment file", "A local .env file exists. Values are not included in this report.", "This project has .env.example but no .env. Set up its local environment before running it.") }
        if ["Laravel", "Statamic"].contains(profile.name) {
            if let env = try files.text(".env", limit: 262_144) {
                let key = env.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix("APP_KEY=") }
                let value = key.map { String($0.dropFirst(8)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                check("app-key", value.map { !$0.isEmpty && !$0.hasPrefix("#") } ?? false, "Laravel application key", "An APP_KEY entry is present in .env. Its value is kept private.", "APP_KEY is absent or empty in .env. If a key is supplied externally, leave it intact. Otherwise set up a local key; replacing an existing key invalidates encrypted data.")
            }
            if files.exists("bootstrap/cache/config.php") { checks.append(.init(id: "config-cache", level: .warning, title: "Cached Laravel configuration", detail: "Cached configuration can hide .env changes and prevents Morrow's full Laravel event capture. For local development, review whether php artisan config:clear is appropriate.")) }
        }
        if GitWorktree.isLinked(at: files.root) { checks.append(.init(id: "worktree", level: .information, title: "Git worktree", detail: "Hosting is separate, but database, cache, queue, and session settings may still be shared with the main checkout. Review the worktree's environment before running jobs or migrations.")) }
        let priority: [ProjectCheck.Level: Int] = [.warning: 0, .information: 1, .passed: 2]
        let ordered = checks.enumerated().sorted {
            let a = priority[$0.element.level]!, b = priority[$1.element.level]!
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
        return Self(path: path, profile: profile, requirements: requirements, checks: ordered)
    }

    private static func selectedRuntime(_ engine: RuntimeEngine, path: String, site: LocalSite?, state: MorrowState, selections: [ProjectRuntimeSelection]) -> RuntimeInstallation? {
        if let item = ProjectRuntimeStore.selection(engine, directory: path, projects: selections) { return item }
        if engine == .php, site?.mode == .php { return state.web.php.first { $0.id == (site?.phpID ?? state.web.defaultPHPID) } }
        return state.tools.first { $0.id == state.toolDefaults[engine.rawValue] }
    }
}

private struct ProjectFiles {
    let root: URL
    init(path: String) { root = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() }
    func url(_ relative: String) -> URL { relative.isEmpty ? root : root.appendingPathComponent(relative) }
    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: url(relative).path) }
    func isDirectory(_ relative: String) -> Bool { (try? url(relative).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    func text(_ relative: String, limit: Int) throws -> String? {
        let file = url(relative)
        guard exists(relative) else { return nil }
        guard file.resolvingSymlinksInPath().path.hasPrefix(root.path + "/"),
              (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { throw MorrowError.message("\(relative) must be a regular file inside this project.") }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit, let content = String(data: data, encoding: .utf8) else { throw MorrowError.message("\(relative) is too large or is not UTF-8 text.") }
        return content
    }
    func json(_ relative: String) throws -> [String: Any]? {
        guard let content = try text(relative, limit: 1_048_576) else { return nil }
        guard let value = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any] else { throw MorrowError.message("\(relative) is not a valid JSON object. Fix it and check the project again.") }
        return value
    }
}
