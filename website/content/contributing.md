---
title: Contributing
description: Keep app behavior, CLI commands, and documentation in sync.
group: Project
order: 8
---
## Shared architecture

`MorrowCore` owns native discovery, provisioning, validation, lifecycle, and persistent state. `MorrowApp` supplies the macOS UI, and `MorrowCLI` exposes the same manager to Terminal.

Make shared behavior changes in the core so both interfaces remain consistent. Keep database creation as one operation; engine and version selection belong in the creation dialog.

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
