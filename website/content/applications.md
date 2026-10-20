---
title: Applications and runtimes
description: Manage PHP, Go, Flutter, Node.js, Python, and Ruby from Settings or Terminal.
group: Everyday use
order: 4.7
---
## Select a version

Open **Settings → Runtimes**, choose an application and version, then click **Install** beside the version selector. For a detected installation the action becomes **Set Default**; a selected default shows a label instead of another button. Morrow verifies and reuses an existing binary, or installs a missing version and selects it in the same operation. Node.js and other missing runtimes use the configured verified catalog; Go also has a direct official archive provider. No package manager is used for installation or updates. See [Binary downloads](/docs/binary-downloads).

Supported runtimes in this preview are PHP, Go, Flutter, Node.js, Python, and Ruby. The provider catalog can be extended as more runtimes are added. PHP web hosting and app-port routing live in [Sites](/docs/sites). [Folder Versions](/docs/project-versions) selects a runtime per project. Automatic ownership of Node/Go development processes, portable project version files, and additional runtimes are future work.

Morrow reads its managed distribution receipts, nvm version directories, existing Homebrew formula kegs, PATH installations, and Herd's PHP binaries. Installed versions and downloaded channel lists are cached on disk. Navigation uses that cache; the refresh icon explicitly rescans installations and available versions. A missing or day-old installation inventory is refreshed when the app starts. Service readiness continues to use live process checks. Flutter discovery reads SDK version metadata without running Flutter's first-use bootstrap. If SDK metadata is absent, run `flutter --version` once using that installation and refresh the pane.

```sh
morrow tool catalog
morrow tool versions php
morrow tool channels php
morrow tool install php 8.4
morrow tool use php 8.4
morrow tool list
```

`tool install` without a version reuses an available runtime first. Explicit `current` or `latest` selects the current release from the runtime's provider. A version series reuses an existing matching installation or selects a compatible catalog release. Legacy installed-version selectors remain supported. An exact release can be downloaded when the catalog publishes it, or reused when already installed. Unavailable historical patches are reported without substituting another version.

## Node.js distributions

Choose **Node.js** and **Latest LTS**, or select an available exact release. Morrow downloads a complete Node package from its hosted catalog, including npm, npx, headers, and license notices. Node **22.23.3** and **24.22.0** LTS are published for Apple silicon and Intel. Downloads need neither nvm nor Homebrew, Git, or Xcode. Installing native npm add-ons can still require their own development tools.

```sh
morrow tool install node lts
morrow tool use node 24
morrow tool channels node
morrow tool exec node --command npm -- --version
```

A numeric series selects a published release in that series; an exact version must be installed or published. `lts` chooses the newest compatible hosted release explicitly marked LTS by its recipe, reusing an existing installation of that exact version when available. It does not silently choose another version when none is available. The CLI's install command preserves the current default until `tool use`; the app's Install action installs and selects its version.

Existing nvm, Homebrew, and PATH Node installations remain selectable. Morrow reads an existing nvm directory selected under **General → Existing Node Installations**, `NVM_DIR`, or `~/.nvm`. It never installs nvm scripts, changes its default alias, or edits shell startup files. New managed versions live separately under Morrow's binary directory. Legacy `nvm@<version>` selectors remain accepted for compatible installed or published versions.

On upgrading, Morrow discards only the old nvm channel list so the selector reloads published versions. Cached installed software and other runtime lists remain available.

## Configuration and PHP logs

### PHP 8.0

PHP **8.0.30** is available from Morrow's hosted catalog for Apple silicon and Intel Macs running macOS 14 or newer. The package includes PHP CLI and PHP-FPM, with built-in extensions including MySQLi, PDO MySQL, mbstring, intl, curl, Redis, and OPcache. It does not require Homebrew.

Use **Runtimes → Folder Versions → Choose Folder…**, select PHP and **8.0.30**, then save to install and assign it to that folder while keeping the global default. The Add Runtime **Install** action installs and selects a runtime as Morrow's default, as it does for other versions. From Terminal, installation and folder assignment are separate:

```sh
morrow binary refresh
morrow tool install php 8.0
morrow project use php 8.0 --path /path/to/project
```

Portable PHP has its own editable `php.ini` and additional INI directory. Morrow's commands and PHP-FPM use those files, keeping other PHP installations' configuration separate. The built-in extensions do not require separately installed libraries. Optional extension binaries must match this PHP build; `phpize` and `php-config` are not included.

PHP 8.0 is a legacy release, with [upstream support ending in November 2023](https://www.php.net/eol.php). Morrow keeps it available for older local projects and does not silently switch them to another PHP series.

Use the configuration icon on a runtime card to open its configuration. PHP exposes its loaded `php.ini` and additional `.ini` files in a shared editor, with an **Open in Editor** action. Saving preserves file permissions and refuses to overwrite a file changed elsewhere; restart affected services to apply settings. These PHP files may be shared with applications outside Morrow. A generated Morrow PHP-FPM pool, when present, is visible read-only; its managed settings belong in Sites. The reload icon rereads a file after an outside edit.

An existing nvm default alias is visible read-only. It belongs to the external nvm installation; Morrow keeps its own default and folder selections. Runtimes without a shared configuration file show an explanation; their project-specific configuration stays in the project. PHP-FPM cards expose the hosting log when one exists.

## Run the selected runtime

```sh
morrow tool exec php -- --version
morrow tool exec go -- version
morrow tool exec flutter -- doctor
morrow tool exec node -- --version
morrow tool exec python -- --version
morrow tool exec ruby -- --version
```

The command inherits Terminal input and output, passes arguments directly to the selected executable, and returns its exit status. It chooses the nearest saved folder version for the current directory, then the global default. `--path <folder>` chooses another working directory. Companion commands can be selected explicitly:

```sh
morrow tool exec node --command npm -- --version
morrow tool exec flutter --command dart -- --version
```

Only commands belonging to the selected runtime are accepted. Missing companion tools are reported.

## Use ordinary commands in Terminal

```sh
morrow tool shell
```

Add the printed `export PATH=...` line to your shell configuration, then open a new terminal. Morrow's wrappers select saved folder versions according to the working directory, falling back to its global defaults for `php`, `go`, `flutter`, `dart`, `node`, `npm`, `python`, `ruby`, and available companion tools. The app and CLI share these selections.

Morrow does not edit your shell files or run `brew link`. Commands already installed elsewhere remain available when Morrow's bin directory is not first on PATH. Wrappers refuse to overwrite unrecognized commands in Morrow's bin directory. Re-select versions after moving the app or CLI so wrappers use its current location.

## Updates

Existing external runtimes can show **Portable distribution available** for the same release. The update action installs Morrow's complete package without modifying the external copy. A selected global default follows the change; folder choices retain their exact installation until you select the portable runtime for those folders. Do this before removing an external package manager yourself.

Choose **Check Updates** and **Update…** in a tracked application's menu, or run:

```sh
morrow tool updates --refresh
morrow tool upgrade php
morrow tool upgrade php 8.4
```

The default version is updated only if the selected installation was the default. Other version selections remain recorded. Existing external binaries are preserved; portable updates include their own libraries. Compatible managed releases can be installed beside existing runtimes. External versions with no catalog release remain the responsibility of their original installer. Node updates use published distributions within the same major series, retaining the previous version and folder selections. Existing nvm aliases are preserved. A refresh does not require Homebrew.

Flutter can use complete catalog SDK archives. Managed SDKs already have separate version directories. Morrow copies externally installed Flutter SDKs into its own `tools/flutter/<version>` directory before selecting them. This preserves selected SDKs when Homebrew replaces its global cask. Flutter's own `upgrade` command can mutate an SDK; use Morrow's update command to retain separate versions. Flutter builds can require Git, Xcode, Android SDK, or other target-platform dependencies in addition to the SDK.

## Remove a selection

```sh
morrow tool remove php 8.4
```

This forgets the version in Morrow and clears its default if selected. Shared installations and retained Flutter SDKs remain on disk. Select another default before using that runtime's wrappers again. Morrow does not uninstall shared Homebrew packages; an existing version can be selected again later.
