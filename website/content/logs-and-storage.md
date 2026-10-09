---
title: Logs and local data
description: Open service logs directly and understand where your data lives.
group: Everyday use
order: 5
---
## Logs from each service

Click the terminal icon on a database, mail, S3, or site card. The same searchable viewer opens in a separate sheet without changing your selected settings page. Database, mail, and S3 services also expose logs in the menu bar. PHP-FPM logs are available on runtime cards after hosting has created them. DNS has a log icon in Sites.

There is no separate Logs item in the sidebar. The viewer supports case-insensitive search, copying displayed lines, manual refresh, and pausing live updates. Live mode checks for new output every second and follows the latest lines. It retains the latest 128 KB to remain responsive; file rotation and truncation reset the reader.

## Read logs from Terminal

```sh
morrow db logs my-app
morrow mail logs local-mail
morrow storage logs local-s3
morrow site logs shop.test
```

The CLI prints recent output, up to 32 KB. Log files remain on disk so output is available after closing or reopening the app.

## Local data and configuration

Morrow stores metadata, cached installation discovery, generated configuration, server output, and service data under:

```text
~/Library/Application Support/Morrow
```

Each database, mail, or S3 service has a UUID directory. Use a database card's **Open Data Folder** action to open its folder. Its configuration icon shows generated configuration; use the service's settings to change it. PHP runtime cards expose editable `php.ini` and additional `.ini` files. See [Applications and runtimes](/docs/applications) for details.

The app and CLI serialize metadata updates using locks and atomic writes; unreadable state is reported and preserved. Saved preferences and version discovery survive app restarts. **Object Storage** manages [local S3 servers and buckets](/docs/object-storage), rather than generic folder-opening buttons.

## Isolate development data

```sh
MORROW_HOME=/tmp/morrow-sandbox morrow db create redis test-cache --port 16379 --start
MORROW_HOME=/tmp/morrow-sandbox morrow db stop test-cache
MORROW_HOME=/tmp/morrow-sandbox morrow db remove test-cache --delete-data
```

`MORROW_HOME` redirects metadata, data, and login plist files. Stop managed processes before removing this directory. These remain real native processes in your user session.

## Mail and S3 data

Captured mail remains in each service's `mail/<service-id>/messages.db` file. See [Local SMTP testing](/docs/mail) for inbox and removal controls. S3 objects and private generated credentials remain in `object-storage/<server-id>`; server removal archives that directory.

Maintenance-update backups live in `backups/<instance-id>/<backup-id>`. Preserved instance folders and archives should not be treated as verified backups. Export/import, scheduled backups, and database backup delivery to S3 are future work.
