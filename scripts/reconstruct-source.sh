#!/usr/bin/env bash
# Rebuild a pinned archive from a cached release and an audited upstream delta.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
output=$(realpath -m -- "${1:?Usage: reconstruct-source.sh OUTPUT}")
# makepkg and callers may inherit Git environment variables. All temporary Git
# operations must address this scratch repository only.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES
[[ ${source_archive_mode:-} == delta && $source_base_version != "$zen_version" &&
   $source_tree =~ ^[0-9a-f]{40}$ && $source_delta_sha256 =~ ^[0-9a-f]{64}$ &&
   $source_base_version =~ ^[0-9]+\.[0-9]+\.[0-9]+-zen[0-9]+$ &&
   $source_base_sha256 =~ ^[0-9a-f]{64}$ &&
   $source_delta_file != /* && $source_delta_file != *..* ]]
delta=$project_root/$source_delta_file
[[ $(zen_digest "$delta") == "$source_delta_sha256" ]]
base=$download_dir/zen-v$source_base_version.tar.gz
zen_download "$source_base_version" "$base" "$source_base_sha256"
mkdir -p "$project_root/work/preflight"
scratch=$(mktemp -d "$project_root/work/preflight/reconstruct.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
tar -xf "$base" --strip-components=1 -C "$scratch"
env -u GIT_DIR -u GIT_WORK_TREE GIT_CEILING_DIRECTORIES="$project_root" \
  git -C "$scratch" apply --check "$delta"
env -u GIT_DIR -u GIT_WORK_TREE GIT_CEILING_DIRECTORIES="$project_root" \
  git -C "$scratch" apply "$delta"
git -C "$scratch" init -q
git -C "$scratch" -c core.autocrlf=false add -f -A
actual_tree=$(git -C "$scratch" write-tree)
[[ $actual_tree == "$source_tree" ]] || {
  echo "Reconstructed source tree mismatch: $actual_tree" >&2; exit 1;
}
git -C "$scratch" -c tar.umask=0000 archive --format=tar.gz -6 \
  --mtime="$source_archive_time" --prefix="zen-kernel-$zen_version/" \
  -o "$output" "$source_tree"
[[ $(zen_digest "$output") == "$source_sha256" ]]
printf 'Verified reconstructed upstream Git tree: %s\n' "$source_tree"
