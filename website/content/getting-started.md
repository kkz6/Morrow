---
title: Getting started
description: Build Morrow and create your first local database in one step.
group: Start here
order: 1
---
Morrow is a native macOS menu bar app and CLI. Both use the same databases, development runtimes, settings, and data folders. This developer preview supports macOS 14 and later.

## Build the app and CLI

Install a full version of Xcode and its command line tools. The build script selects the newest full Xcode in `/Applications` and uses its macOS SDK. Homebrew is needed when a chosen database version is missing.

```sh
git clone https://github.com/kkz6/Morrow.git
cd Morrow
./scripts/build-app.sh
open build/Morrow.app --args --settings
```

The build produces `build/Morrow.app`, which includes the CLI, and `build/morrow` for use from this checkout. Database servers are managed as native processes and downloaded only when necessary.

## Create a database

In Settings, open **Databases → New Instance**. Choose the engine and version, enter a name, and click **Create Instance**. The default **Start after creating** option starts it immediately.

Morrow finds compatible existing binaries, including Homebrew, PATH, Herd, and Postgres.app installations. If the requested version is missing, creation handles its installation automatically. Port conflicts and duplicate names are rejected before downloading or initializing data.

The equivalent terminal command is:

```sh
./build/morrow db create postgresql my-app --version 17 --start
./build/morrow db list
```

## Install the morrow command

Open **Settings → General → Command Line → Install CLI**, or run:

```sh
./scripts/install-cli.sh
```

Add your local bin directory to PATH in `~/.zshrc` if needed:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Open a new terminal and run `morrow --help`. An existing command at the destination is preserved rather than silently overwritten.

## Connect your application

```sh
morrow db connection my-app
```

Copy the returned address into your application’s database settings. For PostgreSQL, a typical address is `postgresql://postgres@127.0.0.1:5432/postgres`. The selected port may differ if the default was already occupied.

> This preview is for local development. Instances bind to 127.0.0.1 and use passwordless local accounts. Remote hosting and authenticated instance configuration are planned separately.

## Manage development runtimes

Open **Settings → Applications** to select PHP, Go, Flutter, Node.js, Python, or Ruby. Existing versions are reused; missing channels use Homebrew. See [Applications and runtimes](/docs/applications) for Terminal setup and companion commands.

## Set up another Mac

Open **Settings → General → iCloud Sync** and choose a folder inside iCloud Drive on both Macs. Enable automatic setup on the Mac that should install missing services. Read [iCloud workspace sync](/docs/icloud-sync) for setup, data boundaries, and retry controls.

## Host local projects

Open **Settings → Sites → Project Directories** to park PHP/static project folders. Use `morrow site link --port 3000` from another web project’s folder to route its development server. Read [Sites and project directories](/docs/sites) for local DNS, suffix selection, and HTTPS setup.
