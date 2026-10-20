#!/usr/bin/env python3
"""Prepare checksum-pinned, signed portable distributions on a Mac build runner.

Recipes are reviewed build inputs, never customer installation scripts. New
packages stay private until Apple accepts the submission and they are published.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shlex
import shutil
import subprocess
import tarfile
import zipfile
import stat
from urllib.parse import urlparse
from distribution_builders import build, prepare_runtime, relocate, mach_files


def run(*command, **kwargs):
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, **kwargs)
    except subprocess.CalledProcessError as error:
        raise RuntimeError('Distribution command failed: ' + error.output[-6000:]) from error


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def fetch(source, cache):
    url = urlparse(source['url'])
    checksum = source['sha256']
    if (url.scheme != 'https' or not url.hostname or url.username or url.password
            or not re.fullmatch(r'[a-f0-9]{64}', checksum)):
        raise ValueError('Inputs require public HTTPS and a pinned SHA-256 digest.')
    path = cache / checksum
    if not path.exists():
        temporary = path.with_suffix('.part')
        subprocess.run(['/usr/bin/curl', '--fail', '--silent', '--show-error', '--location',
                        '--proto', '=https', '--proto-redir', '=https', '--retry', '3',
                        '--retry-all-errors', '--max-time', '1800', source['url'], '-o', str(temporary)], check=True)
        temporary.rename(path)
    if digest(path) != checksum:
        raise ValueError('Upstream checksum mismatch; publication stopped.')
    return path


def inside(root, path):
    return path.resolve().is_relative_to(root.resolve())


def extract(path, target):
    """Extract regular files first so an archive link can never redirect a write."""
    target.mkdir(parents=True)
    if zipfile.is_zipfile(path):
        links, total = [], 0
        with zipfile.ZipFile(path) as archive:
            seen = set()
            for entry in archive.infolist():
                name = PurePosixPath(entry.filename)
                if name.is_absolute() or '..' in name.parts or str(name) in seen or len(seen) >= 100000:
                    raise ValueError('Unsafe ZIP layout.')
                seen.add(str(name)); destination = target / str(name)
                mode = entry.external_attr >> 16
                total += entry.file_size
                if total > 8 * 1024**3:
                    raise ValueError('The SDK is too large.')
                if entry.is_dir():
                    destination.mkdir(parents=True, exist_ok=True)
                elif stat.S_ISLNK(mode):
                    link = archive.read(entry).decode()
                    if link.startswith('/') or not inside(target, destination.parent / link):
                        raise ValueError('A ZIP link escapes its archive.')
                    links.append((destination, link))
                else:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(entry) as source, destination.open('xb') as output:
                        shutil.copyfileobj(source, output)
                    destination.chmod(0o755 if mode & 0o111 else 0o644)
            for destination, link in links:
                destination.parent.mkdir(parents=True, exist_ok=True); destination.symlink_to(link)
        return
    links, seen, total = [], set(), 0
    with tarfile.open(path) as archive:
        for index, entry in enumerate(archive):
            name = PurePosixPath(entry.name)
            if name.is_absolute() or '..' in name.parts or '\\' in entry.name or index >= 100000:
                raise ValueError('Unsafe archive layout.')
            if str(name) == '.':
                continue
            if str(name) in seen:
                if entry.isdir() and (target / str(name)).is_dir():
                    continue
                raise ValueError('Duplicate archive entry.')
            seen.add(str(name))
            destination = target / str(name)
            if entry.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            elif entry.isfile():
                total += entry.size
                if total > 8 * 1024**3:
                    raise ValueError('Upstream archive is too large.')
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(entry) as source, destination.open('xb') as output:
                    shutil.copyfileobj(source, output)
                destination.chmod(0o755 if entry.mode & 0o111 else 0o644)
                # Released configure/parser files already have the right
                # generation order. Preserve it instead of triggering host
                # autotools solely because of archive entry order.
                os.utime(destination, (entry.mtime, entry.mtime))
            elif entry.issym():
                link = PurePosixPath(entry.linkname)
                if link.is_absolute() or not inside(target, destination.parent / str(link)):
                    raise ValueError('An upstream link escapes its archive.')
                links.append((destination, entry.linkname))
            else:
                raise ValueError('Special files and hard links are not distribution inputs.')
    for destination, link in links:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.symlink_to(link)
    for destination, _ in links:
        if not inside(target, destination):
            raise ValueError('An upstream link chain escapes its archive.')


def os_version(value):
    return tuple((list(map(int, value.split('.'))) + [0, 0, 0])[:3])


def sign_tree(root, arch, recipe, args, entitlements):
    count = 0
    bundles = set()
    for binary in sorted(mach_files(root)):
        commands = run('/usr/bin/otool', '-l', str(binary))
        platforms = re.findall(r'\bplatform ([A-Za-z0-9_]+)', commands)
        if recipe['package'] == 'flutter' and platforms and not any(v in ['1', 'MACOS', 'macos'] for v in platforms):
            # iOS/Android target artifacts are kept with their upstream signing.
            continue
        if arch not in run('/usr/bin/lipo', '-archs', str(binary)).split() and recipe['package'] != 'flutter':
            raise ValueError('The executable architecture differs from the recipe: ' + str(binary))
        minimum = re.search(r'\bminos ([0-9.]+)', commands) or re.search(r'LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([0-9.]+)', commands)
        if minimum is None or os_version(minimum.group(1)) > os_version(recipe['minimumMacOS']):
            required = minimum.group(1) if minimum else 'unknown'
            raise ValueError('An executable needs macOS ' + required + ', exceeding declared ' + recipe['minimumMacOS'] + ': ' + str(binary))
        identities = {line.strip() for line in run('/usr/bin/otool', '-D', str(binary)).splitlines()
                      if line.strip() and not line.endswith(':')}
        dependencies = run('/usr/bin/otool', '-L', str(binary)).splitlines()[1:]
        for line in dependencies:
            if not line[:1].isspace():
                continue
            dependency = line.strip().split(' (compatibility version', 1)[0]
            if dependency.startswith(('/usr/lib/', '/System/Library/')) or dependency in identities:
                continue
            if dependency.startswith('@loader_path/'):
                library = binary.parent / dependency.removeprefix('@loader_path/')
                if library.is_file() and inside(root, library):
                    continue
            raise ValueError('A package depends on libraries outside its archive: ' + dependency + ' in ' + str(binary))
        command = ['/usr/bin/codesign', '--force', '--sign', args.identity, '--options', 'runtime', '--timestamp']
        if recipe['package'] in ['node', 'python', 'ruby', 'flutter', 'php']:
            command += ['--entitlements', str(entitlements)]
        subprocess.run(command + [str(binary)], check=True)
        if 'TeamIdentifier=' + args.team not in run('/usr/bin/codesign', '-dv', '--verbose=4', str(binary)):
            raise ValueError('The binary belongs to another signing team.')
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(binary)], check=True)
        for parent in binary.parents:
            if parent == root:
                break
            if parent.suffix in ['.framework', '.app']:
                bundles.add(parent)
        count += 1
    # Seal native macOS bundles after relocating/signing their contained code.
    # Foreign target bundles never enter this set and retain upstream signing.
    for bundle in sorted(bundles, key=lambda path: len(path.parts), reverse=True):
        command = ['/usr/bin/codesign', '--force', '--sign', args.identity, '--options', 'runtime', '--timestamp']
        if bundle.suffix == '.app':
            command += ['--entitlements', str(entitlements)]
        subprocess.run(command + [str(bundle)], check=True)
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(bundle)], check=True)
        if 'TeamIdentifier=' + args.team not in run('/usr/bin/codesign', '-dv', '--verbose=4', str(bundle)):
            raise ValueError('The SDK bundle belongs to another signing team.')
    if count == 0:
        raise ValueError('No native executable was packaged.')


def prepare(args):
    recipe = json.loads(args.recipe.read_text())
    package, version = recipe['package'], recipe['version']
    if (recipe['schemaVersion'] != 1 or package not in ['node', 'caddy', 'mailpit', 'dnsmasq', 'postgresql', 'mysql', 'mariadb', 'mongodb', 'redis', 'valkey', 'memcached', 'python', 'ruby', 'flutter', 'go', 'minio', 'php']
            or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,95}', version)):
        raise ValueError('Unsupported distribution recipe.')
    if args.identity == '-' or not re.fullmatch(r'[A-Z0-9]{10}', args.team):
        raise ValueError('Use a Developer ID signing identity and its Apple team.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cache = output / 'sources'; cache.mkdir(exist_ok=True)
    packages = output / 'packages'; packages.mkdir(exist_ok=True)
    entitlements = output / 'node.entitlements.plist'
    entitlements.write_bytes(plistlib.dumps({
        'com.apple.security.cs.allow-jit': True,
        'com.apple.security.cs.allow-unsigned-executable-memory': True,
        'com.apple.security.cs.disable-library-validation': True,
    }))
    for arch, source in recipe['sources'].items():
        if args.arch and arch != args.arch:
            continue
        if arch not in ['arm64', 'x86_64']:
            raise ValueError('Unsupported CPU architecture.')
        workspace = output / ('work-' + arch)
        extract(fetch(source, cache), workspace)
        upstream = workspace / source['rootDirectory']
        if not inside(workspace, upstream) or not upstream.is_dir():
            raise ValueError('Missing upstream package root.')
        root = packages / arch / (package + '-' + version)
        if root.exists():
            raise ValueError('Use a fresh output directory; existing packages are preserved.')
        if recipe['layout'] == 'source':
            build(recipe, arch, upstream, root, workspace, cache, fetch, extract)
        elif recipe['layout'] == 'tree':
            root.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(upstream), str(root))
        else:
            (root / 'bin').mkdir(parents=True)
            if recipe['layout'] == 'single':
                binary = upstream / recipe['binary']
                if not inside(upstream, binary) or not binary.is_file():
                    raise ValueError('The upstream executable is missing.')
                shutil.copy2(binary, root / 'bin' / package)
                for path in upstream.iterdir():
                    if path.is_file() and path.name != recipe['binary']:
                        shutil.copy2(path, root / path.name)
            elif recipe['layout'] == 'dnsmasq-source' and package == 'dnsmasq':
                # Morrow uses loopback DNS only. Disable optional services and
                # third-party library integrations at build time.
                env = os.environ.copy()
                sdk = run('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path').strip()
                compiler = run('/usr/bin/xcrun', '--find', 'clang').strip()
                flags = '-O2 -arch ' + arch + ' -mmacosx-version-min=' + recipe['minimumMacOS'] + ' -isysroot ' + shlex.quote(sdk)
                env.update({'MACOSX_DEPLOYMENT_TARGET': recipe['minimumMacOS'], 'SDKROOT': sdk})
                # Explicit make arguments survive its recursive Makefiles;
                # environment CFLAGS can be replaced by upstream defaults.
                subprocess.run(['/usr/bin/make', '-j4', 'CC=' + compiler, 'CFLAGS=' + flags, 'LDFLAGS=' + flags,
                                'COPTS=-DNO_DHCP -DNO_TFTP -DNO_SCRIPT -DNO_AUTH -DNO_IPSET -DNO_NFTSET'], cwd=upstream, env=env, check=True)
                shutil.copy2(upstream / 'src/dnsmasq', root / 'bin/dnsmasq')
                for name in ['COPYING', 'COPYING-v3', 'dnsmasq.conf.example']:
                    shutil.copy2(upstream / name, root / name)
            else:
                raise ValueError('Unsupported package layout.')
        for notice in recipe.get('notices', []):
            if not re.fullmatch(r'[A-Za-z0-9_.-]+', notice['name']):
                raise ValueError('Invalid license notice filename.')
            shutil.copyfile(fetch(notice, cache), root / notice['name'])
        for item in recipe.get('files', []):
            destination = root / item['path']
            if not inside(root, destination):
                raise ValueError('A recipe resource escapes its package.')
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(fetch(item, cache), destination)
        for name in recipe['executables']:
            binary = root / name
            if not inside(root, binary) or not binary.is_file():
                raise ValueError('A required executable is missing: ' + name)
            binary.chmod(0o755)
        prepare_runtime(recipe, root)
        relocate(root)
        (root / 'SOURCES.json').write_text(json.dumps(recipe, indent=2) + '\n')
        sign_tree(root, arch, recipe, args, entitlements)
        if platform.machine() == arch:
            identity = run(str(root / recipe['executables'][0]), *recipe['versionArguments'])
            if not re.search(recipe['versionPattern'], identity):
                raise ValueError('The executable reports a different version: ' + identity)
            if package == 'node':
                # Run the bundled npm script with this Node, independent of PATH.
                run(str(root / 'bin/node'), str(root / 'bin/npm'), '--version')
        archive_path = output / (package + '-' + version + '-macos-' + arch + '.tar.gz')
        with tarfile.open(archive_path, 'w:gz') as archive:
            archive.add(root, arcname=root.name)
        descriptor = {'package': package, 'version': version, 'architecture': arch,
                      'minimumMacOS': recipe['minimumMacOS'], 'archive': 'tar', 'rootDirectory': root.name,
                      'executables': recipe['executables'], 'sha256': digest(archive_path),
                      'license': recipe['license'], 'sourceURL': recipe['provider'],
                      'sourceSHA256': digest(args.recipe)}
        if 'lts' in recipe:
            descriptor['lts'] = recipe['lts']
        (output / (arch + '-release.json')).write_text(json.dumps(descriptor, indent=2) + '\n')
        print('Prepared ' + archive_path.name, flush=True)
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(packages), str(output / 'notary-submission.zip')], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--team', required=True)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'])
    prepare(parser.parse_args())
