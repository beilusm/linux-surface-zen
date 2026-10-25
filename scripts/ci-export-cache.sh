#!/usr/bin/env bash
# Export only this project's inputs and caches. Does not upload or erase them.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
cd "$project_root"
mkdir -p artifacts/ci-transfer
exec 8>work/.package.lock
flock -n 8 || { echo 'Pause the local build with background-build.sh stop first.' >&2; exit 1; }
exec 9>"$work_dir/.build.lock"
flock -n 9 || { echo 'A build is still using this workspace.' >&2; exit 1; }
[[ -d $kernel_dir && -s $build_dir/.config ]]
export_dir=$(mktemp -d "artifacts/ci-transfer/$profile.XXXXXX")
PROFILE="$profile" FLAVOR="$flavor" PROJECT_PATH="$project_root" \
  python - "$export_dir/manifest.json" <<'PY'
import json, os, subprocess, sys
from pathlib import Path
data = {key.lower(): os.environ[key] for key in ['PROFILE', 'FLAVOR', 'PROJECT_PATH']}
data['schema'] = 1
data['packages'] = subprocess.check_output(
    ['pacman', '-Q', 'gcc', 'binutils', 'pahole', 'glibc', 'ccache'], text=True).splitlines()
Path(sys.argv[1]).write_text(json.dumps(data, indent=2) + '\n')
PY
# Pipe directly into sub-2 GiB assets, avoiding a second full-size archive copy.
tar --exclude='*/.git' --exclude='*/certs/*.pem' --exclude='*.lock' \
  --exclude='*.part.*' -cf - \
  .cache/ccache ".cache/downloads/zen-v$zen_version.tar.gz" \
  "work/$work_profile/kernel" "work/$work_profile/$build_subdir" |
  zstd -T2 -3 | split -b 1800M -d -a 3 - "$export_dir/cache.tar.zst.part-"
(cd "$export_dir" && sha256sum cache.tar.zst.part-* manifest.json > SHA256SUMS)
printf '%s\n' "$project_root/$export_dir" > artifacts/ci-transfer/latest
printf 'Export directory: %s\n' "$project_root/$export_dir"
du -ch "$export_dir"/cache.tar.zst.part-* | tail -1
