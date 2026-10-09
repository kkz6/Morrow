# Morrow

A small native macOS menu bar app and CLI for local databases and development runtimes.
The CLI and app share `MorrowCore`; databases run as native
processes managed by macOS launchd.

## Build and open

Requires macOS 14 or later, Xcode, and Homebrew to install database binaries.
Morrow has no third-party Swift package dependencies and bundles no database
servers, browser runtime, container engine, or VM.

```sh
./scripts/build-app.sh
open build/Morrow.app --args --settings
./build/morrow --help
```

Install the CLI into your own local bin directory with
`./scripts/install-cli.sh`. Move the app before linking if you want it in a
permanent location. The application bundle also contains the CLI. Settings → General → Command Line can install
it directly. A standalone CLI build is available through `scripts/build-cli.sh`.

## First database

```sh
./build/morrow db channels postgresql
./build/morrow db create postgresql my-project --version 17 --start
./build/morrow db list
./build/morrow db connection my-project
./build/morrow db stop my-project
./build/morrow db configure my-project --port 5433 --memory 256
./build/morrow db autostart my-project on
```

Supported native providers: PostgreSQL, MySQL, MariaDB, MongoDB, Redis,
Valkey, and Memcached. MongoDB uses its official `mongodb/brew` tap; it is
added when MongoDB is installed. Morrow discovers Homebrew's available
release channels and all supported installed kegs, including existing installs.
Homebrew installs can download dependencies and run formula post-install steps;
Morrow never starts or stops Homebrew's shared service jobs.

**Create Instance** is the main workflow in both the menu and Settings. Select
an engine and release, then create it. Morrow detects Homebrew kegs and native
servers on PATH, verifies the engine and version, and reuses a compatible
installation. Only a missing release is installed. The menu displays managed
instances with their current status. Engine and version choices live directly
in the creation dialog; there is no separate installation screen.

The CLI's `db create` also provisions a missing release automatically. With no
`--version`, it reuses an available server or installs the current channel.
Ports, instance names, and limits are validated before any install. A stopped
Morrow instance still reserves its configured port; external listeners are
checked with a real socket bind. Port availability is checked again after
installation and on startup. Existing data and external service processes are
not adopted or overwritten when reusing a server binary.

**Version management:** installable versions follow Homebrew's available
channels, such as `postgresql@17` or `mysql@8.4`. Each instance records its exact
installed keg path and patch version. Creating another instance supports
another version with separate data and a separate port. Arbitrary historical
patch downloads, major-version data migration, and uninstalling shared
Homebrew packages are not implemented in this preview. External Homebrew
upgrades or cleanup can remove a keg; Morrow reports that version as missing
instead of silently changing an instance's version.

**Local development authentication:** servers bind to `127.0.0.1` and use
passwordless local accounts (PostgreSQL: `postgres`; MySQL/MariaDB: `root`).
Connection addresses are provided for TCP clients. Memcached disables UDP.
Instances are for development on your Mac; authenticated remote hosting is a
later feature.

## Updates and development runtimes

Settings → Databases → Check Updates compares pinned software releases and package revisions with Homebrew metadata. Compatible maintenance updates use an explicit backup, upgrade, and recovery workflow. Different release series require migration. Homebrew can update shared dependencies; this is not an isolated package environment.

```sh
morrow db updates --refresh
morrow db upgrade my-project
morrow db recover my-project # only for an interrupted update
```

Settings → Runtimes manages PHP, Go, Flutter, Node.js, Python, and Ruby. Select a version to reuse or install it and set its Morrow default. Existing binaries are detected before installation. Node uses nvm and the official Node release catalog; other missing runtimes use Homebrew. Version discovery is cached on disk so changing pages does not rescan installations. Runtime cards expose configuration files and PHP-FPM logs. Morrow provides optional PATH wrappers, without changing Homebrew links or shell files. Flutter SDK selections are copied into Morrow storage to preserve them across cask upgrades.

```sh
morrow tool install php 8.4
morrow tool use php 8.4
morrow tool exec php -- --version
morrow tool updates --refresh
morrow tool shell
```

See the [update guide](https://kkz6.github.io/Morrow/docs/updates) and [runtime guide](https://kkz6.github.io/Morrow/docs/applications). Historical Homebrew patches and project-specific runtime files remain limited by the selected provider. Node supports exact versions through nvm; PHP web hosting is managed in Sites.

## Sites and parked projects

Settings → Sites manages parked project directories, PHP-FPM hosting, static roots, project HTTPS, and app-port links. Caddy and dnsmasq are native Homebrew dependencies. Folder discovery continues through a managed watcher after the menu bar app closes.

```sh
morrow site park "$HOME/Projects"
morrow site start
morrow site php 8.4
# From a Node/Go/other HTTP project folder:
morrow site link --port 3000
```

Use `morrow site configure --suffix morrow.test` to choose a private namespace. The **Local Domains** card combines DNS/80/443 setup and certificate trust into one action. **Replace Setup** backs up a leftover resolver when switching from another tool. Existing web listeners still block setup. A native socket-activated gateway handles localhost ports without custom packet-filter rules. Its **…** menu validates HTTPS inline, without opening another window; once configured it checks normal DNS and port 443. Project menus can ignore folders without deleting them. Hosting settings use the web-server configuration icon, and the Projects **+** menu holds directory, linking, and refresh controls.

See the [Sites guide](https://kkz6.github.io/Morrow/docs/sites) for npm `predev` integration, project settings, HTTPS toggles, and setup/removal commands.

## Local SMTP testing

Settings → Mail creates a native Mailpit server with SMTP and a browser inbox. It reuses existing binaries or installs Mailpit through Homebrew, validates both ports, captures mail locally, and exposes logs and lifecycle controls in the app and CLI.

```sh
morrow mail create local-mail --start
morrow mail config local-mail
morrow mail inbox local-mail
```

Both endpoints bind to loopback. Messages are persistent and archived by default on removal. Mail recipes sync through iCloud; messages remain local. See the [SMTP guide](https://kkz6.github.io/Morrow/docs/mail).

## Local S3 storage

Settings → Object Storage creates a native MinIO server and manages buckets. Ports, settings, credentials, and data persist across restarts. The server card and menu bar expose live status, red stop controls, console access, and logs.

```sh
morrow storage create local-s3 --start
morrow storage bucket local-s3 create uploads
morrow storage config local-s3
```

S3 endpoints are loopback-only. Generated credentials stay in private local files and are not synced. Removing a server archives its data and keys. See the [S3 guide](https://kkz6.github.io/Morrow/docs/object-storage).

## iCloud workspace setup

Settings → General → iCloud Sync stores a portable workspace blueprint in a folder inside iCloud Drive. Enable sync on each Mac and opt in to automatic Homebrew setup where missing services should be recreated. Morrow shares recipes and runtime defaults; each Mac keeps its own database data and native executable paths.

```sh
morrow sync enable --auto-install
morrow sync now
morrow sync status
```

The app checks while running; the CLI reconciles on demand. Apple manages file delivery. Existing data is preserved, unavailable release series are reported, and new databases start stopped. See the [sync guide](https://kkz6.github.io/Morrow/docs/icloud-sync) for conflict rules and limitations.

## Data and lifecycle

Terminal icons on service cards and menu rows open the same searchable log
sheet directly, without a separate Logs sidebar page. Search output, pause
live updates, refresh, or copy displayed lines.
Live updates check for appended output each second and retain the most recent
128 KB; file rotation and truncation reset the reader automatically. Logs
remain persisted on disk for the CLI and for use after restarting Morrow.

Data, generated settings, logs, and a versioned state file live in
`~/Library/Application Support/Morrow`. Each instance has a UUID directory.
The app and CLI use file locks and atomic state writes so they can operate
together. Corrupt state is reported and preserved.

Processes run in the foreground under individual launchd jobs, and continue
running when Morrow quits. Start-at-login installs that instance's LaunchAgent
in `~/Library/LaunchAgents`. Manually stopping an instance stops it until you
start it or log in again. Turning off start-at-login removes its login job.
Instance creation initializes data but does not start it unless requested.
Memcached is a volatile cache; its contents disappear when its process stops.

`morrow db remove NAME` stops the managed process and archives its data.
`--delete-data` explicitly deletes it. Archives are preserved folders, not
database backups. The app provides both choices with a confirmation dialog.

For isolated development, set `MORROW_HOME` to a different directory. This also
redirects login plist files into that directory instead of modifying your
normal LaunchAgents. launchd jobs still run in your user session and must be
stopped before you remove an isolated store.

## Development

```sh
./scripts/test.sh
./scripts/build-app.sh debug
```

Open `Package.swift` in Xcode for editing. The build script creates a local
ad-hoc signed `.app`. Developer ID signing and notarization are needed for
distribution to other Macs.

UI snapshots use isolated fixture data and render only Morrow's own views:

```sh
build/Morrow.app/Contents/MacOS/MorrowMenuBar --snapshot /tmp/morrow-preview
```

## Documentation website

The Nuxt documentation site lives in `website/`, with Markdown pages in
`website/content/`. GitHub Pages rebuilds and publishes changes pushed to main.
See [Morrow Docs](https://kkz6.github.io/Morrow/) and [CONTRIBUTING.md](CONTRIBUTING.md).

## Planned next

RabbitMQ and additional providers, database client launching, authenticated
instances, export/import and migration, S3-compatible backup destinations,
remote server management, and eventually PHP/Go toolchains. These capabilities
are not presented as working controls in this preview.

Required third-party notices are included with the application resources.

## Preferences

Command Line, Menu Bar, Appearance, and iCloud Sync are grouped in Settings → General. General is one scrollable page with grouped rows and headings, without a category selector. Navigation groups Sites under Projects, databases/runtimes/mail/S3 under Services, and General/About under App.
