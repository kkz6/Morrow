# Changelog

## Unreleased

- Grouped Command Line, Menu Bar, Appearance, and iCloud Sync preferences inside General.
- Local Mailpit SMTP testing services with a persistent inbox, loopback bindings, dual-port validation, lifecycle controls, in-app logs, CLI commands, and portable iCloud setup recipes.
- Redis and Valkey use vendor vector brand marks consistently across menu rows, instance details, and selectors.
- Service status now checks the managed PID with the OS and uses native administration or protocol readiness checks where available.
- iCloud Drive workspace blueprints sync portable preferences, database recipes, runtime series, and defaults across Macs.
- Per-Mac automatic Homebrew setup, safe port selection, additive snapshots, local-removal suppression, setup reports, and app/CLI retry controls.
- Local databases, credentials, logs, executable paths, and process state are excluded from workspace sync.
- Fixed false startup failures caused by treating launchd’s “never exited” placeholder as a real exit code.
- Startup errors now include only a short excerpt from the current start attempt, with full output available in Logs.
- Database update checks distinguish numeric maintenance releases, package revisions, and migration-required release series.
- Explicit database upgrades preserve a stopped instance backup, verify the new binary, and restore the previous instance on failure when possible.
- Durable update journals and app/CLI recovery controls protect interrupted operations.
- Applications settings and shared CLI management for PHP, Go, Flutter, Node.js, Python, and Ruby.
- Existing runtime discovery, version selection, companion commands, interactive execution, and optional Morrow-owned PATH wrappers.
- Runtime update checks and explicit upgrades; selected Flutter SDKs are retained separately from Homebrew's global cask.
- Existing workspace state remains readable with runtime fields added using backward-compatible decoding.

## 0.1.0 — Developer preview

- Native macOS menu bar app with a single database creation workflow.
- Shared CLI for creating, starting, stopping, configuring, and removing instances.
- PostgreSQL, MySQL, MariaDB, MongoDB, Redis, Valkey, and Memcached providers.
- Existing server detection in Homebrew, PATH, Herd, and Postgres.app.
- Port and duplicate validation before installation and on startup.
- Separate data directories and pinned native executables per instance.
- In-app logs with search, live updates, pause, and copy.
- Shared input, selector, and settings window components.
- Independent CLI build and safe local command installation.
- Explicit current Xcode/SDK builds and verified SDK records in the app binary.
- Nuxt documentation with Markdown guides, search, and automatic GitHub Pages deployment.
- Removed the separate Versions screen; database setup now lives entirely in creation.
- Standardized action buttons to the supplied macOS reference, with inset card actions, matching dialog controls, and About links to documentation and source.
- Simplified About to app identity, version, and links; removed the menu footer caption and product-level third-party references.
- Added fixed settings headers with a native gradient blur while scrolling, smooth appearance changes, and Reduce Motion support.
- Refined menu controls with borderless secondary icons and a compact, understated creation action.
- Added automatic card-edge corner geometry, lighter shared actions, a single-action database empty state, and a balanced About resource group.

Remote hosting, authenticated instance configuration, scheduled backups, S3 storage,
RabbitMQ, project-specific runtime selection, and additional toolchains are planned.
