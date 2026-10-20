---
title: Database updates
description: Check maintenance releases, preserve backups, and recover interrupted updates.
group: Everyday use
order: 4.5
---
## Check versions

Open **Settings → Databases → Check Updates**. Morrow refreshes configured release metadata and compares each instance's pinned release with compatible catalog releases. Checks do not apply upgrades.

```sh
morrow db updates --refresh
morrow db updates my-app --json
```

`--refresh` reloads the catalog and provider caches. It never invokes a package manager. Without it, catalog checks reuse fresh cached metadata. A failed check is reported as a failure, never as “up to date.” External installations such as Herd and Postgres.app are updated through their original installer.

## Maintenance releases and rebuilds

Morrow compares numeric version components and packaging revisions for portable distributions. For example, `17.11` to `17.12` is a PostgreSQL maintenance update; `17.11` to `17.11_1` is a packaging rebuild. These numbers are examples, not a statement about the latest release.

PostgreSQL 10 and later stay within the same major release. Older PostgreSQL releases and the other supported engines conservatively stay within the same first two version components. Different release series require a new instance and an engine-supported migration. Morrow does not automatically migrate data between series.

## Apply an update

An existing external installation can show **Portable distribution available** when Morrow publishes the same engine version. The existing update action downloads that package, then uses the same backup and restart procedure to move this instance to its private installation. Publication itself never changes a running service. Downloads and binary validation finish before the service is stopped. External packages and their libraries remain on disk for other applications.

Choose **Update…** in an instance's action menu, review the backup and restart information, and choose **Back Up and Update**. The CLI equivalent is:

```sh
morrow db upgrade my-app
```

Morrow serializes the operation across the app and CLI, downloads and validates the managed distribution, stops its managed server, copies the instance directory into `backups`, and changes that instance's pinned path. An instance that was running is restarted and checked for readiness. A stopped instance stays stopped.

Other instances retain their pinned paths. Portable distributions include their required libraries and keep their previous directories. Morrow never modifies shared package-manager dependencies or removes external installations.

A filesystem backup requires exclusive access to the instance's files. Stop clients before updating. Linked data directories, symlinked files, and external tablespaces are rejected because an instance-directory copy would not cover them. Use the database's own backup and upgrade tools for those configurations. Review engine release notes for extension or application compatibility before updating.

## Recovery

If an update fails, Morrow attempts to restore the previous instance and restart it if necessary. The backup is retained; files produced by the failed upgrade are preserved separately. Existing external installations can still require their original libraries; Morrow preserves them during the transition.

An interrupted operation leaves a durable journal and blocks normal startup, removal, and configuration until recovery:

```sh
morrow db recover my-app
```

The instance's action menu also offers **Recover Interrupted Update…**. An update that finished successfully but was interrupted during final bookkeeping is finalized with its new version rather than restoring old data. Recovery restores the saved pre-update data, so writes made during a failed readiness check are not part of the restored database. If recovery cannot complete, its journal and files remain available and the error explains what needs attention.

Backups live under `~/Library/Application Support/Morrow/backups/<instance-id>/<backup-id>`. Find them in that directory with Finder. **Object Storage** manages local S3 services; it is not a backup-folder browser. Retention is manual in this preview; monitor disk space and keep independent backups for important data.
