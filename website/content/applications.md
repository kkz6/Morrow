---
title: Applications and runtimes
description: Manage PHP, Go, Flutter, Node.js, Python, and Ruby from Settings or Terminal.
group: Everyday use
order: 4.7
---
## Select a version

Open **Settings → Applications**, choose an application and version, then click **Use Version**. Morrow verifies and reuses an existing binary, or installs a missing Homebrew channel and selects it in the same operation.

Supported runtimes in this preview are PHP, Go, Flutter, Node.js, Python, and Ruby. The provider catalog can be extended as more runtimes are added. Web sites, PHP-FPM services, project-specific version files, and additional runtimes are future work.

Morrow reads Homebrew formula kegs, PATH installations, and Herd's PHP binaries. Flutter discovery reads SDK version metadata without running Flutter's first-use bootstrap. If SDK metadata is absent, run `flutter --version` once using that installation and refresh the pane.

```sh
morrow tool catalog
morrow tool versions php
morrow tool channels php
morrow tool install php 8.4
morrow tool use php 8.4
morrow tool list
```

`tool install` without a version reuses an available runtime first. Explicit `current` or `latest` selects the current Homebrew channel. A version series reuses an existing matching installation or chooses an available formula such as `php@8.4`. Exact historical releases are usable if already installed; Homebrew cannot provide every old patch version.

## Run the selected runtime

```sh
morrow tool exec php -- --version
morrow tool exec go -- version
morrow tool exec flutter -- doctor
morrow tool exec node -- --version
morrow tool exec python -- --version
morrow tool exec ruby -- --version
```

The command inherits Terminal input and output, passes arguments directly to the selected executable, and returns its exit status. Companion commands can be selected explicitly:

```sh
morrow tool exec node --command npm -- --version
morrow tool exec flutter --command dart -- --version
```

Only commands belonging to the selected runtime are accepted. Missing companion tools are reported.

## Use ordinary commands in Terminal

```sh
morrow tool shell
```

Add the printed `export PATH=...` line to your shell configuration, then open a new terminal. Morrow's wrappers use its saved defaults for `php`, `go`, `flutter`, `dart`, `node`, `npm`, `python`, `ruby`, and available companion tools. The app and CLI share these defaults.

Morrow does not edit your shell files or run `brew link`. Commands already installed elsewhere remain available when Morrow's bin directory is not first on PATH. Wrappers refuse to overwrite unrecognized commands in Morrow's bin directory. Re-select versions after moving the app or CLI so wrappers use its current location.

## Updates

Choose **Check Updates** and **Update…** in a tracked application's menu, or run:

```sh
morrow tool updates --refresh
morrow tool upgrade php
morrow tool upgrade php 8.4
```

The default version is updated only if the selected installation was the default. Other version selections remain recorded. Homebrew dependencies can be updated globally during an upgrade; external package cleanup can later remove pinned formula versions. External runtimes must be updated with their original installer.

Flutter is a Homebrew cask with one current installable release. Morrow copies selected Flutter SDKs into its own `tools/flutter/<version>` directory before selecting them. This preserves selected SDKs when Homebrew replaces its global cask. Flutter's own `upgrade` command can mutate an SDK; use Morrow's update command to retain separate versions. Flutter builds can require Git, Xcode, Android SDK, or other target-platform dependencies in addition to the SDK.

## Remove a selection

```sh
morrow tool remove php 8.4
```

This forgets the version in Morrow and clears its default if selected. Shared installations and retained Flutter SDKs remain on disk. Select another default before using that runtime's wrappers again. Morrow does not uninstall shared Homebrew packages; an existing version can be selected again later.
