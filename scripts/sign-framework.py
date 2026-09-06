#!/usr/bin/env python3
"""Package only arm64, then sign Sparkle's nested code from the inside out."""
import os
import pathlib
import stat
import subprocess
import sys

framework = pathlib.Path(sys.argv[1])
identity = sys.argv[2]
for path in framework.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    kind = subprocess.check_output(['file', '-b', str(path)], text=True)
    if not kind.startswith('Mach-O'):
        continue
    arches = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
    if 'arm64' not in arches:
        sys.exit(f'Missing arm64 slice: {path.name}')
    if len(arches) > 1:
        mode = stat.S_IMODE(path.stat().st_mode)
        thin = path.with_name(path.name + '.arm64-tmp')
        subprocess.run(['lipo', str(path), '-thin', 'arm64', '-output', str(thin)], check=True)
        os.chmod(thin, mode)
        thin.replace(path)

version = framework / 'Versions/B'
targets = [version / 'Autoupdate', version / 'Updater.app',
           version / 'XPCServices/Installer.xpc', version / 'XPCServices/Downloader.xpc', framework]
for target in targets:
    args = ['codesign', '--force', '--options', '0' if identity == '-' else 'runtime', '--preserve-metadata=entitlements', '--sign', identity]
    if identity != '-':
        args += ['--timestamp']
    subprocess.run(args + [str(target)], check=True)
