#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/scripts/lib.sh"
mkdir -p "$project_root/artifacts/logs"
"$project_root/scripts/build.sh" "$@" 2>&1 |
  tee "$project_root/artifacts/logs/build-$profile-$(date +%Y%m%d-%H%M%S)-$$.log"
