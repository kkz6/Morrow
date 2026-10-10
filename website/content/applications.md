---
title: Applications and runtimes
description: Manage PHP, Go, Flutter, Node.js, Python, and Ruby from Settings or Terminal.
group: Everyday use
order: 4.7
---
## Select a version

Open **Settings → Runtimes**, choose an application and version, then click **Install** beside the version selector. For a detected installation the action becomes **Set Default**; a selected default shows a label instead of another button. Morrow verifies and reuses an existing binary, or installs a missing version and selects it in the same operation. Node.js uses nvm; Go has a direct official archive provider. Other missing runtimes use the configured verified catalog, with Homebrew only when compatibility is explicitly enabled. See [Binary downloads](/docs/binary-downloads).

Supported runtimes in this preview are PHP, Go, Flutter, Node.js, Python, and Ruby. The provider catalog can be extended as more runtimes are added. PHP web hosting and app-port routing live in [Sites](/docs/sites). Automatic ownership of Node/Go development processes, project-specific version files, and additional runtimes are future work.

Morrow reads its managed distribution receipts, nvm version directories, existing Homebrew formula kegs, PATH installations, and Herd's PHP binaries. Installed versions and downloaded channel lists are cached on disk. Navigation uses that cache; the refresh icon explicitly rescans installations and available versions. A missing or day-old installation inventory is refreshed when the app starts. Service readiness continues to use live process checks. Flutter discovery reads SDK version metadata without running Flutter's first-use bootstrap. If SDK metadata is absent, run `flutter --version` once using that installation and refresh the pane.

```sh
morrow tool catalog
morrow tool versions php
morrow tool channels php
morrow tool install php 8.4
morrow tool use php 8.4
morrow tool list
```

`tool install` without a version reuses an available runtime first. Explicit `current` or `latest` selects the current release from the runtime's provider. A version series reuses an existing matching installation or selects a compatible catalog release. Optional compatibility also accepts formula names such as `php@8.4`. An exact release can be downloaded when the catalog publishes it, or reused when already installed. Optional Homebrew compatibility cannot provide every historical patch.

## Node.js with nvm

Choose **Node.js** and **Latest LTS · nvm**, or select an exact release. The release catalog comes from Node's official distribution index. Installation uses nvm's native Node downloads and checksum verification; no container engine is installed.

```sh
morrow tool install node lts
morrow tool use node 24
morrow tool channels node
morrow tool exec node --command npm -- --version
```

The release series here is illustrative. nvm can resolve a release series or an exact numeric version. Morrow reuses a detected compatible installation before downloading. Existing Homebrew/PATH Node versions remain selectable.

Morrow uses a directory selected in **General → Node Version Manager**, then `NVM_DIR` if set, an existing `~/.nvm`, or its own `tools/nvm` directory. It reuses an available nvm script; otherwise it obtains the pinned nvm v0.40.8 scripts from the official nvm repository. Morrow does not edit your shell startup files. Selecting an nvm installation updates its default alias as well as Morrow's saved default. Existing Node versions remain on disk.

## Configuration and PHP logs

Use the configuration icon on a runtime card to open its configuration. PHP exposes its loaded `php.ini` and additional `.ini` files in a shared editor, with an **Open in Editor** action. Saving preserves file permissions and refuses to overwrite a file changed elsewhere; restart affected services to apply settings. These PHP files may be shared with applications outside Morrow. A generated Morrow PHP-FPM pool, when present, is visible read-only; its managed settings belong in Sites. The reload icon rereads a file after an outside edit.

nvm's default alias is visible as a managed, read-only file. Change it using version selection. Runtimes without a shared configuration file show an explanation; their project-specific configuration stays in the project. PHP-FPM cards expose the hosting log when one exists.

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

The default version is updated only if the selected installation was the default. Other version selections remain recorded. Homebrew dependencies can be updated globally during an upgrade; external package cleanup can later remove pinned formula versions. Compatible managed releases can be installed beside existing runtimes. External versions with no catalog release remain the responsibility of their original installer. Node checks use the official Node catalog and install the newest release in the same major series through nvm, retaining the previous version. A refresh does not require Homebrew when only Node is tracked.

Flutter can use complete catalog SDK archives. When Homebrew compatibility is enabled, its cask has one current installable release. Managed SDKs already have separate version directories. Morrow copies externally installed Flutter SDKs into its own `tools/flutter/<version>` directory before selecting them. This preserves selected SDKs when Homebrew replaces its global cask. Flutter's own `upgrade` command can mutate an SDK; use Morrow's update command to retain separate versions. Flutter builds can require Git, Xcode, Android SDK, or other target-platform dependencies in addition to the SDK.

## Remove a selection

```sh
morrow tool remove php 8.4
```

This forgets the version in Morrow and clears its default if selected. Shared installations and retained Flutter SDKs remain on disk. Select another default before using that runtime's wrappers again. Morrow does not uninstall shared Homebrew packages; an existing version can be selected again later.
