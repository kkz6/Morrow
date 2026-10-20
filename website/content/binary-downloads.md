---
title: Binary downloads
description: Complete native service and runtime distributions without a package manager.
group: Start here
order: 1.5
---
## Installation policy

Morrow first verifies and reuses a compatible existing installation. Missing software uses complete native distributions kept under `~/Library/Application Support/Morrow/binaries/<package>/<version>-<architecture>-<hash>`. Database creation stays one workflow; no separate Installed Versions screen is needed.

Morrow handles binary downloads automatically during service creation or runtime installation. General does not expose catalog URLs or binary-management controls. Morrow never runs Homebrew to install, refresh, or update software. Existing native installations and their data remain usable through read-only discovery, even when Homebrew’s command is absent. A saved legacy compatibility preference cannot re-enable package-manager installs. The deprecated `morrow binary brew off` command clears that preference; `brew on` is rejected.

| Software | Source for missing versions |
| --- | --- |
| Node.js | Complete Node distributions from Morrow’s catalog, including npm and npx |
| Go | Official Go macOS archives and published SHA-256 checksums, unless your catalog supplies Go |
| Databases, PHP, Flutter, Python, Ruby | Complete compatible distributions in your configured catalog |
| Caddy, dnsmasq, Mailpit, MinIO | Complete compatible distributions in your configured catalog |

Release builds include Morrow's public HTTPS catalog on Contabo object storage. A saved custom source takes precedence. The active catalog contains 23 releases across all 17 supported service and runtime families for Apple silicon (arm64) Macs. New Intel packages are no longer built or published. Previously published Intel archives remain at their original URLs, but are not offered in the active catalog. Packages support macOS 14 or newer, except Flutter 3.47.7 which requires macOS 15 for its bundled iPhone tools:

| Software | Published versions |
| --- | --- |
| PostgreSQL | 17.11, 18.6 |
| MySQL | 8.4.11, 26.7.0 |
| MariaDB | 11.8.9 |
| MongoDB Community | 8.0.34 |
| Redis | 8.10.2 |
| Valkey | 9.1.2 |
| Memcached | 1.6.45 |
| PHP CLI and FPM | 8.0.30, 8.3.35, 8.4.26, 8.5.11 |
| Node.js with npm and npx | 22.23.3, 24.22.0 LTS |
| Go | 1.27.2 |
| Python with pip | 3.15.0 |
| Ruby with RubyGems and Bundler | 4.0.7 |
| Flutter with Dart | 3.47.7 |
| Mailpit | 1.31.6 |
| MinIO | 2025.10.15 |
| Caddy | 2.11.7 |
| dnsmasq | 2.93 |

These are published versions, not every historical patch. Refresh the version selector to retrieve new catalog releases. Missing releases are reported without substituting another version or invoking Homebrew. See [Release signing and hosting](/docs/releases) for the publishing workflow. Compiling applications or native extensions may require Xcode, Git, Android tools, or project-specific development headers; runtime downloads do not install those tools.

When a custom catalog has no compatible Go release, Go can still use its official archive provider.

## Existing installations

Publishing portable packages does not move running instances automatically. Existing instances and folder choices keep their recorded executable paths. Before uninstalling a package manager yourself, move those selections to portable installations and confirm their services work. Morrow never removes Homebrew, its Cellar, shared libraries, or user databases. Different database release series require migration; compatible updates use the existing backup and recovery workflow.

## Advanced source configuration

Release builds use Morrow's bundled download source without customer configuration. For development or a custom distribution source, use Terminal. Morrow validates the catalog before replacing the previous setting:

```sh
morrow binary source https://downloads.example.com/catalog.json
morrow binary list
morrow binary refresh
morrow binary source clear
```

The example hostname is a placeholder. Do not embed credentials in the URL. `source clear` removes your custom override and returns to the release's bundled source, if present. `morrow doctor` shows the effective source. Catalog choice stays local to this Mac and is not included in iCloud recipes. Customers do not need AWS CLI, storage keys, or Homebrew to download a published distribution.

## Catalog format

A catalog contains `schemaVersion: 1` and a `releases` array. This illustrative release is not downloadable until its URL, version, and checksum are replaced with real published values:

```json
{
  "schemaVersion": 1,
  "releases": [{
    "package": "postgresql",
    "version": "17.12",
    "architecture": "arm64",
    "minimumMacOS": "14.0",
    "url": "https://downloads.example.com/postgresql/17.12/macos-arm64.tar.gz",
    "sha256": "REPLACE_WITH_THE_ARCHIVE_SHA256_DIGEST",
    "archive": "tar",
    "rootDirectory": "postgresql",
    "executables": ["bin/postgres", "bin/initdb", "bin/pg_ctl"]
  }]
}
```

Supported package identifiers are the database and runtime names from `morrow db catalog`/`morrow tool catalog`, plus `caddy`, `dnsmasq`, `mailpit`, and `minio`. New distributions use `arm64`. The reader retains `x86_64` and `universal` metadata compatibility for older catalogs and installation receipts; these are not new distribution targets. `archive` accepts `tar` (including compressed tar archives), `zip`, or `binary`. Use an empty `rootDirectory` when files are already at archive root. Raw binary downloads need one executable and an empty root directory. Node releases can include the optional Boolean `lts` field; `lts: true` makes a published release eligible for the Latest LTS selector. Older catalogs and receipts without this field remain valid.

Database executables and auxiliary services use `bin/<executable>`. PHP needs its CLI and PHP-FPM; Flutter needs complete SDK metadata. Package all required libraries and resources with relocatable paths. A Homebrew bottle referencing another machine's Cellar is not a portable distribution. Publishing and redistribution rights, build signing/notarization, dependency packaging, and minimum-system support are the publisher's responsibility.

## Verification and updates

Downloads use HTTPS and HTTPS redirects. Morrow checks SHA-256 before extraction, filters releases by architecture and macOS version, and reads native Mach-O headers without requiring Xcode on the customer's Mac. Extraction rejects absolute paths, traversal, external symbolic links, hard links, and special files. Downloads are staged privately and published without replacing another version. No catalog-provided install script is executed.

The catalog is a trusted software source. HTTPS protects delivery and the manifest's checksum validates its archive; a checksum does not authenticate a compromised catalog. Configure only a source you control or trust.

Managers verify the actual executable's identity and version before creating a service or selecting a runtime. Missing initialization tools, dependency failures, or mismatched versions are reported without attaching the binary to a new instance.

Numeric patch versions drive update checks. Managed database maintenance updates retain the existing backup/recovery workflow; major-series changes require another instance and data migration. Managed runtime updates install beside the prior version and change the default only when that version was selected. Existing binaries are not relocated or uninstalled automatically.
