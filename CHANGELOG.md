# Changelog

## Unreleased

- Accelerated large distribution publication with multipart uploads and bounded parallel public byte-range verification, retaining complete SHA-256 verification and conditional catalog writes.

- Focused new app and binary releases on Apple silicon. Distribution recipes, signing jobs, publication, and the active catalog use arm64 only; existing Intel archive URLs remain available and running services are not changed.

- Omitted Flutter's optional Pub preload archives containing unsigned example binaries while preserving SDK resources and dependency license notices. Pub retrieves original dependencies when needed; notarization failures retain Apple's detailed reports.

- Preserved bundled SDK framework identities and sealed native macOS framework signatures after relocation, retaining upstream signatures for other target platforms.

- Removed the app's remaining Homebrew availability trigger and obsolete shared-dependency warning. Update explanations follow portable download/validation before backup and restart; deprecated CLI help only advertises clearing the old preference.

- Recorded Flutter 3.47.7's macOS 15 requirement from its bundled native iPhone tools. Older Macs do not receive an incompatible SDK; Morrow's own macOS 14 minimum is unchanged.

- Published complete native distributions for every supported database, runtime, mail, web/DNS, and object-storage family on Apple silicon. Contabo serves 23 releases across 17 families, with pinned provenance, bundled dependencies, and corresponding source archives where applicable. Existing services are preserved until an explicit transition.

- Added explicit transitions from existing external installations to same-version portable packages through the normal update actions. Database downloads and validation finish before the existing backup/restart procedure begins; runtime defaults can switch while folder pins and external files remain preserved.

- Removed Homebrew installation, metadata refresh, and update execution from shared app/CLI management. Existing installations are discovered without executing or requiring the Homebrew command; legacy compatibility settings cannot re-enable it. Catalog-only updates and iCloud restoration preserve existing data and services.

- Added native build and relocation pipelines for the remaining database engines, Python, Ruby, Flutter, Go, and MinIO, with native Apple silicon jobs, complete package resources, pinned source dependencies, and signing/notarization.
- Added source builds for current PHP 8.3/8.4/8.5 with CLI/FPM, bundled static libraries, version-specific configuration, and trusted certificate bundles. Existing MySQL 26.7 installations have a matching portable release series.

- Node installation, channels, same-series updates, folder selections, and iCloud restoration now use complete hosted distributions with npm/npx. Latest LTS uses explicit catalog metadata and reuses an existing exact matching version before downloading. Existing nvm installations remain usable without bootstrapping nvm, requiring Git, or changing external aliases. Old nvm channel caches refresh automatically while installed inventory is retained.

- Added reproducible distribution recipes and a signed GitHub Actions workflow for complete Node 22/24 LTS, Caddy, Mailpit, and DNS-only dnsmasq packages on Apple silicon. Packages include pinned sources, license notices, dependency/architecture checks, and Apple notarization before Contabo publication.

- Added hosted PHP 8.0.30 CLI/FPM distributions for Apple silicon, with pinned source archives, signing, notarization, license notices, and PHP web extensions. PHP 8.0 can be installed or assigned to a folder without Homebrew or changing the global default.
- Added a signed PHP distribution workflow in GitHub Actions that shares the existing release credentials and returns notarized archives for publication through the local storage profile.
- Fixed conditional catalog updates with Contabo/Ceph ETag formatting, retaining concurrent-write protection and credential-safe publication errors.
- Managed PHP commands, PHP-FPM, and configuration access now share version-specific INI paths. Runtime refresh explicitly reloads hosted catalog metadata, and hosted version selectors hide provider identifiers.

- Removed binary-source and Homebrew-location controls from General; service creation and runtime installation handle sourcing automatically, with advanced overrides retained in the CLI.
- Removed HTTPS enabled/disabled/ready notifications. Project switches and padlocks show the setting directly, with amber tooltips for attention and quiet connection verification; failures remain actionable.

- Replaced floating HUDs with small contextual cards above the related settings page or active sheet, using the shared cell surface, padding, status icon, and action styles. Async feedback stays with its originating page; visibility timers pause while hidden or hovered. The menu dropdown remains notification-free.
- Setup permission reminders now stay in General and Sites until native permission is restored, with approval and missing registration handled separately.

- Added Folder Versions for PHP, Node.js, Go, Flutter, Python, and Ruby, with a folder picker in Runtimes and Project Settings, persistent exact selections, closest-parent inheritance, and automatic reuse/installation under the existing provider policy.
- Morrow's CLI and runtime wrappers now resolve versions from the working folder. PHP hosting shares the folder selection; global defaults and nvm's default alias remain unchanged. Added project use/list/show/clear commands and an optional working folder for tool exec.

- Centered toast feedback as a compact macOS HUD with native action buttons, removed notifications from the menu dropdown, and bounded menu sizing so overlays cannot expand it across the screen.

- Replaced the low-contrast bottom toast with shared HUD feedback: an opaque charcoal surface, readable text, status icon, close control, and optional action. Success notices last longer and pause on hover; errors stay until dismissed. Reduce Motion, Increased Contrast, and VoiceOver are supported.
- Project HTTPS confirmations now show the exact URL and Open Site action, verify the selected route before reporting it ready, and distinguish certificate setup from a working connection. Added CLI route renaming and optional per-domain HTTPS validation.

- Migrated the production setup helper to a distinct native identity, retaining the old helper only for scoped unregistration. Native approval-denied errors now lead to the Morrow approval explanation and Login Items settings instead of a generic failure with no prompt.

- Signed app cleanup now refreshes an older native setup-helper registration before repairing gateway association. It retains pending domain setup, requests macOS approval only when needed, and leaves database, mail, PHP, DNS, and web server jobs running. Standard app/CLI CI also uses Xcode 27.

- Added a dedicated Xcode 27 release workflow with Developer ID signing, Apple notarization, ticket stapling, checksum packaging, and temporary-keychain cleanup. Development builds remain available without release credentials.
- Added a bundled default binary catalog shared by the app and its CLI, with custom-source overrides and effective-source reporting.
- Added a Contabo/S3 publishing tool using a local AWS CLI profile, immutable archive keys, public checksum verification, and conditional catalog updates. Customer downloads require no storage credentials or Homebrew; the first hosted distribution is Go for Apple silicon.

- Registered Morrow with Launch Services for background association and added matching-team/signature checks for customer app builds.
- Cleanup now reports unsigned development builds honestly and avoids relabeling their services into additional ungrouped Morrow rows. New native workers use the shared runner only when the app and launcher have valid matching signing teams.
- Added a narrow signed-helper operation that repairs gateway association metadata without restarting services, changing ports, replacing binaries, or rewriting DNS. Older helpers safely reject these requests before domain setup.
- Added staged app output for development builds so attribution work can be prepared without replacing executables used by running services. Ad-hoc development remains supported; customer builds use the signed release workflow.

- Settings and onboarding now read native setup/login permission status on launch, while monitoring, and when returning from System Settings. Approval prompts are conditional; allowed access is distinguished from working local routing, and pending setup survives reopening the app.
- Added scoped background-registration cleanup that archives obsolete inactive Morrow jobs and updates retained service attribution without interrupting running services or resetting macOS's background-item database.
- Added a shared verified binary catalog, HTTPS/checksum validation, safe native archive extraction, architecture/macOS filtering, separate version directories, direct official Go downloads, and app/CLI catalog configuration.
- Homebrew installation and upgrades now require explicit compatibility opt-in; existing native/Homebrew binaries remain usable. Databases, runtimes, mail, Sites, S3, update checks, and iCloud restoration share the provider policy. Hosted service distributions still need to be published.

- Added balanced inner padding to settings cells: fourteen-point side gutters and twelve-point top/bottom insets, with natural height for titles, subtitles, and wrapped text. Shared service rows and card content use the same spacing; button styling and window geometry are preserved.

- Slightly tightened shared settings padding: four-point action insets, eleven-point cell gutters, 44-point standard rows, and twelve-point section spacing; service rows share the same padding tokens.

- Matched light-mode settings cells to the About reference's warm gray fill (#F5F4F4), preserving the approved button palette.

- Softened shared settings surfaces to gray-white cards, slightly lighter neutral buttons, quiet outlines, and restrained shadows; charcoal equivalents cover dark mode.
- Unified normal, hover, pressed, and disabled control colors across settings buttons, menu controls, inputs, and brand-icon backplates without changing layout or card-edge geometry.

- Made the menu bar popover more compact with a 300-point width, 46-point shared service rows, 24-point controls/icons, tighter header/footer spacing, and a smaller empty state and feedback overlay.
- Unified menu row layout and separators across databases, mail, and S3, retaining readable labels, tooltips, accessibility names, and all existing actions.

- Fixed locale-based thousands separators in SMTP and S3 menu-bar port labels; ports always display as plain digits.

- Added an in-app Allow Morrow Setup explanation before opening macOS's native helper approval settings.
- Attributed service jobs to Morrow and added an unprivileged foreground runner for native children, preserving output, environment, exit status, and stop signals. Reliable macOS grouping requires shared Developer ID signing.

- Added first-launch onboarding for login behavior, CLI installation, local domains, and native helper approval; existing workspaces retain their setup.
- Replaced AppleScript elevation in the app with a bundled `SMAppService` setup daemon and a validated owner-only request channel, without storing sudo credentials.
- Added optional Developer ID/hardened-runtime signing inputs for customer builds; notarization remains a release requirement.
- Made runtime actions explicit: a compact Install or Set Default button beside the version selector replaces the full-width Use Version row.
- Fixed localhost gateway log permissions and added a protected standalone gateway copy so it continues after the app moves.

- Replaced PF-based local port forwarding with a socket-activated localhost gateway running as the Mac user, avoiding the custom packet filters that can block iCloud Private Relay.
- Added migration cleanup for Morrow's previous PF anchor, enable token, and DNS alias while retaining other tools' filtering state and resolver backups.

- Simplified Sites to a compact Local Domains card with one setup action and secondary validation/repair controls in a menu; grouped project actions under a plus menu.
- Combined hosting startup, local DNS/80/443 routing, and certificate trust into setup, with explicit backup/replacement of previous resolver files and safe restoration on removal.
- Replaced certificate-tool validation with native trust evaluation and inline status, keeping the settings page and window focus stable.
- HTTPS validation now checks normal DNS and port 443 after routing is installed; system setup flushes stale DNS caches.

- Cleared pending creation before opening service logs, updated the existing log-viewer expectation for sheet presentation, and clarified automatic setup preferences for nvm.

- Added nvm Node version management, official release discovery, LTS selection, and same-series updates that retain existing Node versions.
- Replaced folder-opening Storage controls with local MinIO S3 servers, bucket creation/empty deletion, private generated credentials, console access, and matching CLI lifecycle/configuration/log commands.
- Saved installation inventory and runtime channel caches; navigation reuses them while live service readiness checks continue separately.
- Organized sidebar navigation into Projects, Services, and App; General is now one scrollable page of grouped preferences without a category selector.
- Added shared plain status indicators, red stop icons, tooltip descriptions, accessible labels, and toast feedback across service cards and sheets.
- Moved logs to direct service-card/menu actions using a shared log sheet, removing Logs from sidebar navigation.
- Added an in-app PHP configuration editor with external-change protection and contextual access to managed configurations.
- Added brand icons for PHP, Go, Flutter, Node.js, Python, Ruby, MySQL, PostgreSQL, MongoDB, MariaDB, Memcached, and MinIO.
- Added per-project ignore/include actions that remove local hosting routes while preserving folders and project settings.
- Certificate trust now verifies the result and reports errors; explicit app/CLI HTTPS checks verify a local TLS response and explain missing port forwarding.

- Added a subtle light button background with theme-aware hover, pressed, and disabled states; shared actions use small interior corners and larger outer card-edge corners.
- Balanced grouped-action padding and dividers, updated geometry tracking, and added a shared side-by-side action group with independent outer corners.

- Sites and Project Directories UI for parked-folder discovery, enable/pause/remove controls, explicit links, per-project PHP, document roots, and HTTPS.
- Shared PHP-FPM/Caddy/dnsmasq hosting with loopback listeners, validated reloads, and a watcher that keeps running after the menu bar app closes.
- Folder-based app-port linking for npm development scripts and other HTTP runtimes.
- Configurable private development suffixes, Caddy-managed local certificates, and an explicit per-user CA trust action.
- Separate administrator setup for owned resolver files, a dedicated loopback DNS alias, and scoped 80/443/DNS forwarding; existing Herd/Valet configuration is preserved.
- Hosting listeners and linked application ports participate in database/mail port reservations.


- Grouped Command Line, Menu Bar, Appearance, and iCloud Sync preferences inside General.
- Local Mailpit SMTP testing services with a persistent inbox, loopback bindings, dual-port validation, lifecycle controls, in-app logs, CLI commands, and portable iCloud setup recipes.
- Redis and Valkey use vendor vector brand marks consistently across menu rows, instance details, and selectors.
- Service status now checks the managed PID with the OS and uses native administration or protocol readiness checks where available.
- iCloud Drive workspace blueprints sync portable preferences, database recipes, runtime series, and defaults across Macs.
- Per-Mac automatic Homebrew setup, safe port selection, additive snapshots, local-removal suppression, setup reports, and app/CLI retry controls.
- Local databases, credentials, logs, executable paths, and process state are excluded from workspace sync.
- Fixed false startup failures caused by treating launchd’s “never exited” placeholder as a real exit code.
- Startup errors now include only a short excerpt from the current start attempt, with full output available in Logs.
- Database update checks distinguish numeric maintenance releases, package revisions, and migration-required release series.
- Explicit database upgrades preserve a stopped instance backup, verify the new binary, and restore the previous instance on failure when possible.
- Durable update journals and app/CLI recovery controls protect interrupted operations.
- Applications settings and shared CLI management for PHP, Go, Flutter, Node.js, Python, and Ruby.
- Existing runtime discovery, version selection, companion commands, interactive execution, and optional Morrow-owned PATH wrappers.
- Runtime update checks and explicit upgrades; selected Flutter SDKs are retained separately from Homebrew's global cask.
- Existing workspace state remains readable with runtime fields added using backward-compatible decoding.

## 0.1.0 — Developer preview

- Native macOS menu bar app with a single database creation workflow.
- Shared CLI for creating, starting, stopping, configuring, and removing instances.
- PostgreSQL, MySQL, MariaDB, MongoDB, Redis, Valkey, and Memcached providers.
- Existing server detection in Homebrew, PATH, Herd, and Postgres.app.
- Port and duplicate validation before installation and on startup.
- Separate data directories and pinned native executables per instance.
- In-app logs with search, live updates, pause, and copy.
- Shared input, selector, and settings window components.
- Independent CLI build and safe local command installation.
- Explicit current Xcode/SDK builds and verified SDK records in the app binary.
- Nuxt documentation with Markdown guides, search, and automatic GitHub Pages deployment.
- Removed the separate Versions screen; database setup now lives entirely in creation.
- Standardized action buttons to the supplied macOS reference, with inset card actions, matching dialog controls, and About links to documentation and source.
- Simplified About to app identity, version, and links; removed the menu footer caption and product-level third-party references.
- Added fixed settings headers with a native gradient blur while scrolling, smooth appearance changes, and Reduce Motion support.
- Refined menu controls with borderless secondary icons and a compact, understated creation action.
- Added automatic card-edge corner geometry, lighter shared actions, a single-action database empty state, and a balanced About resource group.

Remote hosting, authenticated instance configuration, scheduled backups, S3 backup delivery,
RabbitMQ, project-specific runtime selection, and additional toolchains are planned.
