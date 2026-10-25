#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
mkdir -p "$project_root/artifacts/"{packages,logs} "$project_root/work/packaging"
cd -- "$project_root"
exec 8>"$project_root/work/.package.lock"
flock 8
makepkg --config "$project_root/scripts/makepkg.conf" "$@" 2>&1 |
  tee "$project_root/artifacts/logs/package-$profile-$(date +%Y%m%d-%H%M%S)-$$.log"
