---
title: Sites and project directories
description: Park PHP projects, link app ports to folder domains, and enable local HTTPS.
group: Everyday use
order: 4.6
---
## Project directories

Open **Settings → Sites → Project Directories** and add a parent directory. Its immediate child folders become project domains:

```text
~/Projects/shop       → shop.test
~/Projects/dashboard  → dashboard.test
```

Enable or pause each directory with its toggle. Removing a parked directory removes its automatically discovered routes and preserves project files. Paused directories retain their project settings. Explicit links remain independent of directory parking.

```sh
morrow site park "$HOME/Projects"
morrow site directories
morrow site directory "$HOME/Projects" off
morrow site directory "$HOME/Projects" on
morrow site unpark "$HOME/Projects"
```

Folder names are converted to lowercase DNS labels; spaces and unsupported characters become hyphens. Duplicate domains across directories show a conflict instead of silently choosing a project. Use **Project Settings** to choose a unique hostname. Hidden folders, `node_modules`, `vendor`, `build`, and `dist` are skipped during automatic discovery.

## Start hosting

Click **Start** in Sites, or:

```sh
morrow site start
morrow site stop
morrow site refresh
morrow site list
```

Morrow installs missing Caddy and dnsmasq binaries using Homebrew and manages separate user-owned launchd jobs. PHP projects use complete PHP-FPM installations; choose a default in Sites or a per-project version in **Project Settings**.

```sh
morrow site php
morrow site php 8.4
morrow site php --install
```

The install option reuses a complete PHP-FPM installation or installs Homebrew's current PHP. A standalone PHP CLI without PHP-FPM is not sufficient for web hosting. This choice is separate from your ordinary CLI runtime default.

The directory watcher continues when the menu bar app closes. Changes are checked approximately every three seconds while hosting is enabled. Start-at-login can be changed in **Hosting Settings**. `morrow site watch` also runs the watcher in the foreground while hosting is enabled.

## PHP and static roots

Laravel projects use `public` as their document root. Other PHP projects are detected by an `index.php` in the root or `public` directory. Static sites use a detected `public` directory or their folder root. Change the root in **Project Settings**; it must remain inside the project folder.

Package-based Node projects and Go projects are detected as application servers and wait for a linked port. Morrow does not serve their source folders as static websites automatically. Static mode blocks PHP source and common private project files; Caddy also handles PHP through its FastCGI handler when PHP mode is selected. This is local development hosting, not a sandbox for untrusted project code.

## Link an app port from its folder

A project can register a development server without Morrow owning that process:

```sh
cd "$HOME/Projects/dashboard"
morrow site link --port 3000
```

This creates `dashboard.test → 127.0.0.1:3000`. The command works for Node, Go, Python, Rust, Java, or any HTTP application. Keep starting the application with its own development command.

For a Nuxt project whose dev script already invokes Nuxt:

```json
{
  "scripts": {
    "predev": "morrow site link --port 3000",
    "dev": "nuxt dev --host 127.0.0.1 --port 3000"
  }
}
```

Run the one-time hosting setup first, then `npm run dev`. A Go project can similarly run `morrow site link --port 8081` before its own startup command. Apps must actually listen on the specified port; setting a port in Morrow does not change the application's configuration.

```sh
morrow site link /path/to/project --port 4100 --domain dashboard.test --https
morrow site unlink dashboard.test
```

A domain without dots is placed under the current development suffix. Explicit links persist after the application's process exits, showing **Waiting for app** until its port opens again. Morrow does not start or stop these external app processes. WebSockets pass through Caddy; frameworks such as Vite may require the exact hostname and secure HMR settings in their dev-server configuration.

## Change the domain suffix

Open **Hosting Settings**, or:

```sh
morrow site configure --suffix morrow.test
```

Supported namespaces are `test`, `internal`, `localhost`, and their subdomains, such as `morrow.test`. Public domain suffixes and `.local` multicast DNS are intentionally outside this feature.

Automatically named routes change with the suffix. Explicit custom hostnames remain as entered; their previous namespace remains managed. New suffixes need system setup again. Changing a suffix creates matching local certificates for HTTPS sites.

## Clean URLs and system DNS

Services use unprivileged listener ports by default: HTTP 8080, HTTPS 8443, and DNS 5354. Before system setup, Morrow displays URLs with those ports. A hostname also needs working local DNS; an existing Herd resolver may already resolve `.test`, but Morrow does not overwrite it.

**Enable Local Domains** requests administrator authorization to install Morrow-owned resolver files and loopback forwarding. Stop another web server using 80/443 before enabling it. If Herd or Valet owns the selected resolver file, remove its configuration through that tool, or use another private suffix.

Current macOS resolver behavior requires special handling for a localhost DNS service on a nonstandard port. Morrow adds the dedicated loopback alias `192.0.2.53`, exposes DNS through port 53 on that alias, and forwards it to its user-owned DNS service. HTTP 80 and HTTPS 443 are forwarded to its private listeners. The rules occupy only the `com.apple/dev.morrow` PF subanchor; the main PF configuration is preserved.

A root-owned one-shot launchd job reapplies Morrow's alias and forwarding after a restart. PHP, DNS, the web server, and the watcher run as your user. Existing resolvers, unrelated web servers, network DNS settings, and project files are preserved. Pending setup is reported rather than counted as complete.

For CLI setup as an administrator, provide the settings you selected:

```sh
sudo morrow site setup --http-port 8080 --https-port 8443 --dns-port 5354 --suffixes test
```

With system setup complete, addresses become `http://shop.test` or `https://shop.test`, without explicit listener ports. Removing only Morrow's system integration:

```sh
sudo morrow site setup --remove
```

Stop Sites before changing listener ports, then rerun system setup with matching values. Linked app ports must differ from the proxy listeners.

## HTTPS on or off

Toggle HTTPS per project, or:

```sh
morrow site secure shop.test
morrow site unsecure shop.test
morrow site configure --https on
```

The global setting controls new sites. Caddy's internal CA issues and renews certificates for explicitly configured project hostnames. It does not request public certificates for these development domains.

Enable HTTPS on a site, start hosting, then choose **Trust Local HTTPS Certificate** or run:

```sh
morrow site trust
```

This installs the public root certificate into this user's login keychain trust settings and may prompt for authorization. Private CA keys remain in Morrow's local `web/caddy-data` directory and are not included in iCloud setup sync. Clients using separate trust stores may need to import the public root certificate separately. Turning off HTTPS changes the route back to HTTP; it does not remove the trusted CA.

## Logs and actual status

Sites reports live launchd PIDs and listener readiness. PHP projects also need their owned PHP-FPM process and socket; proxy projects need a listening upstream port. These checks indicate routing/runtime readiness, not an application-specific database or business-logic health check.

Use **View Routing Log** to open Caddy output in Morrow's searchable log viewer. Files live under `~/Library/Application Support/Morrow/web`; DNS, PHP-FPM, and watcher output have separate log files there.

```sh
morrow site logs shop.test
morrow site open shop.test
```

Site and parked-directory configuration is local in this first implementation; it is not yet part of the portable iCloud workspace blueprint.
