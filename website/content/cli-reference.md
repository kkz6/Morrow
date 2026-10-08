---
title: CLI reference
description: All commands for managing the same workspace as the macOS app.
group: Reference
order: 6
---
## General commands

| Command | Purpose |
| --- | --- |
| `morrow --help` | List commands and options |
| `morrow --version` | Print the application version |
| `morrow doctor` | Check native discovery, Homebrew, and storage |
| `morrow settings` | Open the macOS app’s Settings window |

## Catalog and software

| Command | Purpose |
| --- | --- |
| `morrow db catalog` | List supported engines and default ports |
| `morrow db channels [engine]` | Discover supported release channels |
| `morrow db versions [engine]` | Show native binaries already available |
| `morrow db install <engine> <channel>` | Advanced preparation without creating instance data |

## Create an instance

```sh
morrow db create <engine> <name> [options]
```

| Option | Meaning |
| --- | --- |
| `--version <version-or-channel>` | Select a release; install only when missing |
| `--port <port>` | Use a specific free port between 1024 and 65535 |
| `--memory <MB>` | Set a supported memory limit; default 128 |
| `--connections <count>` | Set supported connection limits; default 100 |
| `--autostart` | Start at macOS login |
| `--start` | Start immediately after creation |

Use 1–48 letters, numbers, dots, underscores, or hyphens for instance names. Names are unique without regard to letter case.

## Lifecycle and configuration

| Command | Purpose |
| --- | --- |
| `morrow db list [--json]` | List instances and statuses |
| `morrow db status [--json]` | Alias for listing instance statuses |
| `morrow db start <name>` | Start the native server |
| `morrow db stop <name>` | Stop the managed process |
| `morrow db restart <name>` | Stop and start |
| `morrow db configure <name>` | Update a stopped instance |
| `morrow db autostart <name> on\|off` | Change startup behavior |

Configure accepts `--name`, `--port`, `--memory`, and `--connections`.

## Output and removal

| Command | Purpose |
| --- | --- |
| `morrow db connection <name>` | Print a connection address |
| `morrow db logs <name>` | Read recent server output |
| `morrow db remove <name>` | Stop, remove, and archive data |
| `morrow db remove <name> --delete-data` | Permanently delete instance data |

## Standalone CLI build

```sh
./scripts/build-cli.sh
./build/cli/morrow --help
./scripts/install-cli.sh "$(pwd)/build/cli/morrow"
```

The standalone CLI shares the same core and default data directory as the app. A GUI process is not required for commands that manage databases. `morrow settings` requires the app to be built or installed.

## Database updates

| Command | Purpose |
| --- | --- |
| `morrow db updates [name] [--refresh] [--json]` | Compare pinned releases against available formula metadata; refresh runs `brew update` |
| `morrow db upgrade <name>` | Stop, back up, apply a compatible maintenance release, and restart if previously running |
| `morrow db recover <name>` | Recover an interrupted update from its journal and backup |

Read [Database updates](/docs/updates) for compatibility, shared dependency behavior, and recovery limitations.

## Development runtimes

| Command | Purpose |
| --- | --- |
| `morrow tool catalog` | List supported runtimes |
| `morrow tool channels <runtime>` | Show installable Homebrew channels and versions |
| `morrow tool versions [runtime]` | Discover existing binaries |
| `morrow tool install <runtime> [version-or-channel]` | Reuse or install a runtime; defaults to automatic reuse |
| `morrow tool use <runtime> <version>` | Select a default and create Morrow-owned command wrappers |
| `morrow tool list [--json]` | List tracked runtime records; text output marks defaults |
| `morrow tool updates [--refresh] [--json]` | Check tracked versions; optionally refresh Homebrew metadata |
| `morrow tool upgrade <runtime> [version]` | Update a tracked version; omitted version means the default |
| `morrow tool remove <runtime> <version>` | Forget a registration and clear its default; preserve installed files |
| `morrow tool exec <runtime> [--command <name>] -- <args>` | Run the selected runtime or an available companion command with Terminal input/output |
| `morrow tool shell` | Print the PATH setup for Morrow's runtime commands |

Supported runtime names: `php`, `go`, `flutter`, `node`, `python`, `ruby`. Aliases: `nodejs`, `python3`.

For `install` and `use`, numeric release series, existing exact versions, and available formula names are accepted. Installable releases depend on Homebrew. `current` and `latest` choose the current channel; they are installation selectors, not aliases for a saved default.

```sh
morrow tool install go
morrow tool versions go
morrow tool use go 1.27
morrow tool exec go -- version
morrow tool exec node --command npm -- --version
morrow tool shell
```

The version in this example is illustrative. Use `tool versions` and `tool channels` for your machine's available versions. Read [Applications and runtimes](/docs/applications) for Flutter retention and shell behavior.

## iCloud workspace sync

| Command | Purpose |
| --- | --- |
| `morrow sync enable [--folder <path>] [--auto-install]` | Enable folder-based workspace sync; optionally set up missing services on this Mac |
| `morrow sync disable` | Disable sync locally, retaining local services and cloud files |
| `morrow sync status` | Show local sync preferences, folder, and reconciliation results |
| `morrow sync now [--retry] [--json]` | Reconcile once; retry failed recipes when requested |

The default folder is `iCloud Drive/Morrow`. Automatic setup is a local opt-in. The CLI needs an explicit `sync now`; the app checks periodically while running. Results describe local reconciliation, with Apple managing delivery. See [iCloud workspace sync](/docs/icloud-sync) for conflict handling, data boundaries, and release availability.

## Local SMTP servers

| Command | Purpose |
| --- | --- |
| `morrow mail create <name> [options]` | Reuse/install Mailpit and create an isolated local SMTP testing service |
| `morrow mail list [--json]` | Show SMTP/inbox endpoints, pinned versions, and actual status |
| `morrow mail start <name>` | Start and check readiness |
| `morrow mail stop <name>` | Stop the managed service |
| `morrow mail restart <name>` | Stop and start the service |
| `morrow mail inbox <name>` | Open the browser inbox |
| `morrow mail smtp <name>` | Print its SMTP address |
| `morrow mail config <name>` | Print development app environment settings |
| `morrow mail logs <name>` | Read recent output; the app has a live searchable viewer |
| `morrow mail configure <name> [options]` | Change a stopped service's name, ports, and launch-at-login choice |
| `morrow mail remove <name> [--delete-messages]` | Remove the service; archive messages unless permanent deletion is explicit |

Creation options: `--smtp-port <port>`, `--http-port <port>`, `--version <detected-version-or-current>`, `--autostart`, `--start`. Defaults use a detected Mailpit binary and free ports starting at 1025 and 8025.

Configuration options: `--smtp-port <port>`, `--http-port <port>`, `--name <name>`, `--autostart on|off`. Read [Local SMTP testing](/docs/mail) for app settings and inbox behavior.

## Sites and project directories

| Command | Purpose |
| --- | --- |
| `morrow site park <directory>` | Discover immediate project folders |
| `morrow site unpark <directory>` | Remove automatic routes, preserving folders |
| `morrow site directories` | List parked directories |
| `morrow site directory <path> on|off` | Enable or pause discovery |
| `morrow site link [path] [--port <port>] [--domain <name>] [--https]` | Link a project or an app port; omitted path means the working directory |
| `morrow site unlink <domain>` | Remove an explicit link |
| `morrow site list [--json]` | List routes; text includes status, JSON includes route records |
| `morrow site start` | Start user-owned Caddy, DNS, PHP-FPM, and watcher jobs |
| `morrow site stop` | Stop hosting and remove its login jobs |
| `morrow site refresh` | Reconcile directory changes and routes |
| `morrow site watch` | Run the enabled workspace watcher in the foreground |
| `morrow site php [version] [--install]` | List/select complete PHP-FPM installations, or reuse/install current Homebrew PHP |
| `morrow site secure <domain>` | Enable local HTTPS |
| `morrow site unsecure <domain>` | Change the route to HTTP |
| `morrow site configure [options]` | Change suffix, listener ports, and new-site HTTPS/login defaults |
| `morrow site setup [options] [--remove]` | Administrator setup/removal of owned DNS and loopback forwarding |
| `morrow site trust` | Trust Morrow's local CA in this user's login keychain |
| `morrow site open <domain>` | Open the project URL |
| `morrow site logs <domain>` | Print recent routing output |

Configuration options: `--suffix <namespace>`, `--http-port <port>`, `--https-port <port>`, `--dns-port <port>`, `--https on|off`, `--autostart on|off`. Stop hosting before changing listener ports.

System setup options: `--http-port`, `--https-port`, `--dns-port`, `--suffixes <comma-separated-namespaces>`, `--user <uid>` for authorization integrations. Under sudo, the original user's UID is inferred from `SUDO_UID`. System setup never takes over another tool's resolver file.

Read [Sites and project directories](/docs/sites) for PHP roots, development-script integration, private namespaces, certificates, and the system authorization step.
