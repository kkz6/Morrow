---
title: Release signing and hosting
description: Sign and notarize customer builds, and publish verified native distributions to object storage.
group: Reference
order: 7.5
---
## Signed application builds

The **Signed macOS release** GitHub Actions workflow runs on main through **Actions → Signed macOS release → Run workflow**. Enter a numeric version such as `0.1.0`. It uses Xcode 27 and its current macOS SDK, while keeping macOS 14 as the minimum supported version. The initial release targets Apple silicon.

Configure these repository secrets through GitHub's encrypted secret storage:

| Secret | Value |
| --- | --- |
| `MORROW_CERTIFICATE_P12_BASE64` | Base64 of the Developer ID Application certificate and private key, exported as an encrypted `.p12` |
| `MORROW_CERTIFICATE_PASSWORD` | Password protecting that `.p12` |
| `MORROW_NOTARY_KEY_BASE64` | Base64 of the dedicated App Store Connect team API key's `.p8` file |
| `MORROW_NOTARY_KEY_ID` | That API key's Key ID |
| `MORROW_NOTARY_ISSUER_ID` | The team's Issuer ID |

Set repository variable `MORROW_APPLE_TEAM_ID` to the certificate's Apple Team ID. Set `MORROW_BINARY_CATALOG_URL` to the public HTTPS catalog to include it as the default source in releases. A user-selected source overrides this default.

The workflow imports the certificate into a temporary keychain, checks its team, signs the app and bundled launcher with hardened runtime and timestamps, and submits an archive to Apple. Only an accepted submission is stapled and packaged. It verifies the ticket and Gatekeeper assessment before producing `Morrow-<version>-macos-arm64.zip`, `SHA256SUMS`, and the notarization reports. On failure, available reports are retained for diagnosis. Temporary credentials and the keychain are removed even after a failed build. Downloads are available under the workflow run's artifacts; this workflow does not automatically publish a GitHub Release.

Never put private keys, certificate passwords, or storage credentials in source files, workflow text, documentation, or chat. Apple Developer membership and a valid Developer ID Application certificate are required. See [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Contabo publisher setup

AWS CLI is an administrator publishing tool. Customers download public HTTPS archives directly through Morrow and do not install it. Install AWS CLI v2 using [AWS's macOS installer](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html); a current-user installation works without Homebrew. This development machine uses `~/.local/bin/aws`.

Configure a dedicated profile locally. Enter access keys only in your own terminal:

```sh
aws configure --profile contabo
aws configure set endpoint_url https://sin1.contabostorage.com --profile contabo
aws configure set s3.addressing_style path --profile contabo
```

Use region `default` for the signing region and output `json`. Choose the endpoint matching your bucket's location; the example is Singapore. Copy `distributions/storage.example.json` to the ignored `distributions/storage.local.json`, then enter your bucket, public download base, endpoint, and profile. The public base uses Contabo's documented tenant-and-bucket URL; it is distinct from the endpoint used by AWS CLI. See [Contabo's object storage documentation](https://docs.contabo.com/docs/storage/object-storage/).

## Publish a prepared native archive

First prepare a complete relocatable distribution and a release descriptor using the [catalog format](/docs/binary-downloads). Include all required libraries, resources, executable paths, redistribution notices, architecture, minimum macOS version, and the archive's SHA-256. Optional `license`, `sourceURL`, `sourceSHA256`, and `notarizationID` fields preserve provenance. Do not upload Homebrew bottles with external Cellar dependencies.

```sh
python3 scripts/publish-binary.py \
  --archive /path/to/distribution.tar.gz \
  --release /path/to/release.json \
  --dry-run

python3 scripts/publish-binary.py \
  --archive /path/to/distribution.tar.gz \
  --release /path/to/release.json \
  --public-read
```

`--dry-run` shows the planned public URLs and descriptor without contacting storage. Publishing checks the local checksum, uploads to a content-addressed key, downloads the public object to verify its bytes, then merges the release into `morrow/catalog.json`. Existing releases with conflicting content are refused. Conditional catalog writes prevent silently overwriting a concurrent publisher; unsupported conditional writes stop publication.

`--public-read` sets the ACL only on the archive and catalog objects being published. It does not make the entire bucket public or change unrelated objects. Omit it when public access is already configured separately. The publisher delegates authentication to AWS CLI's profile and never reads or prints access keys.

For complete source-build recipes and recipes declaring corresponding sources, the publisher also retains their pinned source archives and build dependencies under immutable `sources/` keys. Public source URLs and checksums are attached as `sourceArchives` metadata. This keeps redistribution sources available alongside the binary without adding compiler tools to customer installations. License notices stay inside the package.

After publishing, set the repository's `MORROW_BINARY_CATALOG_URL` variable to the printed catalog URL and build a signed release. Customer releases use this source automatically. For an existing development Mac, set an override with `morrow binary source <url>`. New catalog patch versions become available through Morrow's existing update checks; previous archives remain immutable.

Publication merges the current catalog and uses conditional writes. Returned ETags are normalized for Ceph/Contabo compatibility; concurrent catalog changes still stop publication. Storage failures name the operation and error category without printing credentials.

Hosted distributions include Go for Apple silicon; PHP 8.0.30 CLI/FPM, Node 22.23.3 and 24.22.0 LTS, Caddy 2.11.7, Mailpit 1.31.6, and dnsmasq 2.93 for Apple silicon and Intel. Additional complete packages appear only after their native build, signing, notarization, and publication succeed. Existing services and data continue using their current binaries during this transition.

### Portable PHP preparation

`distributions/php/8.0.30.json` pins the upstream StaticPHP CLI/FPM archives and SHA-256 digests for both architectures. Prepare a fresh signed package directory with:

```sh
python3 scripts/package-php.py --recipe distributions/php/8.0.30.json --output .build/php-release --identity "$MORROW_SIGNING_IDENTITY" --team "$MORROW_EXPECTED_TEAM"
```

Preparation validates archive layout, architecture, minimum macOS, and dependencies restricted to system libraries. It includes upstream license notices, source provenance, and version-specific configuration, then signs each executable with Developer ID. Run `scripts/notarize-php.sh .build/php-release` to notarize its submission ZIP and record the accepted ID in both descriptors before publishing each archive with `scripts/publish-binary.py`. No Homebrew installation or global PHP linking occurs during preparation.

The **Signed PHP distributions** GitHub Actions workflow runs this preparation and notarization with the existing release credentials in a temporary keychain. It uploads signed archives, descriptors, and the Apple acceptance report; download these artifacts to publish through the locally configured object-storage profile. Storage access keys are not needed by this workflow.

### Node and service preparation

The **Complete portable distributions** workflow builds each architecture on a native Mac runner. Its recipes cover PostgreSQL, MySQL, MariaDB, MongoDB, Redis, Valkey, Memcached, Python, Ruby, Flutter, Go, and MinIO. Native source builds use pinned dependencies; complete upstream SDKs retain their libraries, resources, and notices. The publisher rewrites references only to libraries already inside that package, rejects unresolved host dependencies, and signs the relocated code before notarization. Recipes and accepted build artifacts are published before their versions are advertised to customers.

Current PHP source recipes include CLI/FPM and pinned OpenSSL, Oniguruma, ICU, and libzip builds. They supply a trusted certificate bundle and a version-specific INI file; Morrow resolves its own configuration placeholder after download without running an installation script. The older PHP 8.0 StaticPHP workflow remains available for that legacy release.

Ruby's native-extension configuration and PHP's `phpize`/`php-config` helpers use the installed package location rather than the publisher's SDK paths. Building native extensions can still require Xcode and the extension's own development headers; those are development prerequisites rather than a Homebrew requirement for running the packaged runtime.

Signed Go packages retain the compiler, tools, standard library, headers, and source, but omit the compiler suite's `testdata` directories containing deliberately malformed or foreign executables. These fixtures are not required to build Go applications; use the upstream source archive for developing or running Go's own compiler suite.

The **Signed service distributions** workflow uses reviewed recipes in `distributions/<package>/<version>.json`. Recipes cover Node 22.23.3 and 24.22.0 LTS, Caddy 2.11.7, Mailpit 1.31.6, and dnsmasq 2.93 for Apple silicon and Intel. Node includes npm, npx, headers, and its bundled licenses. Caddy and Mailpit use checksum-pinned official release archives. dnsmasq is built from pinned source using Xcode, with optional DHCP, TFTP, scripting, and external library integrations disabled for Morrow's loopback DNS use.

Run the workflow with the package name and exact recipe version. It prepares both architectures, rejects external library dependencies or incorrect minimum macOS declarations, signs all native executables with the release identity, checks the native executable's version, and submits the packages to Apple. Only accepted submissions produce publishable artifacts. Build tools are confined to the publisher's build machine; customers do not need Homebrew, nvm, Git, AWS CLI, or Xcode for these downloads.

Download the workflow artifact and publish each architecture's archive with its corresponding `*-release.json` through `scripts/publish-binary.py`. Storage credentials stay in the locally configured profile. Node descriptors may include `lts: true`; this records the upstream release designation instead of inferring it from a version number. An immutable package is never rebuilt over an existing published version.

## Preserve running services during deployment

Stage a new app with `MORROW_APP_OUTPUT`; do not overwrite executable files used by active service runners. Deploy the entire staged bundle atomically, preserving the previous bundle until its processes have exited. Launch Services registration and scoped attribution cleanup can update association metadata without stopping servers. Already running legacy workers and historical macOS records may remain separate until macOS refreshes or those workers next restart normally. Never reset the global background-task database to force a cosmetic cleanup.
