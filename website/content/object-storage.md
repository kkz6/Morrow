---
title: Local S3 storage
description: Run MinIO on your Mac, create buckets, and connect development apps.
group: Everyday use
order: 4.9
---
## Create a server

Open **Settings → Object Storage → Create S3 Server**. Choose a server name, S3 API port, console port, and startup options. Morrow reuses an existing MinIO executable or installs Homebrew's MinIO formula. The executable is pinned to its resolved installation path.

Both ports are validated before installation and again before startup. Database, mail, and hosting listeners also participate in port reservations. Defaults select free ports beginning at 9000. MinIO and its console listen on `127.0.0.1` and run through your user launchd session, independently of the menu bar app.

```sh
morrow storage create local-s3 --api-port 9000 --console-port 9001 --start
morrow storage list
morrow storage stop local-s3
morrow storage start local-s3
```

The API is normally `http://127.0.0.1:9000`; the console is normally `http://127.0.0.1:9001`. Use the displayed endpoints if you selected different ports. Settings and the CLI share the same saved server records. The running indicator requires an owned live process and a successful MinIO readiness response.

## Buckets and application settings

Start the server, then use **Create Bucket**. Bucket names use 3–63 lowercase letters, numbers, dots, or hyphens and must satisfy S3 naming rules. The bucket list is fetched when the server becomes available and can be refreshed manually.

```sh
morrow storage bucket local-s3 create uploads
morrow storage buckets local-s3
morrow storage config local-s3
```

**Copy App Settings** returns environment values including generated credentials, the endpoint, `AWS_DEFAULT_REGION=us-east-1`, and path-style access. The copy icon on a bucket includes that bucket's name. Adapt these values to your application's S3 SDK; `morrow storage config` uses a placeholder bucket name.

**Open Console** opens MinIO's browser interface. The settings icon exposes **Copy Access Key** and **Copy Secret Key** for login. The keys are generated once for each server and retained across restarts.

Deleting a bucket requires it to be empty; Morrow does not recursively delete objects. Use the console or an S3 client to manage object contents.

```sh
morrow storage bucket local-s3 delete uploads
morrow storage console local-s3
```

## Logs and configuration

The card's terminal icon opens the shared searchable log sheet. The menu bar also exposes start/stop, console, and logs for S3 servers.

```sh
morrow storage logs local-s3
morrow storage restart local-s3
morrow storage configure local-s3 --api-port 9010 --console-port 9011 --autostart on
```

Stop a server before changing its name, ports, or start-at-login preference. Changes preserve data and credentials.

## Data and removal

MinIO data, logs, and credentials live under:

```text
~/Library/Application Support/Morrow/object-storage/<server-id>
```

Credentials are stored in a private local file and private launchd plists with mode `0600`. They are not placed in shared state or the iCloud blueprint. S3 server records and objects are local to this Mac in this preview.

**Remove** stops the owned server and moves its complete directory into Morrow's `archives` directory, preserving objects and keys. It does not uninstall a shared MinIO binary.

```sh
morrow storage remove local-s3
```

This feature provides local S3-compatible development storage. Database backup delivery to S3, server software upgrades, and remote object-storage administration are separate future features.
