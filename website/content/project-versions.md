---
title: Folder Versions
description: Select PHP, Node.js, or another runtime per project folder for hosting and Terminal commands.
group: Everyday use
order: 4.8
---
## Choose a folder's runtime

Open **Settings → Runtimes → Folder Versions → Choose Folder**. Select the project folder, choose an application and version, and save. You can save PHP and Node.js separately for the same folder. The folder's saved versions appear together in the list.

**Project Settings → Folder versions → Choose** opens the same editor for a hosted project. Choose **Inherit Default** to remove a runtime's explicit choice from this folder. Clearing all folder versions preserves the folder and installed software.

Supported runtimes are PHP, Node.js, Go, Flutter, Python, and Ruby. Installed versions and available provider releases use the shared selector; **Other Version** accepts a release series such as PHP `8.4` or Node `24`. Morrow reuses a compatible installation or installs the requested release using its configured provider. PHP **8.0.30** is available from the hosted catalog for Apple silicon; selecting it for a folder installs it when needed and leaves the global PHP default unchanged. A package not installed or published in the catalog requires an appropriate published distribution. It is not silently replaced by another release.

Selecting a series stores the exact version actually installed. Updates to the global default do not move a folder's selection. Change its choice explicitly when you want to update it.

## Terminal commands

```sh
cd ~/Projects/shop
morrow project use php 8.4
morrow project use node 24
morrow project show
morrow tool exec php -- --version
morrow tool exec node -- --version
morrow tool exec node --command npm -- run dev
```

The versions above are examples; availability depends on installed binaries and the selected provider. Choose a folder without changing your terminal directory:

```sh
morrow project use php 8.4 --path ~/Projects/shop
morrow tool exec php --path ~/Projects/shop -- artisan about
morrow project list
morrow project clear node --path ~/Projects/shop
morrow project clear all --path ~/Projects/shop
```

To use ordinary `php`, `node`, and `npm` commands, run `morrow tool shell` and add the printed PATH line to your shell configuration. Morrow's wrappers choose the version for the current working directory on each invocation. Outside a selected folder, select a global default with `morrow tool use` when one is needed. Morrow does not edit shell startup files, `.nvmrc`, or project configuration files.

## Inheritance and hosting

A folder selection applies to its descendants. The closest selected ancestor wins separately for each runtime. For example, a parent folder can select PHP 8.4 and Node 24, while one child selects Node 22 and continues inheriting PHP 8.4.

PHP web hosting uses the same selected installation's PHP-FPM pool. Hosting requires a PHP distribution containing PHP-FPM. Morrow reloads affected routing and starts the required pool; other projects retain their own choices. An existing explicit PHP site selection is retained as a folder choice when that folder has one consistent version.

Node selection does not start a development server. Run its npm script using the selected version, then link the local port to a domain as described in [Sites](/docs/sites).

If a selected executable is removed or changes version, Morrow reports the unavailable selection instead of falling back to another runtime. Clear or reselect the folder's version. A runtime referenced by a folder must be cleared from that folder before it can be forgotten from Morrow.

## Where choices are saved

Selections are stored privately in Morrow's `project-runtimes.json`, alongside its workspace metadata. They persist after app and Mac restarts. Paths are canonicalized so a folder reached through a symbolic link shares the same choice. These local path mappings are not included in iCloud workspace sync; registered runtime installation recipes still sync normally.
