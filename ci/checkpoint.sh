#!/usr/bin/env bash
# Save source timestamps and incremental objects, excluding private signing keys.
set -euo pipefail
source scripts/lib.sh
[[ ${GITHUB_ACTIONS:-} == true ]]
[[ -d $kernel_dir && -s $build_dir/.config ]] || exit 0
mkdir -p .cache/ci-checkpoints
partial=$(mktemp .cache/ci-checkpoints/output.XXXXXX)
trap 'rm -f -- "$partial"' EXIT
tar --exclude='*/.git' --exclude='*/certs/*.pem' \
  -cf - "work/$work_profile/kernel" "work/$work_profile/$build_subdir" |
  zstd -T2 -3 -o "$partial" -f
mv "$partial" .cache/ci-checkpoints/output.tar.zst
trap - EXIT
du -h .cache/ci-checkpoints/output.tar.zst
