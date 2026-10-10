---
title: Binary downloads
description: Verified native distributions and optional Homebrew compatibility.
group: Start here
order: 1.5
---
## Installation policy

Morrow first verifies and reuses a compatible existing installation. Missing software uses complete native distributions kept under `~/Library/Application Support/Morrow/binaries/<package>/<version>-<architecture>-<hash>`. Database creation stays one workflow; no separate Installed Versions screen is needed.

Homebrew compatibility is **off by default**, including when older preferences do not contain the new option. Existing Homebrew installations and their data remain usable. Enable **General → Binary Downloads → Homebrew compatibility** only if you want Homebrew to install or upgrade a package that is not published in the catalog.

| Software | Source for missing versions |
| --- | --- |
| Node.js | nvm and the official Node release catalog |
| Go | Official Go macOS archives and published SHA-256 checksums, unless your catalog supplies Go |
| Databases, PHP, Flutter, Python, Ruby | Complete compatible distributions in your configured catalog |
| Caddy, dnsmasq, Mailpit, MinIO | Complete compatible distributions in your configured catalog |

No Morrow-hosted catalog is deployed in this preview. Without a published package, Morrow explains that it is unavailable instead of installing another release or silently invoking Homebrew. This download layer prepares the app and CLI for object storage; it does not create a server or upload packages.

## Configure a source

Open **General → Binary Downloads**, enter an HTTPS catalog URL, and save it. Morrow validates the catalog before replacing the previous setting. Source changes clear cached channel lists. Use the same configuration from Terminal:

```sh
morrow binary source https://downloads.example.com/catalog.json
morrow binary list
morrow binary refresh
morrow binary brew off
morrow binary source clear
```

The example hostname is a placeholder. Supply your own source; do not embed credentials in the URL. Catalog choice and compatibility permission stay local to this Mac and are not included in iCloud recipes.

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

Supported package identifiers are the database and runtime names from `morrow db catalog`/`morrow tool catalog`, plus `caddy`, `dnsmasq`, `mailpit`, and `minio`. Architectures are `arm64`, `x86_64`, and `universal`. `archive` accepts `tar` (including compressed tar archives), `zip`, or `binary`. Use an empty `rootDirectory` when files are already at archive root. Raw binary downloads need one executable and an empty root directory.

Database executables and auxiliary services use `bin/<executable>`. PHP needs its CLI and PHP-FPM; Flutter needs complete SDK metadata. Package all required libraries and resources with relocatable paths. A Homebrew bottle referencing another machine's Cellar is not a portable distribution. Publishing and redistribution rights, build signing/notarization, dependency packaging, and minimum-system support are the publisher's responsibility.

## Verification and updates

Downloads use HTTPS and HTTPS redirects. Morrow checks SHA-256 before extraction, filters releases by architecture and macOS version, and reads native Mach-O headers without requiring Xcode on the customer's Mac. Extraction rejects absolute paths, traversal, external symbolic links, hard links, and special files. Downloads are staged privately and published without replacing another version. No catalog-provided install script is executed.

The catalog is a trusted software source. HTTPS protects delivery and the manifest's checksum validates its archive; a checksum does not authenticate a compromised catalog. Configure only a source you control or trust.

Managers verify the actual executable's identity and version before creating a service or selecting a runtime. Missing initialization tools, dependency failures, or mismatched versions are reported without attaching the binary to a new instance.

Numeric patch versions drive update checks. Managed database maintenance updates retain the existing backup/recovery workflow; major-series changes require another instance and data migration. Managed runtime updates install beside the prior version and change the default only when that version was selected. Existing binaries are not relocated or uninstalled automatically.
