---
title: Getting started
description: Download Morrow, set up your workspace, and create your first local database.
group: Start here
order: 1
---
Morrow is a native macOS menu bar app and CLI. Both use the same databases, development runtimes, settings, and data folders. This developer preview supports Apple silicon (M-series) Macs running macOS 14 and later.

<div class="download-callout">
<h2>Download Morrow for macOS</h2>
<p>The signed, Apple-notarized app is ready to use. No Xcode or Homebrew required.</p>
<p><a class="button" href="{{downloadUrl}}">Download for macOS — v{{version}}</a></p>
<p>Apple silicon · macOS 14 or later · <a href="{{releaseUrl}}">Release notes and checksums</a></p>
</div>

## Install the app

1. [Download the latest signed app]({{downloadUrl}}) and open the ZIP archive.
2. Move **Morrow.app** into your **Applications** folder.
3. Open Morrow from Applications. Its icon appears in your menu bar.
4. Follow the setup assistant, or choose **Finish Later** to configure optional features when you need them.

The app includes its CLI. Database servers and runtimes download only when needed, with no package manager required. Compatible existing installations can also be reused. See [Binary downloads](/docs/binary-downloads) for details.

Morrow supports Apple silicon Macs running macOS 14 or later. Some runtimes need a newer system; selectors filter incompatible packages. Building the application yourself is optional—see [Contributing](/docs/contributing#build-and-verify) for source-build instructions.

## First-launch setup

New workspaces open a setup assistant. Choose launch at login, the optional `morrow` command, and local project domains. Existing workspaces keep their settings and are not forced through onboarding. Reopen the assistant from **General → Open Setup Assistant**.

Choose **Allow Morrow Setup** to review a native in-app explanation, then continue to macOS approval. Local domains require one-time approval for **Morrow** in macOS **System Settings → General → Login Items & Extensions**. The native helper handles only local DNS and standard-port setup; no sudo password is stored. Database and runtime management work without that helper. You can finish later and enable local domains when needed.

## Settings and app updates

Settings uses one fixed-size window with native macOS window controls. Each page keeps its title above the scrolling content, with soft translucent backdrops at the header and bottom edge. Cards share the same warm-gray surface and text gutters in light and dark appearances. Buttons, action icons, and menus use native Liquid Glass on macOS 26 and later, with standard native controls on macOS 14 and 15. macOS supplies their borders, corners, focus feedback, and accessibility appearance. Compact cards keep consistent text gutters, and short preference lists use native segmented controls. The edge fades remain in place as content scrolls beneath them, so no delayed shadow appears or disappears. They introduce no animation, including with Reduce Motion enabled.

**General** groups startup permissions, Appearance, Menu Bar, Command Line, and iCloud Sync. Choose **System**, **Light**, or **Dark** from the visible theme choices. **About** contains app update controls and links to documentation, source code, and issue reporting.

In signed releases, choose **About → Check for Updates…**, or enable **Automatically check for updates**. Morrow uses Sparkle's native update window and verifies downloaded updates before installation. Updating the menu bar app does not upgrade your databases or runtimes. Development builds keep their local version and disable app updates. Builds predating the updater need one manual installation of a current signed release from [GitHub Releases](https://github.com/kkz6/Morrow/releases/latest).

## Create a database

**General → Background access** displays the native helper's current permission. Morrow refreshes it when returning from System Settings and while monitoring, so an already allowed helper is not shown as needing approval. Approval and successful routing are separate checks; a helper can be allowed while local domains still need setup.

In Settings, open **Databases → New Instance**. Choose the engine and version, enter a name, and click **Create Instance**. The default **Start after creating** option starts it immediately.

Morrow finds compatible existing binaries, including Homebrew, PATH, Herd, and Postgres.app installations. If the requested version is missing, creation downloads a compatible catalog distribution. If a release is not published, use an existing installation or choose a published version. Port conflicts and duplicate names are rejected before downloading or initializing data.

After installing the optional CLI below, the equivalent terminal command is:

```sh
morrow db create postgresql my-app --version 17 --start
morrow db list
```

## Install the morrow command

Open **Settings → General → Command Line → Install CLI**. Morrow links the command bundled in your installed app; no source checkout is needed.

Add your local bin directory to PATH in `~/.zshrc` if needed:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Open a new terminal and run `morrow --help`. An existing command at the destination is preserved rather than silently overwritten.

## Connect your application

```sh
morrow db connection my-app
```

Copy the returned address into your application’s database settings. For PostgreSQL, a typical address is `postgresql://postgres@127.0.0.1:5432/postgres`. The selected port may differ if the default was already occupied.

> This preview is for local development. Instances bind to 127.0.0.1 and use passwordless local accounts. Remote hosting and authenticated instance configuration are planned separately.

## Manage development runtimes

Open **Settings → Runtimes** to select PHP, Go, Flutter, Node.js, Python, or Ruby. Existing versions are reused. Morrow handles downloads automatically: Node and other missing releases use its bundled distribution source; Go can also use official archives. Installation and updates use complete native packages. Installation discovery is cached rather than repeated on each navigation. See [Applications and runtimes](/docs/applications) for Terminal setup and companion commands.

## Set up another Mac

Open **Settings → General → iCloud Sync** and choose a folder inside iCloud Drive on both Macs. Enable automatic setup on the Mac that should install missing services. Read [iCloud workspace sync](/docs/icloud-sync) for setup, data boundaries, and retry controls.

## Host local projects

Use the **+** menu beside **Settings → Sites → Projects**, then **Project Directories** to park PHP/static project folders. Use `morrow site link --port 3000` from another web project’s folder to route its development server. Read [Sites and project directories](/docs/sites) for local DNS, suffix selection, and HTTPS setup.

## Add local S3 storage

Open **Settings → Object Storage → Create S3 Server** to run MinIO and configure buckets. The equivalent CLI command is `morrow storage create local-s3 --start`. Read [Local S3 storage](/docs/object-storage) for application settings and credential access.

## Find your preferences and logs

General is a single scrollable page with grouped headings for appearance, menu bar, command line, and iCloud sync. Shared cards and controls use subtle neutral surfaces that adapt to light and dark appearance. Service cards provide their own logs and configuration actions. The sidebar groups Projects, Services, and App for navigation; it has no separate Logs item.
