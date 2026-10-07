---
title: Versions and detection
description: How Morrow selects native binaries and avoids duplicate installations.
group: Everyday use
order: 4
---
Version selection is part of creating an instance. There is no separate installation step in the app.

## Automatic selection

```sh
morrow db create redis local-cache --start
```

With no `--version`, Morrow reuses an available compatible server. If none is present, it installs the current Homebrew channel.

## Choose a release series

```sh
morrow db create postgresql legacy-app --version 16 --start
morrow db create postgresql new-app --version 17 --start
```

The selected release series follows available Homebrew formulae, such as `postgresql@17` or `mysql@8.4`. An existing binary in the requested series is reused; a different major release is not silently substituted.

Each instance stores its exact executable path and patch version. These two PostgreSQL instances keep separate data and ports.

## Detect an existing server

Morrow checks Homebrew kegs, server binaries on PATH, Herd service directories, and Postgres.app. It reads the executable’s reported version and checks the initialization tools needed to create separate data.

A MariaDB binary exposed under a MySQL compatibility name is classified as MariaDB. Client-only tools such as `psql`, `mysql`, or `mongosh` do not count as a complete server installation.

```sh
morrow db versions
morrow db channels postgresql
morrow doctor
```

## Upgrade data deliberately

Changing the executable of an existing instance is rejected. Create a new instance with the desired release, then migrate data using the database’s supported tools. Automated migration is planned.

External Homebrew cleanup may remove a recorded executable. Morrow reports a missing version and preserves the data. Arbitrary historical patch downloads and uninstalling shared native packages are not implemented.

## Advanced binary preparation

For scripts that explicitly want to prepare software without creating data, the CLI retains an advanced command:

```sh
morrow db install postgresql 17
```

The normal workflow remains `db create`; it already handles this preparation when needed.
