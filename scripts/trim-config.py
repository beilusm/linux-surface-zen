#!/usr/bin/env python3
"""Create explicit hardware pruning overrides from the pinned source Kconfigs.

Never uses the set of currently loaded modules to decide what to remove.
Run olddefconfig afterward; review the resulting dependency removals separately.
"""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('kernel', type=Path)
parser.add_argument('baseline', type=Path)
parser.add_argument('policy', type=Path)
parser.add_argument('fragment', type=Path)
parser.add_argument('report', type=Path)
args = parser.parse_args()
policy = json.loads(args.policy.read_text())
baseline = dict(re.findall(r'^CONFIG_(\w+)=(.*)$', args.baseline.read_text(), re.M))
exceptions = set(policy['path_symbol_exceptions'])
skip = policy['skip_kconfig_subtrees']
removed = {}
for reason, paths in policy['groups'].items():
    for relative in paths:
        path = args.kernel / relative
        if not path.exists():
            raise SystemExit(f'Missing policy source path: {relative}; review for this version')
        files = sorted(path.rglob('Kconfig*')) if path.is_dir() else [path]
        for file in files:
            relative_file = str(file.relative_to(args.kernel))
            if any(relative_file.startswith(s + '/') for s in skip):
                continue
            for name in re.findall(r'^(?:menu)?config\s+(\w+)', file.read_text(), re.M):
                if name not in exceptions and baseline.get(name) in ('m', 'y'):
                    removed[name] = reason
for name, reason in policy['disable_symbols'].items():
    if baseline.get(name) in ('m', 'y'):
        removed[name] = reason
lines = ['# Generated from configs/policies/surface-pro7.json; no localmodconfig.']
for name, reason in sorted(removed.items()):
    lines.extend([f'# {reason}', f'# CONFIG_{name} is not set'])
for name, value in policy['enable_symbols'].items():
    lines.append(f'CONFIG_{name}={value}')
args.fragment.write_text('\n'.join(lines) + '\n')
args.report.write_text(json.dumps(removed, indent=2, sort_keys=True) + '\n')
print(f'Explicitly disabled {len(removed)} enabled options; normalize and audit dependencies next')
