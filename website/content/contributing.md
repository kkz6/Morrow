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

Use the shared DesignSystem components for controls. Action buttons use a subtle light surface that adapts to light and dark mode, a thin border, and medium-weight text without raised shadows. `SettingsCard` publishes its size and coordinate space; full-width actions keep softly rounded interior corners and automatically increase the radius at the card edges. A single action rounds all corners, first and last actions follow top and bottom edges, and middle actions use a restrained three-point radius and card-edge corners are capped at six points. Compact action controls use a five-point radius. Do not specify row positions or per-pane corner overrides.

In the menu popover, use compact actions with a translucent surface and borderless secondary icons. Icon backplates appear only on hover or press. Keep creation buttons centered and appropriately sized rather than stretching a heavy settings-card button across the menu.

About centers a modest app identity above a Resources group with documentation, source, and issue-reporting links. Keep marketing text and implementation details out of this pane. Empty database views offer one creation action at the card's bottom edge. The menu footer contains only its settings and quit controls. Settings cards provide full-width actions for command installation and opening storage folders.

Settings titles and icons remain pinned while detail content scrolls. The header samples the window's native material only after scrolling begins. Its alpha mask remains opaque through the title's midpoint, then fades smoothly to transparent. Keep the title outside the effect, avoid opaque fills or bottom borders, and disable the fade animation when Reduce Motion is enabled. The shared layout retains its existing window size and gutters in both appearances.

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

This is a developer preview for local databases. Authentication controls, backup/export, S3 destinations, remote server management, RabbitMQ, and PHP/Go runtimes are future work.

## Dependency status

The Nuxt toolchain currently reports upstream high-severity npm audit advisories involving its development dependencies. Patched Git parser versions are pinned through overrides. The published site contains static HTML, CSS, and client scripts; its development server stays on 127.0.0.1. Recheck advisories when updating dependencies rather than forcing an incompatible Nuxt downgrade.
