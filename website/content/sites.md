---
title: Sites and project directories
description: Park PHP projects, link app ports to folder domains, and enable local HTTPS.
group: Everyday use
order: 4.6
---
## Project directories

Open **Settings → Sites**, then use the **+** menu beside **Projects → Project Directories** and add a parent directory. Its immediate child folders become project domains:

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

## Ignore folders for local hosting

For a folder that should not receive a local domain, open its project menu and choose **Ignore for .test hosting** (the label follows your configured suffix). Morrow keeps the project settings and folder, removes its route from the web server, and shows **Ignored for local hosting**. Directory refreshes retain this choice. Choose **Include in .test hosting** to restore it.

```sh
morrow site ignore dotfiles.test
morrow site include dotfiles.test
```

Ignoring never deletes the application folder. Removing a parked directory is a separate action that un-registers its discovered routes while preserving all folders.

## Start hosting

Click the play icon beside **Web server** in Sites, or:

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

Open the configuration icon beside **Web server** for **Hosting Settings**, or:

```sh
morrow site configure --suffix morrow.test
```

Supported namespaces are `test`, `internal`, `localhost`, and their subdomains, such as `morrow.test`. Public domain suffixes and `.local` multicast DNS are intentionally outside this feature.

Automatically named routes change with the suffix. Explicit custom hostnames remain as entered; their previous namespace remains managed. New suffixes need system setup again. Changing a suffix creates matching local certificates for HTTPS sites.

## Clean URLs and system DNS

Services use unprivileged listener ports by default: HTTP 8080, HTTPS 8443, and DNS 5354. Before system setup, Morrow displays URLs with those ports. A hostname also needs working local DNS. Setup preserves other resolvers unless you explicitly select replacement.

The **Local Domains** card shows routing and certificate status. **Set Up** starts hosting if needed, registers the native setup helper for one-time macOS approval for DNS and ports 80/443, and trusts the development CA when a project has HTTPS enabled. If approval is needed, **Approve Morrow** opens the macOS background-permission settings; setup resumes after approval. Once configured, the setup button disappears. Validation, gateway logs, and repair live in its **…** menu.

If a previous resolver remains after removing Herd/Valet, the primary action becomes **Replace Setup**. It explicitly backs up the previous resolver before replacing it. Stop any other web server using 80/443 first; Morrow still refuses to redirect an occupied web-server port. You can also choose another private suffix.

The CLI requires an explicit replacement option:

```sh
sudo morrow site setup --http-port 8080 --https-port 8443 --dns-port 5354 --suffixes test --replace-resolvers
```

Resolver backups are private root-owned JSON files in `/Library/Application Support/Morrow Network Backups`. They retain the original bytes and permissions. Removing Morrow routing restores a saved resolver only if that resolver still contains Morrow's configuration. Backups remain available afterward.

Morrow uses launchd socket activation for standard localhost ports. launchd opens HTTP 80, HTTPS 443, and TCP/UDP DNS 53 on `127.0.0.1`, then gives those sockets to a small gateway running as your Mac user. It forwards only to Morrow's private local listeners. PHP, DNS, Caddy, the gateway, and the directory watcher run without root privileges.

This setup does not install packet-filter rules, a VPN, or a network extension. Private domains and local connections are outside Private Relay's internet relay path. Migrating an older Morrow setup removes its PF anchor, releases only Morrow's PF token, and removes its dedicated DNS alias; other tools' filtering state is preserved. macOS may take a short time to refresh Private Relay's status.

Unrelated resolvers, web servers, network DNS settings, and project files are preserved. Resolver replacement only applies to the namespaces explicitly selected for setup. Pending setup is reported rather than counted as complete.

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

Enable HTTPS on a site, then choose **Set Up** or **Finish Setup** in **Local Domains**. Setup skips certificate changes when the CA is already trusted. Advanced users can still run:

```sh
morrow site trust
```

**Validate HTTPS** in the Local Domains **…** menu reports its result inside the card. Validation uses native certificate trust evaluation without launching a certificate application, opening a browser, changing the selected page, or adding a page-wide activity/error panel. Only explicit setup or certificate trust changes need system approval. The app no longer elevates through AppleScript or shell scripts.

```sh
morrow site check-https
```

After routing is configured, validation checks the normal project hostname and HTTPS port 443, including system DNS and forwarding. Before setup, it checks the private listener directly and explains the remaining setup step. HTTP redirects such as 302 still establish a working TLS connection; the check does not verify an application's business logic.

Before system routing is enabled, use the displayed address such as `https://shop.test:8443`. The default HTTPS switch applies only to new sites; existing projects have their own HTTPS toggles.

This installs the public root certificate into this user's login keychain trust settings and may prompt for authorization. Private CA keys remain in Morrow's local `web/caddy-data` directory and are not included in iCloud setup sync. Clients using separate trust stores may need to import the public root certificate separately. Turning off HTTPS changes the route back to HTTP; it does not remove the trusted CA.

## Logs and actual status

Sites reports live launchd PIDs and listener readiness. PHP projects also need their owned PHP-FPM process and socket; proxy projects need a listening upstream port. These checks indicate routing/runtime readiness, not an application-specific database or business-logic health check.

Use the project card's terminal icon or **View Routing Log** to open Caddy output in Morrow's searchable log viewer. Files live under `~/Library/Application Support/Morrow/web`; DNS, PHP-FPM, and watcher output have separate log files there.

```sh
morrow site logs shop.test
morrow site open shop.test
```

Site and parked-directory configuration is local in this first implementation; it is not yet part of the portable iCloud workspace blueprint.

## Native helper and release signing

The setup daemon is bundled with Morrow and registered through `SMAppService`. macOS retains its approval. It accepts only a private regular request file owned by the console user, validates the listener ports and private suffixes, and exposes no arbitrary command/path execution. Public setup results contain status, never credentials.

The gateway is copied to a root-protected application-support location and runs as the Mac user. It keeps working if the GUI app moves. The helper and gateway are distinct roles: only installation metadata and resolver changes use root privileges.

Customer builds must be Developer ID signed and notarized. Ad-hoc development builds can have additional macOS approval restrictions. See [Contributing](/docs/contributing) for release build inputs.
