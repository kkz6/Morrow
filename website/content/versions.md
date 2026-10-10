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

With no `--version`, Morrow reuses an available compatible server. If none is present, it downloads a compatible release from the configured catalog. A package without a published distribution requires an existing installation or explicit Homebrew compatibility.

## Choose a release series

```sh
morrow db create postgresql legacy-app --version 16 --start
morrow db create postgresql new-app --version 17 --start
```

The selected release series follows published catalog releases. Optional Homebrew compatibility adds formula channels such as `postgresql@17` or `mysql@8.4`. An existing binary in the requested series is reused; a different major release is not silently substituted.

Each instance stores its exact executable path and patch version. These two PostgreSQL instances keep separate data and ports.

## Detect an existing server

Morrow checks managed distribution receipts, existing Homebrew kegs, server binaries on PATH, Herd service directories, and Postgres.app. It reads the executable’s reported version and checks the initialization tools needed to create separate data.

A MariaDB binary exposed under a MySQL compatibility name is classified as MariaDB. Client-only tools such as `psql`, `mysql`, or `mongosh` do not count as a complete server installation.

```sh
morrow db versions
morrow db channels postgresql
morrow doctor
```

## Upgrade data deliberately

Ordinary instance settings cannot change its executable. Compatible maintenance releases have an explicit [backup and update workflow](/docs/updates). For another release series, create a new instance and migrate data using the database’s supported tools. Automated migration between series is planned.

External Homebrew cleanup may remove a recorded executable. Morrow reports a missing version and preserves the data. Historical patches must be published in the configured catalog. Uninstalling shared native packages is not implemented.

## Advanced binary preparation

For scripts that explicitly want to prepare software without creating data, the CLI retains an advanced command:

```sh
morrow db install postgresql 17
```

The normal workflow remains `db create`; it already handles this preparation when needed.
