---
title: Managing instances
description: Start, stop, configure, and remove local databases from either interface.
group: Everyday use
order: 3
---
An instance represents a database server and its own data. The app and CLI show the same managed instances.

## Create and start

```sh
morrow db create postgresql my-app --version 17 --port 5433 --start
```

Creation checks the name, limits, and port before installing software. Existing compatible binaries are reused. Missing releases are installed and verified before initializing the instance’s data.

Without `--port`, Morrow chooses an available port starting at the engine’s default. A stopped instance still reserves its configured port. External listeners are checked with a real socket bind, and availability is checked again after installation and on startup.

## Control a server

```sh
morrow db start my-app
morrow db stop my-app
morrow db restart my-app
morrow db list --json
```

The menu bar offers start and stop controls. Settings shows status, connection addresses, and instance settings. Databases continue running when the menu bar app quits because macOS launchd owns their processes.

## Configure a stopped instance

```sh
morrow db stop my-app
morrow db configure my-app --port 5434 --memory 256 --connections 150
morrow db start my-app
```

You can change its name, port, memory limit where supported, and maximum connections where supported. Both interfaces use the same validation.

## Start at login

```sh
morrow db autostart my-app on
morrow db autostart my-app off
```

Morrow creates a LaunchAgent for that instance. Manually stopping a configured instance keeps it stopped until you start it or log in again. Turning off this setting removes its login job.

## Remove an instance

```sh
morrow db remove my-app
```

Removal stops the managed process and archives its data by default. To permanently delete its files, explicitly use:

```sh
morrow db remove my-app --delete-data
```

The app offers these two choices in a confirmation dialog. Removed data archives are folders, not verified database backups.
