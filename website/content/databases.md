---
title: Supported databases
description: Choose a native database engine and keep project data separate.
group: Start here
order: 2
---
Select the database and version directly while creating an instance. Each instance has its own port, settings, and data folder.

## Available engines

| Engine | CLI name | Default port | Local account |
| --- | --- | --- | --- |
| PostgreSQL | postgresql | 5432 | postgres |
| MySQL | mysql | 3306 | root |
| MariaDB | mariadb | 3306 | root |
| MongoDB | mongodb | 27017 | Authentication disabled |
| Redis | redis | 6379 | No password |
| Valkey | valkey | 6379 | No password |
| Memcached | memcached | 11211 | No authentication |

The CLI also accepts `postgres`, `pg`, and `pgsql` for PostgreSQL, and `mongo` for MongoDB.

## SQL databases

```sh
morrow db create postgresql local-pg --version 17 --start
morrow db create mysql local-mysql --version 8.4 --start
morrow db create mariadb local-maria --version 11.8 --start
```

PostgreSQL supports shared-buffer and maximum-connection settings. MySQL and MariaDB support a maximum-connection limit. Changes to an existing instance require it to be stopped.

## Documents and caches

```sh
morrow db create mongodb local-mongo --version 8.0 --start
morrow db create redis local-cache --start
morrow db create valkey local-valkey --start
morrow db create memcached local-memcached --memory 64 --start
```

MongoDB uses its official Homebrew tap when installation is needed. Redis and Valkey use separate persistent data directories with append-only persistence. Memcached is volatile: stopping its process clears cached contents, and UDP is disabled.

## Developer preview coverage

PostgreSQL, Redis, and reuse of Herd’s MariaDB have been exercised with real native processes. All providers have configuration checks; MySQL, MongoDB, Valkey, and Memcached still need complete live lifecycle coverage.

RabbitMQ, further database providers, backups, and language runtimes are planned capabilities. They are not exposed as completed features in the app.

## Engine icons

Redis and Valkey use their vendor brand marks in instance rows, the menu bar, and creation selectors. The marks are bundled as transparent vector assets and remain sharp in light and dark appearances.

Each database card provides a shared live status indicator, red stop/play controls, a terminal icon for its log sheet, and a configuration icon to inspect generated settings. Change values using the service settings rather than editing the generated file.
