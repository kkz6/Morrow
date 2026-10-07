# Morrow development

- Keep database creation a single workflow: choose engine and version, then create. Reuse compatible binaries or install missing ones internally. Do not add an Installed Versions screen or a separate installation prerequisite to the app.
- Shared management behavior belongs in MorrowCore. The app and CLI must use the same state, validation, and lifecycle rules.
- Respect existing native binaries, user data, and services. Validate ports and versions before installation; never silently substitute an incompatible release or overwrite another CLI.
- Keep all app input and selector styles in the shared DesignSystem components.
- Use scripts/build-app.sh, scripts/build-cli.sh, and scripts/test.sh. They select full Xcode, use its current macOS SDK, and keep the minimum supported macOS version separate from that SDK.
- Every user-facing feature change must update the relevant website/content Markdown pages and CHANGELOG.md in the same change. Update the CLI reference when command behavior or options change.
- Build the Nuxt docs with Node 24.15 or newer, npm ci, npm run generate, and npm run check. GitHub Pages republishes main automatically.
- Do not commit generated app bundles, user databases, credentials, node_modules, .nuxt, or .output directories.
