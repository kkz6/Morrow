#!/usr/bin/env python3
"""Publish prepared native archives through AWS CLI; credentials stay in its profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config',type=Path,default=Path('distributions/storage.local.json'))
parser.add_argument('--archive',type=Path,required=True)
parser.add_argument('--release',type=Path,required=True,help='One BinaryRelease JSON object')
parser.add_argument('--dry-run',action='store_true',help='Prepare the upload plan without accessing storage')
parser.add_argument('--public-read',action='store_true',help='Make only the published archive and catalog objects publicly readable')
args=parser.parse_args()

def https(value):
    parsed=urllib.parse.urlparse(value)
    if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or parsed.fragment or parsed.query:
        raise ValueError('Use a stable HTTPS URL without credentials or query parameters.')
    return value.rstrip('/')

def safe_component(value):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,95}',value): raise ValueError('Unsafe package, version or filename.')
    return value

def digest(path):
    result=hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda:source.read(1024*1024),b''): result.update(block)
    return result.hexdigest()

try:
    config=json.loads(args.config.read_text())
    endpoint=https(config['endpointURL']); base=https(config['publicBaseURL'])
    bucket=safe_component(config['bucket'])
    if 'REPLACE' in bucket or 'REPLACE' in base: raise ValueError('Configure the real bucket and public download base first.')
    prefix=config.get('prefix','morrow').strip('/')
    if any(not re.fullmatch(r'[A-Za-z0-9._-]+',x) or x in ['.','..'] for x in prefix.split('/')): raise ValueError('Unsafe storage prefix.')
    release=json.loads(args.release.read_text())
    fields={'package','version','architecture','minimumMacOS','url','sha256','archive','rootDirectory','executables','license','sourceURL','sourceSHA256','notarizationID','lts'}
    if set(release)-fields: raise ValueError('The descriptor contains unknown fields; keep credentials and machine settings out of release metadata.')
    packages={'postgresql','mysql','mariadb','mongodb','redis','valkey','memcached','php','go','flutter','node','python','ruby','caddy','dnsmasq','mailpit','minio'}
    package=safe_component(release['package']); version=safe_component(release['version'])
    architecture=release['architecture']
    if package not in packages or architecture not in ['arm64','x86_64','universal']: raise ValueError('Unsupported package or architecture.')
    if 'lts' in release and (package != 'node' or not isinstance(release['lts'],bool)): raise ValueError('LTS metadata is a Boolean for Node distributions only.')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}',release['minimumMacOS']): raise ValueError('Invalid minimum macOS version.')
    if release['archive'] not in ['tar','zip','binary'] or not isinstance(release['executables'],list) or not release['executables'] or len(release['executables'])>64: raise ValueError('Incomplete release descriptor.')
    for value in [release['rootDirectory'],*release['executables']]:
        if not isinstance(value,str) or value.startswith('/') or '\\' in value or '..' in value.split('/') or '\x00' in value: raise ValueError('Unsafe distribution layout.')
    if release['archive']=='binary' and (release['rootDirectory'] or len(release['executables'])!=1): raise ValueError('Raw binary downloads require one executable and an empty root directory.')
    actual=digest(args.archive)
    if release.get('sha256') and release['sha256'].lower()!=actual: raise ValueError('The archive does not match the release checksum.')
    release['sha256']=actual
    key=f'{prefix}/binaries/{package}/{version}/{architecture}/{actual}/{safe_component(args.archive.name)}'
    catalog_key=f'{prefix}/catalog.json'
    release['url']=base+'/'+urllib.parse.quote(key,safe='/')
    catalog_url=base+'/'+urllib.parse.quote(catalog_key,safe='/')
    if args.dry_run:
        print(json.dumps({'archiveKey':key,'catalogKey':catalog_key,'catalogURL':catalog_url,'release':release},indent=2)); sys.exit(0)
    cli=os.environ.get('AWS_CLI_PATH') or shutil.which('aws')
    if not cli:
        candidate=Path.home()/'.local/bin/aws'
        if candidate.is_file(): cli=str(candidate)
    if not cli: raise ValueError('Install AWS CLI and configure the Contabo profile first.')
    command=[cli,'--profile',config.get('profile','contabo'),'--region',config.get('region','default'),'--endpoint-url',endpoint,'--no-cli-pager','s3api']
    environment=os.environ.copy(); environment['AWS_PAGER']=''
    def aws(*options,check=True):
        result=subprocess.run(command+list(options),capture_output=True,text=True,env=environment)
        if check and result.returncode:
            code=re.search(r'An error occurred \(([A-Za-z0-9]+)\)',result.stderr)
            reason=code.group(1) if code else 'transport or CLI failure'
            raise RuntimeError(f'Object storage {options[0]} failed ({reason}). Check the local profile, endpoint and bucket permissions; credentials were not printed.')
        return result
    with tempfile.TemporaryDirectory(prefix='morrow-publish-') as temporary:
        remote=Path(temporary)/'catalog.json'
        # HEAD avoids an AWS CLI/Ceph error parsing a missing object's GET response.
        existing=aws('head-object','--bucket',bucket,'--key',catalog_key,check=False)
        if existing.returncode:
            if 'NoSuchKey' not in existing.stderr and '404' not in existing.stderr: raise RuntimeError('The catalog could not be checked; publication stopped before uploading.')
            catalog={'schemaVersion':1,'releases':[]}; previous_etag=None
        else:
            aws('get-object','--bucket',bucket,'--key',catalog_key,str(remote))
            catalog=json.loads(remote.read_text()); previous_etag=json.loads(existing.stdout).get('ETag')
        if catalog.get('schemaVersion')!=1 or not isinstance(catalog.get('releases'),list): raise ValueError('Existing catalog has an unsupported schema.')
        tuple_key=(package,version,architecture)
        old=next((item for item in catalog['releases'] if (item['package'],item['version'],item['architecture'])==tuple_key),None)
        if old and old['sha256']!=actual: raise ValueError('This release already exists with different contents. Publish a new revision instead.')
        found=aws('head-object','--bucket',bucket,'--key',key,check=False)
        if found.returncode==0:
            if json.loads(found.stdout).get('Metadata',{}).get('sha256')!=actual: raise ValueError('The existing object has conflicting checksum metadata.')
        elif 'Not Found' in found.stderr or '404' in found.stderr or 'NoSuchKey' in found.stderr:
            acl=['--acl','public-read'] if args.public_read else []
            aws('put-object','--bucket',bucket,'--key',key,'--body',str(args.archive.resolve()),'--metadata',json.dumps({'sha256':actual}),'--content-type','application/octet-stream','--cache-control','public, max-age=31536000, immutable',*acl)
        else: raise RuntimeError('The immutable archive key could not be checked; nothing was replaced.')
        # Read the public object before advertising it. Object ACLs/public access
        # are configured by the owner; this tool never changes bucket policy.
        request=urllib.request.Request(release['url'],headers={'User-Agent':'Morrow-Publisher/1'})
        class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self,request,fp,code,msg,headers,newurl):
                if urllib.parse.urlparse(newurl).scheme!='https': raise ValueError('Public downloads must remain on HTTPS.')
                return super().redirect_request(request,fp,code,msg,headers,newurl)
        with urllib.request.build_opener(HTTPSRedirect()).open(request,timeout=60) as response:
            if urllib.parse.urlparse(response.url).scheme!='https': raise ValueError('Public downloads must remain on HTTPS.')
            downloaded=hashlib.sha256()
            for block in iter(lambda:response.read(1024*1024),b''): downloaded.update(block)
        if downloaded.hexdigest()!=actual: raise ValueError('Public archive checksum failed; the catalog was not changed.')
        if not old: catalog['releases'].append(release)
        remote.write_text(json.dumps(catalog,indent=2)+'\n')
        latest=aws('head-object','--bucket',bucket,'--key',catalog_key,check=False)
        if previous_etag is not None:
            if latest.returncode or json.loads(latest.stdout).get('ETag')!=previous_etag: raise ValueError('The catalog changed during upload. Retry to merge the latest releases.')
        elif latest.returncode==0: raise ValueError('Another publisher created the catalog. Retry to merge it.')
        # Conditional writes fail safely if a provider does not implement them.
        # Ceph accepts the ETag digest here; passing the literal response quotes
        # can return an empty precondition error that AWS CLI cannot parse.
        condition=['--if-match',previous_etag.strip('"')] if previous_etag else ['--if-none-match','*']
        acl=['--acl','public-read'] if args.public_read else []
        aws('put-object','--bucket',bucket,'--key',catalog_key,'--body',str(remote),'--content-type','application/json','--cache-control','public, max-age=300',*condition,*acl)
    print('Published verified binary: '+release['url'])
    print('Catalog: '+catalog_url)
except Exception as error:
    print(str(error),file=sys.stderr); sys.exit(1)
