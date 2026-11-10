# Development-tool feature review

Reviewed 10 November 2026 against Flock `93101c8f7c36d8b3d0175b6959a8bd29208b1afe` and Lerd `34487c66f170c60bb1c99762c4699a5477bd6996`. This compares their public feature families and selected implementation paths with Morrow. It is not a full code or security audit of either project.

Morrow should keep its native macOS interface, shared app/CLI core, portable Apple silicon distributions, and explicit ownership of services. Features should fit into project details, the existing service cards, and General instead of adding a sidebar entry for every tool. Existing services and project files must remain usable through upgrades.

## Added in the current development branch

| Addition | Result | Limits |
| --- | --- | --- |
| Native mail inbox | Project tags, search, HTML/text/raw/header views, attachments, message deletion, SMTP settings | Uses existing Mailpit; project tagging becomes active on a server's next start |
| PHP request timeline | Per-folder opt-in dumps, supported Laravel queries/logs/views/jobs, app and CLI | Laravel 11+ with uncached local configuration; existing workers need a later launch through the Morrow PHP shim |
| Project Health | Framework detection, public directory, dependency markers, saved runtime/version-file comparisons, private environment checks | Read-only metadata checks; no dependency installation, migrations, extension probing, or database validation |
| Better new-site detection | Conventional PHP framework roots; Node/Go/Python/Ruby/Rust wait for an app port | Existing site settings stay unchanged; custom layouts still need an explicit root |
| Query insights | Request duration/status, query totals, ≥100 ms markers, repeated shapes by request and connection | Heuristic repetition hints, not confirmed N+1 detection or a profiler |
| Better capture navigation | Search nested values/bindings/source paths, type-aware request filtering, attention filter | Searches retained captures only |

## Comparison and recommended fit

### Project setup, runtimes, and workers

| Feature reviewed | Morrow today | Recommended next step |
| --- | --- | --- |
| Framework-aware setup and diagnostics | Detection and read-only Project Health added here | Add reviewed, versioned setup recipes with a visible plan and step logs. Never execute hooks merely because a folder is parked. [Lerd setup](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/features/project-setup.md) |
| Shareable runtime pins | Exact machine-local folder choices; common version files appear in health reports | Add a portable project manifest and version-file resolution shared by hosting and CLI. Explicit local override → nearest project request → default; unavailable requests must not silently fall back. [Flock versions](https://github.com/flock-php/flock/blob/93101c8f7c36d8b3d0175b6959a8bd29208b1afe/docs/project-versions.md) |
| PHP, Node, and other runtime isolation | PHP, Node, Go, Flutter, Python, Ruby; portable downloads and project selection | Keep current native distribution model. Container runtimes and cross-platform hosts are not needed for parity on macOS. [Lerd native runtime](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/features/native-runtime.md) |
| Queue, scheduler, Horizon, Reverb, and other workers | Can adopt existing launch agents without restarting them; no worker creation UI | Add explicit worker presets with arguments, logs, real status, restart policy, and stop controls. Reuse the signed Morrow service runner and avoid duplicate workers. [Lerd workers](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/usage/framework-workers.md) |
| Node/Go/Python development-server supervision | Port linking works; user starts app commands | Build on the same worker manager, with explicit command and working directory, owned process identity, port readiness, and bounded restart backoff. [Host proxy](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/usage/host-proxy.md) |
| Framework/service definition store | Compiled lifecycle implementations and a signed/checksummed distribution catalog | First use bundled declarative recipes. Add remotely updated definitions after schema/version validation and rollback exist. Keep executable plugins separate. [Framework definitions](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/usage/framework-definitions.md) |
| Scaffold projects and install dependencies | Link/park existing folders | Add an explicit create-project flow with runtime choice, destination checks, visible package commands, and resumable setup. Do not combine it with automatic directory discovery. |
| Worker self-healing and idle suspension | Service status is real; PHP-FPM already uses on-demand workers | Add failure backoff and manual recovery before optional sleep/wake. Queue and scheduler suspension needs clear user control because work can arrive without a browser request. [Idle suspension](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/usage/idle-suspend.md) |

### Worktrees and data

| Feature reviewed | Morrow today | Recommended next step |
| --- | --- | --- |
| Worktree discovery and domains | Parked immediate child worktrees can be included/excluded; manual linking works | Add repository-level worktree grouping, branch metadata, and stable branch-domain naming without altering existing URLs. |
| Worktree bootstrap | No automatic package installs or environment changes | Offer a setup plan. Copy-on-write dependency reuse needs matching lockfiles and independent writable copies; never symlink mutable dependency directories between checkouts. |
| Isolated worktree database/cache/queue/session state | Health reminder only; application configuration can remain shared | Add explicit shared/fresh/copied database choices and per-worktree cache/queue/session names, with a reversible environment patch and ownership records. [Flock worktrees](https://github.com/flock-php/flock/blob/93101c8f7c36d8b3d0175b6959a8bd29208b1afe/docs/worktrees.md), [Lerd worktrees](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/features/git-worktrees.md) |
| Database snapshots, import/export, restore | Instance lifecycle, compatible-update backup/recovery; no general project snapshot workflow | Add engine-specific export/import and named snapshots before automatic worktree cloning. Validate restore targets, keep rollback data, and test real restores. [Lerd database tools](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/usage/database.md) |
| External database connections and browsing | Existing binary reuse; Morrow manages its own instances | Add an explicit external connection type. Never treat an imported connection as permission to stop its server or delete its data. |
| Scheduled snapshots and retention | No scheduled project snapshots | Follow tested manual snapshot/restore. Retention must preserve pinned snapshots and show disk usage. |
| Extra services: search, queues, admin tools | Databases, Redis/Valkey, Mailpit, MinIO | Prioritize Meilisearch/Typesense if native arm64 distributions and lifecycle checks are available; use the existing catalog and cards. Broader brokers/search stacks are optional later additions. [Service presets](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/usage/service-presets.md) |

### Hosting and sharing

| Feature reviewed | Morrow today | Recommended next step |
| --- | --- | --- |
| Local domains, TLS renewal, custom suffixes | Already implemented, including native helper and trust checks | Preserve the current local gateway and certificate ownership; no replacement is required. |
| Site groups and subdomains | Explicit dotted domains work; no group model | Add relationships only when shared services, environment, or navigation benefit. Keep each site's explicit hostname. |
| Vite assets/HMR under project hostnames | Generic WebSocket-capable proxy; project configuration may still be needed | Add a dev-server integration through the worker manager, with framework-specific HMR validation. Do not blindly rewrite arbitrary HTML or JavaScript responses. [Host proxy](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/usage/host-proxy.md) |
| LAN/mobile previews | Local loopback hosting | Offer one selected site, a visible share state, expiry/stop, and a QR code. HTTPS and secure-cookie behavior must be explicit. [LAN sharing](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/usage/lan-sharing.md) |
| Public tunnels | Not implemented | Start with an optional time-limited provider. Sharing must be explicit, site-scoped, and stop on request; block local tools and expose application debug settings clearly. [Flock sharing](https://github.com/flock-php/flock/blob/93101c8f7c36d8b3d0175b6959a8bd29208b1afe/docs/sharing.md) |
| FrankenPHP/Octane and custom containers | PHP-FPM and native app-port proxying | Consider a separate runtime option after worker ownership and readiness are proven. Keep native PHP-FPM as the default. |

### Debugging and productivity

| Feature reviewed | Morrow today | Recommended next step |
| --- | --- | --- |
| On-demand Xdebug, IDE triggers, breakpoints | Not implemented | Package ABI-matched arm64 extensions per PHP version and use isolated debug pools. Normal requests should not load an active debugger. [Flock Xdebug](https://github.com/flock-php/flock/blob/93101c8f7c36d8b3d0175b6959a8bd29208b1afe/docs/xdebug.md) |
| Flame-graph profiling | Request/query timing only | Add an explicit per-project or single-request profiler after compatible extension distribution. Captures stay local with bounded retention. [Lerd profiler](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/features/profiler.md) |
| Framework-independent query capture | Supported Laravel event capture | Evaluate a separately packaged PHP observer extension. Do not claim current userland capture covers arbitrary PDO/frameworks. [Lerd queries](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/features/queries.md) |
| Outgoing HTTP, browser errors, and richer application events | Not captured | Add opt-in adapters with sensitive-header/body handling and source attribution; preserve application semantics. |
| Historical request analytics | Bounded recent request captures and insights | Add route timing from access logs separately from debug capture, normalize dynamic IDs, exclude assets/WebSockets, and label retention. [Request timing](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/features/request-timing.md) |
| REPL/Tinker and editor integration | Runtime execution and source reveal | Add a project-aware Terminal action first; IDE deep links and a native REPL can follow. Keep execution explicit. |
| MCP/AI integration | CLI with structured output for many operations | Start with read-only status, project health, mail metadata, and request insights, then carefully scoped mutations through MorrowCore. Client configuration changes must be explicit and preserve existing entries. [Flock AI](https://github.com/flock-php/flock/blob/93101c8f7c36d8b3d0175b6959a8bd29208b1afe/docs/ai.md), [Lerd MCP](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/features/mcp.md) |
| Config editing with validation/rollback | Opens runtime configuration files | Add versioned backups and a validate/apply flow before an embedded editor. Preserve external editors and existing configuration. |
| Offline documentation, command palette, terminal UI | Nuxt documentation, native sidebar, CLI | Bundle concise troubleshooting/help and add native search before building a second full UI. |
| Plugins, IDE extensions, remote/container hosts | Not implemented | Defer until core lifecycle APIs stabilize. Declarative recipes are a smaller first step than executing third-party plugins. [Lerd plugins](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/docs/features/plugins.md) |

## Recommended implementation order

1. **Portable project requirements and managed workers.** They provide a common foundation for setup, runtime selection, queues, HMR, and framework recipes. Include permission grouping and real status from the first release.
2. **Database export/snapshots and worktree isolation.** Prove restore/recovery before enabling automatic worktree data provisioning. Keep setup hooks visible and opt-in.
3. **Xdebug, extension compatibility, and profiling.** Validate each PHP ABI and coexistence with capture, custom bootstrap settings, and ordinary serving pools.
4. **Explicit LAN/public previews and read-only MCP.** Keep exposure and automation permissions distinct from ordinary local hosting.
5. **Broader services, request analytics, and extension points.** Add these on the same tested lifecycle and data-management foundations.

These are recommendations, not claims of shipped functionality or scheduled release commitments. Current additions remain unreleased until the branch is merged and a signed release is published.

## Implementation boundaries

Flock identifies its source license as AGPL-3.0 and Lerd as MIT. This change implements original Swift behavior using Morrow's existing components and local data; it does not import either project's implementation. Reference projects help identify useful workflows, not require duplicating their UI or architecture.

Selected implementation references include [Flock project selection](https://github.com/flock-php/flock/blob/93101c8f7c36d8b3d0175b6959a8bd29208b1afe/internal/project/project.go), [Flock worktree setup](https://github.com/flock-php/flock/blob/93101c8f7c36d8b3d0175b6959a8bd29208b1afe/internal/worktree/setup.go), [Lerd framework definitions](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/internal/config/framework.go), and [Lerd event analysis](https://github.com/lerd-env/lerd/blob/34487c66f170c60bb1c99762c4699a5477bd6996/internal/dumps/lens.go).
