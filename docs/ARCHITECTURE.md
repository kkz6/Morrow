# Architecture

`MorrowCore` contains native providers, Homebrew discovery and installation,
launchd lifecycle management, configuration generation, and persistent state.
Both executable targets link this core directly. There is no required cloud
backend or always-running Morrow daemon.

```text
SwiftUI menu bar + Settings ─┐
                            ├── MorrowCore ── Homebrew native binaries
morrow CLI ─────────────────┘       │
                                  ├── per-instance config, data, and logs
                                  └── user launchd jobs
```

The menu and Settings window use shared UI components. An AppKit
controller owns the fixed window frame and close button; SwiftUI owns pane
content. Geometry is centralized in `SettingsLayout`. The window is 720×620
points, and the menu popover is 340 points wide. Native materials, semantic
colors, switches, and the appearance preference adapt to macOS.

Each native provider specifies initialization, a foreground server command,
and engine-specific configuration. Providers never use `brew services` to
manage shared global databases. A generated LaunchAgent pins the exact binary
path, binds loopback, captures logs, and supplies a stable locale. An instance
records its engine, exact installed keg, port, limits, and startup preference.

Creation provisions software and instance data in one operation. It validates
the requested name, port, and limits before installing anything, detects
existing servers in Homebrew, PATH, Herd, and Postgres.app, and verifies the
actual engine and version before reuse. A missing release is installed via
Homebrew and verified again. Ports are checked after installation and on start.
MySQL compatibility aliases that actually run MariaDB are classified as MariaDB.

Inputs and selectors share `ControlLayout` for height and spacing. Selectors
use a native AppKit popup with the reference's icon, label, and outlined
up/down capsule. Text and search fields use a shared SwiftUI component; the
instance dialog uses the same grouped card rows as Settings.

Separate file locks protect long operations and short state transactions.
This allows the UI to refresh during installation while serializing changes
from multiple CLIs or app actions. State writes are atomic and schema versioned.
Unreadable state is preserved and surfaced as an error.

Version upgrades are intentionally separate from data migration. Installing
another major release creates another available binary; creating an instance
with that binary initializes its own data directory. The manager rejects
changing an existing instance's binary. A future migration feature must export
or use engine-specific upgrade tools before promoting a new instance.

Later native installers can implement independent download/catalog sources
without changing the UI's instance model. A Morrow release server or S3 bucket
could distribute native artifacts; S3 backup storage and remote database
management need their own authentication and data transfer implementations.

## Initial verification

- Eleven automated core tests and four app flow tests pass, including concurrent writes, malformed state
  preservation, command output handling, input validation, exact binary paths,
  separate instance data, guarded version changes, and safe removal.
  App flow checks cover showing unused installed versions and creating an
  instance with the selected engine and exact installed version.
- Native Redis was installed and exercised through creation, start, restart,
  key persistence, stop, and removal with preserved files.
- Native PostgreSQL 17 was installed and exercised through initialization,
  startup, a real SQL connection, changed resource limits, restart, login
  setting changes, stop, and removal with preserved files.
- Settings and menu views were rendered from isolated fixture data and reviewed.
- MySQL, MariaDB, MongoDB, Valkey, and Memcached providers have configuration
  checks; their real server lifecycles still need integration coverage.
