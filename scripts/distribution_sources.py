"""Retain checksum-pinned corresponding sources beside published binaries."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile
from urllib.parse import urlparse, quote
import urllib.request


def publish_sources(archive, release, aws, bucket, prefix, public_base, public_read):
    inputs = []
    with tarfile.open(archive) as payload:
        name = release['rootDirectory'].rstrip('/') + '/SOURCES.json'
        try:
            entry = payload.getmember(name)
        except KeyError:
            return []
        if not entry.isfile() or entry.size > 262144:
            raise ValueError('Invalid package source provenance.')
        recipe = json.load(payload.extractfile(entry))
        if recipe.get('package') != release['package'] or recipe.get('version') != release['version']:
            # The original PHP 8.0 recipe predates the generic schema.
            return []
        if recipe.get('layout') == 'source':
            inputs.append(recipe['sources'][release['architecture']])
            inputs.extend(recipe.get('dependencies', {}).values())
        inputs.extend(recipe.get('sourceArchives', []))
    cache = Path('.build/published-sources'); cache.mkdir(parents=True, exist_ok=True)
    results, seen = [], set()
    for item in inputs:
        digest = item['sha256']
        source = urlparse(item['url'])
        if (source.scheme != 'https' or not source.hostname or source.username or source.password or source.query
                or not re.fullmatch(r'[a-f0-9]{64}', digest)):
            raise ValueError('Source archives need public HTTPS URLs and pinned checksums.')
        if digest in seen:
            continue
        seen.add(digest)
        name = Path(source.path).name
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', name):
            raise ValueError('Invalid source archive name.')
        path = cache / digest
        if not path.exists():
            temporary = path.with_suffix('.part')
            subprocess.run(['/usr/bin/curl', '--fail', '--silent', '--show-error', '--location',
                            '--proto', '=https', '--proto-redir', '=https', '--retry', '3', '--retry-all-errors',
                            '--max-time', '1800', item['url'], '-o', str(temporary)], check=True)
            temporary.rename(path)
        value = hashlib.sha256()
        with path.open('rb') as file:
            for block in iter(lambda: file.read(1024 * 1024), b''):
                value.update(block)
        if value.hexdigest() != digest:
            raise ValueError('A corresponding source checksum failed; publication stopped.')
        key = prefix + '/sources/' + digest + '/' + name
        found = aws('head-object', '--bucket', bucket, '--key', key, check=False)
        if found.returncode == 0:
            if json.loads(found.stdout).get('Metadata', {}).get('sha256') != digest:
                raise ValueError('Conflicting immutable source archive metadata.')
        elif '404' in found.stderr or 'NoSuchKey' in found.stderr or 'Not Found' in found.stderr:
            acl = ['--acl', 'public-read'] if public_read else []
            aws('put-object', '--bucket', bucket, '--key', key, '--body', str(path.resolve()),
                '--metadata', json.dumps({'sha256': digest}), '--content-type', 'application/octet-stream',
                '--cache-control', 'public, max-age=31536000, immutable', *acl)
        else:
            raise RuntimeError('The source archive could not be checked; nothing was replaced.')
        url = public_base + '/' + quote(key, safe='/')
        request = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'Morrow-Publisher/1'})
        with urllib.request.urlopen(request, timeout=60) as response:
            if (urlparse(response.url).scheme != 'https' or int(response.headers['Content-Length']) != path.stat().st_size
                    or response.headers.get('x-amz-meta-sha256') != digest):
                raise ValueError('Published corresponding source metadata did not match.')
        results.append({'url': url, 'sha256': digest, 'upstreamURL': item['url']})
    return results
