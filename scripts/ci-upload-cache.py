#!/usr/bin/env python3
"""Resume a local seed upload and dispatch the cloud build once it is complete."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--repo', required=True)
parser.add_argument('--tag', required=True)
parser.add_argument('--directory', required=True, type=Path)
parser.add_argument('--wait-pid', type=int)
args = parser.parse_args()
root = args.directory.resolve()
status_path = root / 'cloud-transfer.json'


def status(state, **details):
    status_path.write_text(json.dumps({'state': state, **details}, indent=2) + '\n')
    print(state, details, flush=True)


def gh(*arguments):
    return subprocess.check_output(['gh', *arguments], text=True)


try:
    # A service can adopt an already-running upload without polling or issuing
    # overlapping --clobber operations against the same remote assets.
    if args.wait_pid:
        status('waiting for existing upload', pid=args.wait_pid)
        try:
            fd = os.pidfd_open(args.wait_pid)
        except ProcessLookupError:
            pass
        else:
            select.select([fd], [], [])
            os.close(fd)

    manifest = json.loads((root / 'manifest.json').read_text())
    profile = manifest['profile']
    flavor = manifest['flavor']
    assert re.fullmatch(r'\d+\.\d+\.\d+-zen\d+', profile)
    assert flavor in ('pro7', 'full') and manifest['schema'] == 1
    checksums = {}
    for line in (root / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        assert re.fullmatch(r'[a-zA-Z0-9_.-]+', name)
        assert re.fullmatch(r'[0-9a-f]{64}', digest)
        checksums[name] = digest
    status('verifying local export', files=len(checksums))
    for name, expected in checksums.items():
        path = root / name
        assert path.is_file() and not path.is_symlink()
        with path.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha256').hexdigest()
        assert actual == expected, f'Checksum mismatch: {name}'

    release = json.loads(gh('api', f'repos/{args.repo}/releases/tags/{args.tag}'))
    existing = {asset['name']: asset for asset in release['assets']}
    names = sorted(name for name in checksums if name.startswith('cache.tar.zst.part-'))
    assert names
    status('uploading', chunks=len(names), total_bytes=sum((root / n).stat().st_size for n in names))

    def upload(name):
        path = root / name
        asset = existing.get(name, {})
        if asset.get('state') == 'uploaded' and asset.get('size') == path.stat().st_size:
            # The runner also verifies SHA256SUMS before extracting any data.
            print('Already uploaded:', name, flush=True)
            return
        for attempt in range(1, 4):
            proc = subprocess.run(
                ['gh', 'release', 'upload', args.tag, str(path), '--repo', args.repo, '--clobber'],
                text=True, capture_output=True)
            if proc.returncode == 0:
                print('Uploaded:', name, flush=True)
                return
            print(f'Upload attempt {attempt} failed for {name}: {proc.stderr[:400]}', flush=True)
        raise RuntimeError(f'Could not upload {name}')

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(upload, names))
    upload('manifest.json')
    upload('SHA256SUMS')
    status('dispatching cloud build', profile=profile, flavor=flavor)
    output = gh('workflow', 'run', 'kernel.yml', '--repo', args.repo, '--ref', 'main',
                '-f', f'flavor={flavor}', '-f', f'bootstrap_tag={args.tag}')
    print(output, flush=True)
    urls = re.findall(r'https://github\.com/[^\s]+/actions/runs/\d+', output)
    status('cloud build dispatched', url=urls[-1] if urls else f'https://github.com/{args.repo}/actions')
except BaseException as error:
    status('failed', error=str(error))
    raise
