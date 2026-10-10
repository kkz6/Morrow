---
title: Contributing
description: Keep app behavior, CLI commands, and documentation in sync.
group: Project
order: 8
---
## Shared architecture

`MorrowCore` owns native discovery, provisioning, validation, lifecycle, and persistent state. `MorrowApp` supplies the macOS UI, and `MorrowCLI` exposes the same manager to Terminal.

Make shared behavior changes in the core so both interfaces remain consistent. Keep database creation as one operation; engine and version selection belong in the creation dialog.

## App interface

`DS.Surface` owns the shared appearance palette. Light-mode cells use the warm gray `#F5F4F4` from the reference, with slightly lighter neutral controls; dark mode uses charcoal equivalents. Buttons, menu controls, input fields, and brand-icon backplates share those colors. Hover, pressed, and disabled states adjust the neutral fill without tinting the whole surface. Keep outlines quiet and shadows shallow; avoid pure-white card blocks, broad floating shadows, or pane-specific color overrides. Geometry, typography, window material, and grouped action corners remain independent of this palette.

Use the shared DesignSystem components for controls. Action buttons use a subtle light surface that adapts to light and dark mode, a thin border, and medium-weight text with a restrained one-point shadow. `SettingsCard` publishes its size and coordinate space; full-width actions keep softly rounded interior corners and automatically increase the radius at the card edges. A single action rounds all corners, first and last actions follow top and bottom edges, and middle actions use a restrained three-point radius and card-edge corners expand to eleven points. Bottom action rows keep modest top corners and larger lower corners that follow the card. Compact action controls use a five-point radius. Use `SettingsActionGroup` for side-by-side actions; only their outer card-edge corners expand. Action rows/groups share balanced four-point padding and half-point dividers. Do not specify row positions or per-pane corner overrides.

Settings cells use `settingsCellPadding()` for fourteen-point side gutters and twelve-point top/bottom insets. `SettingRow` applies these insets before its 44-point minimum height, allowing titles, subtitles, and wrapped labels to grow naturally without squeezing text against the cell edges. Custom service rows and card content use the same helper and `SettingsLayout` tokens. Button labels keep their independent eleven-point inset; spacing changes must preserve the approved control appearance. Section gaps remain twelve points, and the window size stays fixed.

In the menu popover, use compact actions with the shared quiet neutral surface and borderless secondary icons. Icon backplates appear only on hover or press. Keep creation buttons centered and appropriately sized rather than stretching a heavy settings-card button across the menu.

Use `MenuLayout` and `MenuServiceRow` for menu geometry: 300-point width, 46-point rows, 24-point icons and action targets, 12-point horizontal insets, and a shared six-row viewport. Header/footer, empty state, separators, and preview rendering use the same tokens. Keep service names at 12 points and metadata at 10 points; compactness comes from spacing rather than unreadable text. Use the compact service-action and feedback variants in the menu, preserving regular sizes in Settings.

About centers a modest app identity above a Resources group with documentation, source, and issue-reporting links. Keep marketing text and implementation details out of this pane. Empty database views offer one creation action at the card's bottom edge. The menu footer contains only its settings and quit controls. Settings cards provide full-width actions for command installation and service creation.

Settings titles and icons remain pinned while detail content scrolls. The header samples the window's native material only after scrolling begins. Its alpha mask remains opaque through the title's midpoint, then fades smoothly to transparent. Keep the title outside the effect, avoid opaque fills or bottom borders, and disable the fade animation when Reduce Motion is enabled. The shared layout retains its existing window size and gutters in both appearances.

Service lifecycle actions use `ServiceActionButton`: start uses a play icon, stop uses a red stop icon, and secondary icons have tooltips and accessible labels. Use `ServiceStatusView` for plain live status and `serviceFeedback()` for theme-aware toast feedback, including in sheets. Use the shared `ServiceLogViewer` and configuration editor rather than another sidebar page or bespoke file opener. Runtime and database tiles resolve bundled brand marks through `BrandIcons`.

General is one scrollable grouped page. Sidebar navigation groups Projects, Services, and App. Installation inventory and release catalogs are saved in a private cache; use explicit refresh for rescans, with a daily installation refresh at startup. Never cache running status as the source of truth: status still checks owned processes and native readiness.

## Build and verify

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/build-cli.sh
```

Tests cover state, provider configuration, log reading, creation, duplicate prevention, and port validation. Real native integration checks should use an isolated `MORROW_HOME` and clean up their managed jobs.

## Documentation workflow

The website is a Nuxt application in `website/`. Its source pages are Markdown in `website/content/`; generated HTML and search data are derived at build time.

```sh
cd website
npm ci
npm run dev
```

Use Node 24.15 or newer. To produce the static site:

```sh
npm run generate
npm run check
```

Changes pushed to `main` rebuild and publish the documentation through GitHub Pages. Keep feature changes and relevant documentation together in the same pull request. The docs checker catches missing pages, broken local links, and uncovered CLI command names.

## Add a feature

1. Implement shared behavior and expose it in the app and CLI where appropriate.
2. Add meaningful verification for behavior that needs it.
3. Update relevant guide pages, the CLI reference if commands changed, and the changelog.
4. Run the documentation build and checker before publishing.

The repository’s `AGENTS.md` records this requirement for future coding sessions. It supports keeping documentation current; it does not generate unreviewed feature descriptions automatically.

## Current scope

This developer preview includes local databases, PHP/Go/Flutter/Node/Python/Ruby runtimes, nvm Node management, Mailpit, PHP/static/app-port hosting, and MinIO S3 buckets. Authenticated database configuration, backup/export and S3 backup delivery, remote server management, RabbitMQ, and project-specific runtime selection are future work.

## Dependency status

`BinaryInstaller` owns shared installation policy. Prefer validated existing copies and `ManagedBinaryStore` distributions; guard every Homebrew mutation with explicit compatibility permission. Catalog downloads require HTTPS, SHA-256, platform filtering, private staging, safe extraction, and actual version validation. Go has an official archive provider and Node uses nvm. Keep distribution libraries/resources relocatable; do not advertise an unpublished package as installable. See [Binary downloads](/docs/binary-downloads) for catalog fields and current availability.

The Nuxt toolchain currently reports upstream high-severity npm audit advisories involving its development dependencies. Patched Git parser versions are pinned through overrides. The published site contains static HTML, CSS, and client scripts; its development server stays on 127.0.0.1. Recheck advisories when updating dependencies rather than forcing an incompatible Nuxt downgrade.

## Customer distribution

Build the complete app, including the bundled `dev.morrow.setup.plist`, with a Developer ID identity:

```sh
MORROW_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh release
```

The build signs nested executables before the app, enables hardened runtime, and requests a timestamp when an identity is provided. Default local/CI builds remain ad-hoc signed. A customer release still needs Apple's notarization submission and ticket stapling; providing a signing variable does not itself notarize the app.

Setup uses native `SMAppService` approval. Do not reintroduce AppleScript/Python elevation or cache a sudo password. Keep the setup helper's operations limited to validated local DNS and gateway installation.

## Background-item attribution

Register the app with Launch Services before repairing attribution. `BackgroundAttribution` checks the app and launcher signatures and Apple team identifiers. The build rejects a supplied signing identity when those teams differ or are missing. Ad-hoc development builds remain supported, but cleanup must explain their grouping limitation and avoid converting more unsigned native workers into separately named Morrow entries.

To stage an app without replacing the bundle used by current services:

```sh
MORROW_APP_OUTPUT="$PWD/.build/staged/Morrow.app" ./scripts/build-app.sh release
```

Staging does not update `build/morrow`. Signing and deployment can be completed later; staging alone does not change macOS's allowed list. Never modify the global background-task database to hide entries.

The setup helper's attribution action changes only the protected gateway plist's association metadata. It validates user ownership and matching helper/gateway signing teams and does not invoke launchctl or local-domain setup. Attribution requests use zero ports so an older helper rejects them before changing any domains. Do not replace a pending domain-setup request with an attribution request.

Read `SMAppService` status at startup, during monitoring, and when the app becomes active. Never use an operation-local boolean as permission state. Approval and working routing are separate: validate routing before reporting setup complete. Do not register helpers merely to refresh permission. `BackgroundRegistrations` may archive inactive orphan Morrow jobs and normalize retained definitions; it preserves running services and other apps' jobs. macOS controls historical list entries and final grouping.

Generated launchd jobs declare `AssociatedBundleIdentifiers` for Morrow. When the bundled CLI and app have valid matching Apple signing teams, database, mail, web, and S3 workers launch through Morrow's foreground service runner. Ad-hoc development builds launch native workers directly to avoid adding more ungrouped Morrow rows. The signed runner preserves environment/output, forwards stop signals to the owned native child, and exits with that child's status.

Customer executables must share Morrow's Developer Team ID for macOS attribution. macOS owns the final Login Items grouping; ad-hoc previews, old registrations, or standalone unsigned binaries can appear separately. Never modify the system background-task database or claim that separate server processes disappear. Existing services adopt updated job metadata when recreated or restarted; do not stop user databases merely to refresh a settings list.
