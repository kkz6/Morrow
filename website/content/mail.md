---
title: Local SMTP testing
description: Capture development email with a local SMTP server and Morrow’s native project inboxes.
group: Everyday use
order: 4.8
---
## Create a mail server

Open **Settings → Mail → Create Mail Server**. Choose a name, Mailpit version, SMTP port, and inbox port. Creation reuses a detected native binary or downloads a verified Mailpit distribution from the configured catalog. No package manager is required. Port conflicts and duplicate names are checked before installation.

The suggested ports begin at **1025** for SMTP and **8025** for the inbox. Each service has its own captured-message database. Multiple services can run on different ports; database and mail reservations share the same port validation.

Port labels use plain digits in every locale: `1025`, without a thousands separator.

```sh
morrow mail create local-mail --start
morrow mail list
morrow mail smtp local-mail
morrow mail inbox local-mail
```

Use `--smtp-port`, `--http-port`, `--version`, and `--autostart` when needed. Automatic selection reuses a detected installation. An exact version must already be installed or be published in the catalog. Missing versions must be published before they can be downloaded.

## Configure your app

| Setting | Value |
| --- | --- |
| SMTP host | `127.0.0.1` |
| SMTP port | The service's configured port; usually `1025` |
| Username/password | None |
| TLS/STARTTLS | Disabled for this local testing service |
| Inbox | The service's local HTTP URL; usually `http://127.0.0.1:8025/` |

Copy the app settings from **Settings → Mail → Copy Settings**, or:

```sh
morrow mail config local-mail
```

The generated environment settings work as a starting point for Laravel development:

```dotenv
MAIL_MAILER=smtp
MAIL_HOST=127.0.0.1
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_SCHEME=null
MAIL_ENCRYPTION=null
```

Use the actual SMTP port shown in Morrow if it differs. Restart your application or reload its cached configuration after changing its mail settings. Other frameworks use the same SMTP host/port with authentication and encryption disabled.

Mailpit captures messages for inspection rather than forwarding them to recipients. Morrow starts it with a clean environment, no SMTP relay configuration, persistent local storage, and loopback-only SMTP and HTTP bindings. It is a development mail catcher, not a public incoming/outgoing email service.

## Inbox and logs

Choose **Open Inbox** in Settings or use the menu-bar inbox button to open Morrow’s native inbox. Search messages, filter by project, read HTML or plain text, inspect headers and original MIME, save email attachments or `.eml` files, and delete individual messages. Messages refresh while the inbox is open. HTML previews block scripts and remote resources; explicit links open in your browser. Inline images remain available as downloadable attachments.

The browser inbox remains available through `morrow mail inbox <server>` and the server’s local URL.

### Project inboxes

Newly started supported Mailpit servers accept any local test username/password and automatically tag mail with the username. Select a site in the native inbox and choose **Copy SMTP Settings**, or run:

```sh
morrow mail config local-mail --project shop.test
```

Use `MAIL_USERNAME="shop.test"` and `MAIL_PASSWORD=morrow`, with the same loopback host, port, and disabled TLS. These are local routing labels, not account credentials. Messages without authentication still appear in All inboxes. Existing captured messages are not relabeled.

An already running server keeps its current settings. Morrow shows **Restart Mail** when project tagging is not enabled; this briefly restarts only that mail server and preserves its database. Older external Mailpit binaries lacking the tagging/authentication flags remain usable without project grouping; choose a current catalog release to enable it.

```sh
morrow mail messages local-mail --project shop.test --search "subject:Receipt" --json
morrow mail messages local-mail --offset 50
morrow mail message local-mail <message-id>
morrow mail message local-mail <message-id> --raw > message.eml
morrow mail delete-message local-mail <message-id>
```

Lists are paginated in groups of 50. Deletion names a specific message; an empty selection never clears the mailbox.

The card's **Logs** action opens the shared searchable log sheet directly. The same action is available in the menu bar. The red stop icon controls the owned mail process; the plain dot and status label report actual readiness.

```sh
morrow mail logs local-mail
```

Status checks the managed PID, SMTP greeting, and local HTTP response. The service is **Running** only when both endpoints are ready. It stays running when the Morrow app closes because launchd manages the foreground server.

## Lifecycle and settings

```sh
morrow mail stop local-mail
morrow mail configure local-mail --smtp-port 1026 --http-port 8026 --autostart on
morrow mail start local-mail
morrow mail restart local-mail
```

Stop the service before changing its name, ports, or launch-at-login settings. Native Mailpit executables are pinned to their detected paths. External package cleanup can remove an old executable; Morrow reports that version as missing and preserves messages. Mailpit binary upgrades with an existing message database are not automated in this preview; create another service to choose another detected/current version.

## Storage and removal

Captured messages and logs live under `~/Library/Application Support/Morrow/mail/<service-id>`. Removing a server archives its directory by default; shared Mailpit installations are preserved.

```sh
morrow mail remove local-mail
# Permanently discard this service's captured messages:
morrow mail remove local-mail --delete-messages
```

Mail server recipes participate in [iCloud workspace sync](/docs/icloud-sync). The other Mac gets its own empty inbox and free ports; captured messages and attachments are not uploaded through Morrow's setup sync.
