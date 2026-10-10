---
title: Troubleshooting
description: Resolve port conflicts, missing binaries, and startup problems.
group: Reference
order: 7
---
## A port is already in use

Morrow validates a real loopback bind and also checks ports reserved by its configured instances. Choose another port or stop the process already using it.

```sh
morrow db create postgresql my-app --port 5433 --start
```

Do not stop another application’s service merely to make Morrow’s default port available.

## Homebrew is not found

Homebrew is optional and compatibility is off by default. Compatible existing native binaries can be reused. Configure a verified distribution catalog in **General → Binary Downloads**, use direct Go/nvm providers, or explicitly enable Homebrew compatibility and set its executable path. See [Binary downloads](/docs/binary-downloads).

## Duplicate background entries or stale permission status

**General → Background access** reads macOS permission status. Its menu opens permission settings or cleans obsolete Morrow registrations. `morrow background status` shows job permission status; `morrow background clean` performs the same cleanup.

Cleanup archives inactive orphan job files and updates retained job definitions to use Morrow attribution and its launcher. Running orphan processes are preserved and reported. Retained running jobs adopt revised definitions on their next normal restart; cleanup does not stop databases. macOS can retain historical list entries after the files are removed. Customer builds need consistent Developer ID signing for reliable grouping. Morrow never resets the whole background database or edits another app's registrations.

```sh
morrow doctor
```

## A database cannot start

Open the terminal icon on that instance's card or run:

```sh
morrow db logs my-app
```

A missing recorded version is shown as missing rather than silently substituted. Data remains preserved. The chosen release must include its native server and any required initialization tools.

## The CLI is not found

Install it from Settings → General → Command Line or `scripts/install-cli.sh`. Confirm `~/.local/bin` is on PATH, then open a new terminal.

An existing command under the same name is preserved. Choose a different location or remove the previous link intentionally before installing another copy.

## Xcode or SDK mismatch

The build scripts select a full Xcode, print its SDK version, and verify the final app binary records that SDK. `macOS 14` is the deployment minimum, not the compiler SDK selection.

For a custom installation, set the developer directory for that command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
```

## Developer preview distribution

Local builds are ad-hoc signed. Developer ID signing and notarization are still required for polished distribution to other Macs. The project currently documents source builds and CI artifacts rather than a notarized installer.

## Running after a startup error

Morrow parses launchd exit codes numerically. The `last exit code = (never exited)` placeholder means a new process has not exited, rather than a startup failure. Launching states remain **Starting** until the managed process listens on its configured port.

Real startup failures show a short excerpt from that attempt. Open the card's terminal icon for the full server output. Older shutdown messages are not included in a new startup error.

## How service status is measured

Morrow locates the managed PID through launchd and checks whether that process is alive through the operating system. A live process is **Running** only after a readiness check succeeds; a live process without readiness is **Starting**. PostgreSQL uses `pg_isready` when included in the installation; MySQL and MariaDB use their native administration ping tools. Redis and Valkey use a protocol PING, and Memcached uses its VERSION command. MongoDB and installations without an administration client use process liveness plus TCP readiness, which confirms a listener rather than authenticated query health.

Service logs are diagnostics and are never interpreted as the current process status. Updates and the CLI use the same readiness rules as the menu bar and Settings. Status refreshes periodically; a process transition can occur between checks.

## Local domains or HTTPS need setup

Enable HTTPS on the project card, then use **Local Domains → Set Up** or **Finish Setup**. Morrow combines hosting, DNS/80/443 routing, and development CA trust into that action. Once ready, its **…** menu contains **Validate HTTPS** and repair controls.

Validation stays in the current window and reports inline. It uses native certificate trust evaluation and does not launch certificate tools or a browser. Setup asks for native approval of Morrow in Login Items & Extensions; explicit certificate trust may also request macOS authorization. The app does not use script-based administrator prompts.

If a resolver remains after removing Herd or Valet, **Replace Setup** backs it up and replaces only the selected namespace. Port conflicts still require stopping the other web server. Backups remain under `/Library/Application Support/Morrow Network Backups`; `sudo morrow site setup --remove` restores one when the resolver still belongs to Morrow.

Without system routing, URLs include the listener port (normally 8443). After setup, HTTP uses 80 and HTTPS uses 443. See [Sites](/docs/sites) for the CLI replacement flag and setup sequence.

## Installed versions look stale

Discovery results persist across navigation and app restarts. Use the refresh icon in Runtimes to rescan installations and available releases. Starting the app with a missing or day-old inventory also refreshes installations. A saved version does not guarantee its executable remains present after an external package cleanup; Morrow validates it before use.

## Private Relay reports incompatible software

Earlier Morrow builds used custom PF rules for localhost forwarding. Apple documents custom packet filters as a possible reason Private Relay becomes unavailable. Current setup uses a socket-activated localhost gateway instead.

Use **Local Domains → … → Repair Local Domains** to migrate an old setup. It removes Morrow's rules and releases its PF reference without disabling filtering owned by other tools. Private Relay's status can take a little time to refresh; if the alert remains, check other VPN/filtering software. Morrow does not change your Private Relay preference.

See [Apple's guidance](https://support.apple.com/en-au/102022) for the system-settings incompatibility alert.

## Setup helper needs approval

Choose **Approve Morrow** in Local Domains or the setup assistant. In **System Settings → General → Login Items & Extensions**, allow Morrow's helper. Return to Morrow; it checks the saved setup request and resumes. If a development build is rejected, use the complete app bundle and check its signing. Customer distribution requires Developer ID signing and notarization. In the ad-hoc development preview, macOS can list the helper as **morrow** because it has no Developer Team ID.

## Several Morrow-related background rows

macOS may list legacy `morrow`, `mysqld`, or `php-fpm` jobs separately. New job definitions attribute managed workers to Morrow and use its signed foreground runner. Correct customer grouping requires the app and CLI to share a Developer Team ID. The current ad-hoc preview can still appear as `morrow`; old records may remain until macOS updates them. Morrow does not alter the system's background-task database.
