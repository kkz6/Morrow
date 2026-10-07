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

Install Homebrew or set its executable path in Settings → General. Compatible existing native binaries can still be reused without downloading another copy.

```sh
morrow doctor
```

## A database cannot start

Open Logs for that instance or run:

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

Real startup failures show a short excerpt from that attempt. Open **Logs** for the full server output. Older shutdown messages are not included in a new startup error.

## How service status is measured

Morrow locates the managed PID through launchd and checks whether that process is alive through the operating system. A live process is **Running** only after a readiness check succeeds; a live process without readiness is **Starting**. PostgreSQL uses `pg_isready` when included in the installation; MySQL and MariaDB use their native administration ping tools. Redis and Valkey use a protocol PING, and Memcached uses its VERSION command. MongoDB and installations without an administration client use process liveness plus TCP readiness, which confirms a listener rather than authenticated query health.

Service logs are diagnostics and are never interpreted as the current process status. Updates and the CLI use the same readiness rules as the menu bar and Settings. Status refreshes periodically; a process transition can occur between checks.
