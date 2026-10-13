#!/usr/bin/env python3
"""Prepare signed portable PHP CLI/FPM archives from checksum-pinned upstream builds.

Only preparation occurs here. Notarize the returned submission ZIP and publish
accepted archives with publish-binary.py. No Homebrew installation is used.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import platform
import shutil
import subprocess
import tarfile
from urllib.parse import urlparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--recipe', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--identity', required=True)
parser.add_argument('--team', required=True)
args = parser.parse_args()


def run(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT)


def fetch(url, target, sha256=None):
    parsed = urlparse(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('Distribution inputs must use public HTTPS URLs.')
    if not target.exists():
        temporary = target.with_suffix(target.suffix + '.part')
        subprocess.run(['/usr/bin/curl', '--fail', '--silent', '--show-error', '--location', '--http1.1', '--retry', '3', '--retry-all-errors',
                        '--proto', '=https', '--proto-redir', '=https', '--max-time', '120',
                        url, '-o', str(temporary)], check=True)
        temporary.rename(target)
    if sha256 and hashlib.sha256(target.read_bytes()).hexdigest() != sha256:
        raise ValueError('Upstream archive checksum mismatch: ' + target.name)


def prepare():
    recipe = json.loads(args.recipe.read_text())
    version = recipe['version']
    if recipe['schemaVersion'] != 1 or not re.fullmatch(r'8\.[0-9]+\.[0-9]+', version):
        raise ValueError('Unsupported PHP distribution recipe.')
    if args.identity == '-' or not re.fullmatch(r'[A-Z0-9]{10}', args.team):
        raise ValueError('Use a Developer ID signing identity and its Apple team.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cache = output / 'sources'; cache.mkdir(exist_ok=True)
    licenses = output / 'licenses'; licenses.mkdir(exist_ok=True)
    license_base = recipe['licenseDirectory'].rstrip('/') + '/'
    index = cache / 'licenses.json'
    fetch(license_base + '?format=json', index)
    notices = [entry['name'] for entry in json.loads(index.read_text())
               if not entry['is_dir'] and not entry.get('is_parent')]
    if not notices or any(not re.fullmatch(r'[A-Za-z0-9_.-]+\.txt', name) for name in notices):
        raise ValueError('Unexpected upstream license directory.')
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(lambda name: fetch(license_base + name, licenses / name), notices))
    entitlements = output / 'php.entitlements.plist'
    import plistlib
    entitlements.write_bytes(plistlib.dumps({
        'com.apple.security.cs.allow-jit': True,
        'com.apple.security.cs.allow-unsigned-executable-memory': True,
        'com.apple.security.cs.disable-library-validation': True,
    }))
    packages = output / 'packages'; packages.mkdir(exist_ok=True)
    for arch, sources in recipe['sources'].items():
        if arch not in ['arm64', 'x86_64'] or set(sources) != {'php', 'php-fpm'}:
            raise ValueError('A PHP package needs native CLI and FPM binaries.')
        root = packages / arch / ('php-' + version)
        if root.exists():
            raise ValueError('Use a new output directory; existing packages are never replaced.')
        (root / 'bin').mkdir(parents=True)
        for name, source in sources.items():
            archive_path = cache / Path(urlparse(source['url']).path).name
            fetch(source['url'], archive_path, source['sha256'])
            with tarfile.open(archive_path) as archive:
                entries = archive.getmembers()
                if len(entries) != 1 or not entries[0].isfile() or entries[0].name != name or entries[0].size > 512 * 1024 * 1024:
                    raise ValueError('Unexpected upstream PHP archive layout.')
                binary = root / 'bin' / name
                binary.write_bytes(archive.extractfile(entries[0]).read()); binary.chmod(0o755)
            if run('/usr/bin/lipo', '-archs', str(binary)).strip() != arch:
                raise ValueError('The upstream PHP architecture does not match the recipe.')
            load_commands = run('/usr/bin/otool', '-l', str(binary))
            minimum = re.search(r'\bminos ([0-9.]+)', load_commands) or re.search(r'LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([0-9.]+)', load_commands)
            declared = tuple((list(map(int, recipe['minimumMacOS'].split('.'))) + [0, 0, 0])[:3])
            required = tuple((list(map(int, minimum.group(1).split('.'))) + [0, 0, 0])[:3]) if minimum else None
            if required is None or required > declared:
                raise ValueError('The upstream binary requires a newer macOS than the release declares.')
            dependencies = run('/usr/bin/otool', '-L', str(binary)).splitlines()[1:]
            if any(not line.strip().startswith(('/usr/lib/', '/System/Library/')) for line in dependencies):
                raise ValueError('PHP depends on a library outside macOS; do not publish it.')
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', args.identity, '--options', 'runtime',
                            '--timestamp', '--entitlements', str(entitlements), str(binary)], check=True)
            details = run('/usr/bin/codesign', '-dv', '--verbose=4', str(binary))
            if 'TeamIdentifier=' + args.team not in details:
                raise ValueError('The PHP signing identity belongs to another team.')
            subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(binary)], check=True)
            if platform.machine() == arch and not re.search(r'PHP ' + re.escape(version) + r'\b', run(str(binary), '-n', '--version')):
                raise ValueError('The native PHP executable reports a different release.')
        (root / 'etc/conf.d').mkdir(parents=True)
        (root / 'etc/php.ini').write_text('; Morrow PHP ' + version + ' local development configuration\n'
                                       'memory_limit = 256M\ndisplay_errors = On\nlog_errors = On\n'
                                       'error_reporting = E_ALL\ndate.timezone = UTC\n'
                                       'opcache.enable_cli = 0\nopcache.jit = 0\n')
        (root / 'etc/conf.d/README.txt').write_text('Place version-compatible PHP INI files in this directory.\n')
        shutil.copytree(licenses, root / 'licenses')
        (root / 'SOURCES.json').write_text(json.dumps(recipe, indent=2) + '\n')
        archive_path = output / ('php-' + version + '-macos-' + arch + '.tar.gz')
        with tarfile.open(archive_path, 'w:gz') as archive:
            archive.add(root, arcname=root.name)
        release = {'package': 'php', 'version': version, 'architecture': arch,
                   'minimumMacOS': recipe['minimumMacOS'], 'archive': 'tar', 'rootDirectory': root.name,
                   'executables': ['bin/php', 'bin/php-fpm'],
                   'sha256': hashlib.sha256(archive_path.read_bytes()).hexdigest(),
                   'license': 'PHP-3.01 and bundled third-party licenses; see licenses/',
                   'sourceURL': recipe['provider'],
                   'sourceSHA256': hashlib.sha256(args.recipe.read_bytes()).hexdigest()}
        (output / (arch + '-release.json')).write_text(json.dumps(release, indent=2) + '\n')
        print('Prepared ' + str(archive_path), flush=True)
    submission = output / 'php-notary-submission.zip'
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(packages), str(submission)], check=True)
    print('Submit to Apple before publication: ' + str(submission), flush=True)


if __name__ == '__main__':
    prepare()
