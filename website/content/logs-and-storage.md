---
title: Logs and storage
description: Follow server output in the app and understand where your data lives.
group: Everyday use
order: 5
---
## Logs inside Morrow

Open **Settings → Logs** and choose an instance. You can also use **View Logs** from its menu or the terminal icon in the menu bar.

The viewer supports case-insensitive search, copying displayed lines, manual refresh, and pausing live updates. Live mode checks for new output every second and follows the latest lines. It retains the latest 128 KB to remain responsive; file rotation and truncation reset the reader.

## Read logs from Terminal

```sh
morrow db logs my-app
```

The CLI prints the latest server output, up to 32 KB. Log files remain on disk so output is available after closing or reopening the app.

## Data location

Morrow stores metadata, generated configuration, server output, and per-instance data under:

```text
~/Library/Application Support/Morrow
```

Each instance has a UUID directory. Settings → Storage opens the root folder and individual instance folders. The app and CLI serialize metadata updates using locks and atomic writes; unreadable state is reported and preserved.

## Isolate development data

```sh
MORROW_HOME=/tmp/morrow-sandbox morrow db create redis test-cache --port 16379 --start
MORROW_HOME=/tmp/morrow-sandbox morrow db stop test-cache
MORROW_HOME=/tmp/morrow-sandbox morrow db remove test-cache --delete-data
```

`MORROW_HOME` redirects metadata, data, and login plist files. Stop managed processes before removing this directory. These remain real native processes in your user session.

## Planned backups

Export/import, verified database backups, and S3-compatible backup storage are planned. Preserved instance folders should not be treated as backup verification.

## Mail server output

Mailpit servers appear alongside database instances in the in-app log selector. Captured messages remain in each service’s local `mail/<service-id>/messages.db` file. See [Local SMTP testing](/docs/mail) for inbox and removal controls.
