# Changelog

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

Remote hosting, authenticated instance configuration, backups, S3 storage,
RabbitMQ, and language toolchains are planned and not included in this preview.
