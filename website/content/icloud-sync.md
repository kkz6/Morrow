---
title: iCloud workspace sync
description: Restore database setup and runtime choices on another Mac using iCloud Drive.
group: Everyday use
order: 4.9
---
## Enable on each Mac

Open **Settings → General → iCloud Sync**, choose a folder inside iCloud Drive, and enable **Sync workspace with iCloud Drive**. The default is **iCloud Drive/Morrow**. Use the corresponding folder on your other Mac and enable sync there too.

Enable **Set up missing services automatically** on a Mac that should recreate the shared setup with native installers (nvm for Node, Homebrew for other missing software). This switch covers missing Node versions too. This permission is local to each Mac and is off by default. Morrow checks the folder approximately every 30 seconds while the app is running and idle. **Sync and Retry Setup** starts a check immediately and retries unresolved recipes.

This developer preview uses a user-accessible iCloud Drive folder, with coordinated file access. It does not depend on CloudKit or an app-specific iCloud entitlement, and works with the shared CLI. Apple handles the folder's delivery between devices; Morrow's status confirms local file reconciliation, not completion of Apple's upload or another Mac's download. For a different folder, make sure it is actually inside iCloud Drive.

## What travels between Macs

The workspace blueprint contains:

- Mailpit server names, version choices, SMTP/inbox ports, and launch-at-login choices.
- Database names, engine and release series, preferred ports, memory and connection limits, and launch-at-login choices.
- Registered runtime release series and selected defaults for PHP, Go, Flutter, Node.js, Python, and Ruby.
- Appearance and menu-bar count preferences.

Database contents, captured mail/attachments, logs, credentials, executable paths, Homebrew paths, process status, and machine-specific sync preferences remain local. MinIO server records, objects, and credentials are also local and are not yet included in the blueprint. A synced database recipe creates a new, empty instance on another Mac; it does not copy its data or open connections.

## Automatic setup

When enabled, Morrow verifies existing installations and reuses a compatible release series before downloading. Missing Node versions are installed through nvm; other missing versions use Homebrew, with the same validation as normal creation. A historical patch that is unavailable may be recreated using an available patch in the same series. The setup report shows the version actually used.

A new database or mail service starts stopped. Its launch-at-login choice is retained. If its preferred port is occupied, Morrow chooses the next available engine port and reports it. Existing instances keep their machine's local port and data. Settings changes require stopping a running instance; a different engine or release series is reported for local review rather than automatically migrated.

A local removal is remembered on that Mac so subsequent sync checks do not immediately recreate the removed selection. Remote deletions do not remove local data or uninstall shared packages. Recipes remain in the shared setup for other machines; removing recipes from the shared setup is not a preview feature.

Mailpit setup is recreated using a detected compatible version or a current available release in the same major series. The report shows the version installed and the machine’s ports.

## Conflicts and retries

Each Mac publishes a separate snapshot file under `devices`. Revisions give delivered snapshots a deterministic order. On publication, Morrow keeps additions from the delivered cloud setup and gives that Mac's local settings and defaults precedence. Simultaneous edits to the same preference or service are not merged field by field; the selected snapshot wins. This preview does not promise real-time synchronization or a distributed transactional merge.

Unavailable Homebrew channels, missing Homebrew, port/configuration problems, and running-instance settings conflicts are listed under **Sync Status**. One failure does not stop unrelated recipes from being restored. Failed recipes are not downloaded repeatedly on every timer tick: use **Sync and Retry Setup** after resolving the problem, or deliver a changed blueprint.

If iCloud has not downloaded a snapshot, Morrow waits and reports that settings are downloading. Use Finder to download the selected folder if needed. Disabling sync leaves local services and existing cloud files intact.

## CLI

```sh
morrow sync enable --auto-install
morrow sync now
morrow sync status
morrow sync now --retry --json
morrow sync disable
```

For an explicitly chosen folder:

```sh
morrow sync enable --folder "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Morrow" --auto-install
```

The CLI reconciles once per `sync now` invocation. Keep the macOS app open for periodic checks. Homebrew is required for missing database, mail, and non-Node runtime software; Node uses nvm. iCloud Drive must be enabled and the chosen folder available on both Macs. Automatic setup can download large SDKs, especially Flutter.
