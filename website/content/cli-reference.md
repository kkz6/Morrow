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
