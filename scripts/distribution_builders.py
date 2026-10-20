"""Publisher-only native builds and relocation for complete Morrow packages."""
import os
from pathlib import Path
import shutil
import subprocess


def command(arguments, cwd, environment):
    subprocess.run([str(v) for v in arguments], cwd=cwd, env=environment, check=True)


def build(recipe, arch, source, root, workspace, cache, fetch, extract):
    sdk = subprocess.check_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    environment = os.environ.copy()
    flags = '-O2 -arch ' + arch + ' -mmacosx-version-min=' + recipe['minimumMacOS'] + ' -isysroot ' + sdk
    environment.update({'SDKROOT': sdk, 'MACOSX_DEPLOYMENT_TARGET': recipe['minimumMacOS'],
                        'CC': '/usr/bin/clang', 'CXX': '/usr/bin/clang++', 'CFLAGS': flags,
                        'CXXFLAGS': flags, 'LDFLAGS': flags, 'PKG_CONFIG_PATH': '',
                        'PKG_CONFIG_LIBDIR': str(workspace / 'dependency/lib/pkgconfig')})
    dependencies = workspace / 'dependency'
    dependencies.mkdir()
    notices = root / 'licenses'; notices.mkdir(parents=True)
    for name, item in recipe.get('dependencies', {}).items():
        directory = workspace / ('dependency-' + name)
        extract(fetch(item, cache), directory)
        upstream = directory / item['rootDirectory']
        notice_root = upstream
        env = environment.copy()
        if name == 'openssl':
            command(['./Configure', 'darwin64-' + ('arm64' if arch == 'arm64' else 'x86_64') + '-cc',
                     'shared' if recipe['package'] == 'postgresql' else 'no-shared', 'no-tests', 'no-legacy', '--prefix=' + str(dependencies),
                     '--openssldir=' + str(dependencies / 'ssl')], upstream, env)
            command(['/usr/bin/make', '-j4'], upstream, env)
            command(['/usr/bin/make', 'install_sw'], upstream, env)
        elif name == 'libevent':
            command(['cmake', '-S', upstream, '-B', directory / 'build',
                     '-DCMAKE_INSTALL_PREFIX=' + str(dependencies), '-DCMAKE_OSX_SYSROOT=' + sdk,
                     '-DCMAKE_OSX_ARCHITECTURES=' + arch, '-DCMAKE_OSX_DEPLOYMENT_TARGET=' + recipe['minimumMacOS'],
                     '-DEVENT__LIBRARY_TYPE=STATIC', '-DEVENT__DISABLE_OPENSSL=ON',
                     '-DEVENT__DISABLE_TESTS=ON', '-DEVENT__DISABLE_REGRESS=ON',
                     '-DEVENT__DISABLE_SAMPLES=ON', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5'], upstream, env)
            command(['cmake', '--build', directory / 'build', '--parallel', '4'], upstream, env)
            command(['cmake', '--install', directory / 'build'], upstream, env)
        elif name in ['libyaml', 'oniguruma']:
            command(['./configure', '--prefix=' + str(dependencies), '--disable-shared', '--enable-static'], upstream, env)
            command(['/usr/bin/make', '-j4'], upstream, env)
            command(['/usr/bin/make', 'install'], upstream, env)
        elif name == 'icu':
            upstream = upstream / 'source'
            command(['./runConfigureICU', 'MacOSX', '--prefix=' + str(dependencies), '--enable-static',
                     '--disable-shared', '--disable-tests', '--disable-samples', '--with-data-packaging=static'], upstream, env)
            command(['/usr/bin/make', '-j4'], upstream, env)
            command(['/usr/bin/make', 'install'], upstream, env)
        elif name == 'libzip':
            command(['cmake', '-S', upstream, '-B', directory / 'build',
                     '-DCMAKE_INSTALL_PREFIX=' + str(dependencies), '-DCMAKE_OSX_SYSROOT=' + sdk,
                     '-DCMAKE_OSX_ARCHITECTURES=' + arch, '-DCMAKE_OSX_DEPLOYMENT_TARGET=' + recipe['minimumMacOS'],
                     '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_TOOLS=OFF', '-DBUILD_REGRESS=OFF', '-DBUILD_EXAMPLES=OFF',
                     '-DENABLE_BZIP2=OFF', '-DENABLE_LZMA=OFF', '-DENABLE_ZSTD=OFF', '-DENABLE_OPENSSL=OFF',
                     '-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local'], upstream, env)
            command(['cmake', '--build', directory / 'build', '--parallel', '4'], upstream, env)
            command(['cmake', '--install', directory / 'build'], upstream, env)
        else:
            raise ValueError('Unsupported pinned build dependency: ' + name)
        for path in notice_root.iterdir():
            if path.is_file() and path.name.upper().startswith(('COPYING', 'LICENSE', 'NOTICE', 'LEGAL')):
                shutil.copy2(path, notices / (name + '-' + path.name))
    for path in (dependencies / 'lib').glob('*.dylib'):
        (root / 'lib').mkdir(exist_ok=True)
        shutil.copy2(path, root / 'lib' / path.name, follow_symlinks=False)
    kind = recipe['build']
    run = lambda arguments, cwd=source: command(arguments, cwd, environment)
    if kind == 'postgresql':
        environment['CPPFLAGS'] = '-I' + str(dependencies / 'include')
        environment['LDFLAGS'] += ' -L' + str(dependencies / 'lib')
        run(['./configure', '--prefix=' + str(root), '--without-icu', '--without-readline',
             '--without-zlib', '--without-lz4', '--without-zstd', '--with-ssl=openssl',
             '--without-libxml', '--without-libxslt', '--disable-nls'])
        run(['/usr/bin/make', '-j4'])
        run(['/usr/bin/make', 'install'])
        # Standard SQL extensions ship alongside the server, not a separate
        # system package. Exclude extensions requiring optional external libs.
        for extension in ['hstore', 'pgcrypto', 'uuid-ossp', 'citext', 'btree_gin', 'btree_gist', 'pg_trgm']:
            if extension == 'uuid-ossp':
                continue
            run(['/usr/bin/make', '-j4', 'all', 'install'], source / 'contrib' / extension)
    elif kind in ['redis', 'valkey']:
        targets = [kind + suffix for suffix in ['-server', '-cli', '-benchmark', '-check-aof', '-check-rdb']]
        run(['/usr/bin/make', '-C', 'src', '-j4', *targets, 'MALLOC=libc', 'BUILD_TLS=no', 'BUILD_WITH_MODULES=no',
             'USE_SYSTEMD=no', 'CC=/usr/bin/clang', 'CFLAGS=' + flags, 'LDFLAGS=' + flags])
        (root / 'bin').mkdir(exist_ok=True)
        for name in [kind + '-server', kind + '-cli', kind + '-benchmark', kind + '-check-aof', kind + '-check-rdb']:
            shutil.copy2(source / 'src' / name, root / 'bin' / name)
    elif kind == 'memcached':
        # Recent macOS SDKs removed the legacy named-sandbox constants. Do not
        # compile that deprecated optional backend into the portable server.
        environment['ac_cv_func_sandbox_init'] = 'no'
        run(['./configure', '--prefix=' + str(root), '--with-libevent=' + str(dependencies),
             '--disable-sasl', '--disable-tls', '--disable-extstore'])
        run(['/usr/bin/make', '-j4', 'memcached'])
        (root / 'bin').mkdir(exist_ok=True)
        shutil.copy2(source / 'memcached', root / 'bin/memcached')
    elif kind == 'mariadb':
        target = workspace / 'build'
        run(['cmake', '-S', source, '-B', target, '-DCMAKE_BUILD_TYPE=Release',
             '-DCMAKE_INSTALL_PREFIX=' + str(root), '-DINSTALL_LAYOUT=STANDALONE',
             '-DCMAKE_OSX_SYSROOT=' + sdk, '-DCMAKE_OSX_ARCHITECTURES=' + arch,
             '-DCMAKE_OSX_DEPLOYMENT_TARGET=' + recipe['minimumMacOS'],
             '-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local',
             '-DCMAKE_PREFIX_PATH=' + str(dependencies), '-DWITH_SSL=' + str(dependencies),
             '-DOPENSSL_USE_STATIC_LIBS=TRUE', '-DWITH_UNIT_TESTS=OFF', '-DWITH_EMBEDDED_SERVER=OFF',
             '-DWITH_WSREP=OFF', '-DWITH_ZLIB=bundled', '-DWITH_PCRE=bundled', '-DWITH_LIBFMT=bundled',
             '-DPLUGIN_ROCKSDB=NO', '-DPLUGIN_MROONGA=NO', '-DPLUGIN_CONNECT=NO',
             '-DPLUGIN_OQGRAPH=NO', '-DPLUGIN_SPIDER=NO', '-DPLUGIN_COLUMNSTORE=NO', '-DPLUGIN_S3=NO'])
        run(['cmake', '--build', target, '--parallel', '4'])
        run(['cmake', '--install', target])
        initializer = root / 'scripts/mariadb-install-db'
        if initializer.is_file() and not (root / 'bin/mariadb-install-db').exists():
            (root / 'bin/mariadb-install-db').symlink_to('../scripts/mariadb-install-db')
    elif kind == 'ruby':
        run(['./configure', '--prefix=' + str(root), '--enable-load-relative', '--enable-shared',
             '--disable-install-doc', '--disable-yjit', '--with-openssl-dir=' + str(dependencies),
             '--with-libyaml-dir=' + str(dependencies), '--with-out-ext=gdbm,dbm'])
        run(['/usr/bin/make', '-j4'])
        run(['/usr/bin/make', 'install'])
    elif kind == 'php':
        include = '-I' + str(dependencies / 'include')
        lib = '-L' + str(dependencies / 'lib')
        environment.update({'CPPFLAGS': include, 'LDFLAGS': flags + ' ' + lib,
                            'OPENSSL_CFLAGS': include, 'OPENSSL_LIBS': lib + ' -lssl -lcrypto',
                            'ONIG_CFLAGS': include, 'ONIG_LIBS': lib + ' -lonig',
                            'ICU_CFLAGS': include, 'ICU_LIBS': lib + ' -licui18n -licuuc -licudata -lc++',
                            'LIBXML_CFLAGS': '-I' + sdk + '/usr/include/libxml2', 'LIBXML_LIBS': '-lxml2',
                            'CURL_CFLAGS': '-I' + sdk + '/usr/include', 'CURL_LIBS': '-lcurl',
                            'SQLITE_CFLAGS': '-I' + sdk + '/usr/include', 'SQLITE_LIBS': '-lsqlite3',
                            'ZLIB_CFLAGS': '-I' + sdk + '/usr/include', 'ZLIB_LIBS': '-lz',
                            'LIBZIP_CFLAGS': include, 'LIBZIP_LIBS': lib + ' -lzip -lz'})
        run(['./configure', '--prefix=' + str(root), '--enable-cli', '--enable-fpm', '--disable-cgi',
             '--disable-phpdbg', '--without-pear', '--with-openssl', '--with-curl', '--with-zlib',
             '--enable-mbstring', '--enable-intl', '--enable-bcmath', '--enable-sockets', '--enable-pcntl',
             '--enable-exif', '--enable-soap', '--enable-ftp', '--with-mysqli=mysqlnd', '--with-pdo-mysql=mysqlnd',
             '--with-sqlite3', '--with-pdo-sqlite', '--with-zip', '--enable-opcache'])
        run(['/usr/bin/make', '-j4'])
        run(['/usr/bin/make', 'install'])
        if (root / 'sbin/php-fpm').exists():
            shutil.move(root / 'sbin/php-fpm', root / 'bin/php-fpm')
        configuration = root / 'etc'; (configuration / 'conf.d').mkdir(parents=True, exist_ok=True)
        extension = subprocess.check_output([str(root / 'bin/php-config'), '--extension-dir'], text=True).strip()
        relative = Path(extension).relative_to(root)
        content = '; Morrow local development configuration\nmemory_limit=256M\ndisplay_errors=On\nlog_errors=On\ndate.timezone=UTC\n'
        content += 'extension_dir="@MORROW_PREFIX@/' + relative.as_posix() + '"\n'
        content += 'openssl.cafile="@MORROW_PREFIX@/etc/ssl/cert.pem"\ncurl.cainfo="@MORROW_PREFIX@/etc/ssl/cert.pem"\n'
        if list((root / relative).glob('opcache.*')):
            content += 'zend_extension=opcache\nopcache.enable_cli=0\nopcache.jit=0\n'
        (configuration / 'php.ini').write_text(content)
    elif kind == 'minio':
        environment.update({'CGO_ENABLED': '0', 'GOOS': 'darwin', 'GOARCH': 'arm64' if arch == 'arm64' else 'amd64',
                            'GOTOOLCHAIN': recipe['buildGoVersion']})
        (root / 'bin').mkdir(exist_ok=True)
        tag = recipe['releaseTag']
        link = '-s -w -X github.com/minio/minio/cmd.Version=' + tag + ' -X github.com/minio/minio/cmd.ReleaseTag=' + tag
        run(['go', 'build', '-mod=readonly', '-trimpath', '-tags', 'osusergo,netgo', '-ldflags', link,
             '-o', root / 'bin/minio', '.'])
    else:
        raise ValueError('Unsupported source builder: ' + kind)
    for path in source.iterdir():
        if path.is_file() and path.name.upper().startswith(('COPYING', 'LICENSE', 'NOTICE', 'LEGAL')):
            shutil.copy2(path, notices / path.name)


def prepare_runtime(recipe, root):
    """Replace publisher-path shebangs without depending on the user's PATH."""
    if recipe['package'] in ['go', 'flutter']:
        # The Go source tree includes deliberately malformed/foreign Mach-O
        # inputs for compiler tests. They are data, not SDK executables; omit
        # those fixtures from the signed runtime while retaining Go sources.
        names = ['testdata'] if recipe['package'] == 'go' else ['testdata', 'test_data', 'fixtures']
        for name in names:
            for directory in sorted(root.rglob(name), key=lambda p: len(p.parts), reverse=True):
                if directory.is_dir() and not directory.is_symlink():
                    shutil.rmtree(directory)
    if recipe['package'] == 'python':
        for binary in (root / 'bin').glob('pip*'):
            if binary.is_file() and not binary.is_symlink():
                binary.write_text('#!/bin/sh\nMORROW_PYTHON_BIN="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\n'
                                  'exec "$MORROW_PYTHON_BIN/python3" -m pip "$@"\n')
                binary.chmod(0o755)
        if not (root / 'bin/pip').exists() and (root / 'bin/pip3').exists():
            (root / 'bin/pip').symlink_to('pip3')
    if recipe['package'] == 'ruby':
        for binary in (root / 'bin').iterdir():
            if binary.is_symlink() or not binary.is_file():
                continue
            data = binary.read_bytes()
            if data.startswith(b'#!') and b'ruby' in data.split(b'\n', 1)[0]:
                text = data.decode()
                lines = text.splitlines(keepends=True)
                # Ruby -x skips the shell preamble and preserves __FILE__ and
                # companion-script locations while using this package's Ruby.
                binary.write_text('#!/bin/sh\nMORROW_RUBY_BIN="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\n'
                                  'exec "$MORROW_RUBY_BIN/ruby" -x "$0" "$@"\n#!/usr/bin/env ruby\n'
                                  + ''.join(lines[1:]))


def mach_files(root):
    for path in root.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as source:
            header = source.read(32)
            magic = header[:4]
            if magic in [b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf']:
                width = 8 if magic[-1] == 0xbf else 4
                source.seek(int.from_bytes(header[16:16 + width], 'big'))
                header = source.read(32); magic = header[:4]
        if magic not in [b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf']:
            continue
        kind = int.from_bytes(header[12:16], 'little' if magic == b'\xcf\xfa\xed\xfe' else 'big')
        # Object files (including Go's cross-architecture .syso race support)
        # are SDK inputs, not loadable executables, libraries, or bundles.
        if kind in [2, 6, 8]:
            yield path


def relocate(root):
    """Resolve only libraries already shipped in this package; never copy host libs."""
    root = root.resolve()
    files = list(mach_files(root))
    for binary in files:
        changes = []
        commands = subprocess.check_output(['/usr/bin/otool', '-l', str(binary)], text=True)
        import re
        platforms = re.findall(r'\bplatform ([A-Za-z0-9_]+)', commands)
        if platforms and not any(value in ['1', 'MACOS', 'macos'] for value in platforms):
            continue
        ids = [line.strip() for line in subprocess.check_output(['/usr/bin/otool', '-D', str(binary)], text=True).splitlines() if line.strip() and not line.endswith(':')]
        if ids:
            changes += ['-id', '@rpath/' + binary.name]
        libraries = subprocess.check_output(['/usr/bin/otool', '-L', str(binary)], text=True).splitlines()[1:]
        for line in libraries:
            if not line[:1].isspace():
                continue
            dependency = line.strip().split(' (compatibility version', 1)[0]
            if dependency in ids or dependency.startswith(('/usr/lib/', '/System/Library/')):
                continue
            candidates = []
            if dependency.startswith('@loader_path/'):
                candidates.append(binary.parent / dependency.removeprefix('@loader_path/'))
            elif dependency.startswith(str(root) + '/'):
                candidates.append(Path(dependency))
            elif dependency.startswith('@executable_path/'):
                candidates.append(root / 'bin' / dependency.removeprefix('@executable_path/'))
            elif dependency.startswith('@rpath/'):
                for rpath in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset', commands):
                    base = rpath.replace('@loader_path', str(binary.parent)).replace('@executable_path', str(root / 'bin'))
                    candidates.append(Path(base) / dependency.removeprefix('@rpath/'))
            valid = {p.resolve() for p in candidates if p.exists() and p.resolve().is_relative_to(root)}
            if not valid:
                valid = {p.resolve() for p in root.rglob(Path(dependency).name) if p.is_file() and p.resolve().is_relative_to(root)}
            if len(valid) != 1:
                raise ValueError('Unresolved or ambiguous bundled library: ' + dependency + ' in ' + str(binary))
            library = next(iter(valid))
            changes += ['-change', dependency, '@loader_path/' + os.path.relpath(library, binary.parent)]
        if changes:
            subprocess.run(['/usr/bin/install_name_tool', *changes, str(binary)], check=True)
