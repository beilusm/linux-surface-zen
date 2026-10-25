#!/usr/bin/env bash
# Explicitly migrate a cache workspace, preserving absolute paths and mtimes.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
base_profile=${1:?Usage: SURFACE_ZEN_PROFILE=NEW scripts/reuse-build.sh OLD}
[[ $# == 1 && $base_profile != "$profile" && $base_profile == "$work_profile" ]] || {
  echo 'Target manifest must explicitly select the base work_profile.' >&2; exit 2;
}
base_identity=$(SURFACE_ZEN_PROFILE="$base_profile" bash -c \
  'source "$1/scripts/lib.sh"; zen_source_identity' bash "$project_root")
mkdir -p "$work_dir" "$project_root/work/archive"
# Same lock order as packaging. Never change a tree while a build is using it.
exec 8>"$project_root/work/.package.lock"
flock 8
exec 9>"$work_dir/.build.lock"
flock 9
target_identity=$(zen_source_identity)
if [[ -f $kernel_dir/.surface-zen-source-sha256 &&
      $(<"$kernel_dir/.surface-zen-source-sha256") == "$target_identity" ]]; then
  echo "Cache workspace already prepared for $profile"; exit 0
fi
[[ -f $kernel_dir/.surface-zen-source-sha256 &&
   $(<"$kernel_dir/.surface-zen-source-sha256") == "$base_identity" &&
   -s $build_dir/.config && -s $build_dir/vmlinux &&
   -s $build_dir/.surface-zen-build-sha256 ]] || {
  echo 'Expected source identity and completed base output are required.' >&2; exit 1;
}
zen_download "$zen_version" "$tarball" "$source_sha256"
staging=$(mktemp -d "$work_dir/update.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
tar -xf "$tarball" --strip-components=1 -C "$staging"
zen_apply "$staging" --check
zen_apply "$staging"
zen_apply "$staging" --reverse --check
printf '%s\n' "$target_identity" > "$staging/.surface-zen-source-sha256"
snapshot=$(mktemp -d "$project_root/work/archive/$base_profile-before-$profile.XXXXXX")
# Fail on filesystems without reflinks rather than unexpectedly copying 25 GB.
# Reflinks are independent snapshots; hard links would corrupt the old output.
cp -a --reflink=always "$kernel_dir" "$snapshot/kernel"
cp -a --reflink=always "$build_dir" "$snapshot/$build_subdir"
printf 'base=%s\ntarget=%s\nsource=%s\noutput=%s\n' \
  "$base_profile" "$profile" "$kernel_dir" "$build_dir" > "$snapshot/migration.txt"
printf '%s\n' "$snapshot" > "$work_dir/.surface-zen-cache-snapshot"
# Content comparison is essential: release tarballs give unchanged files new
# timestamps. Leave those files untouched, and date changed files as of now.
# Invalidate the source marker first so interruption can never pass as a build.
rm -- "$kernel_dir/.surface-zen-source-sha256"
rsync -rlpc --delete --exclude=/.surface-zen-source-sha256 \
  --itemize-changes "$staging/" "$kernel_dir/" > "$snapshot/source-changes.txt"
cp "$staging/.surface-zen-source-sha256" "$kernel_dir/.surface-zen-source-sha256"
printf 'Cache retained at: %s\nRollback snapshot: %s\nChanged source paths: %s\n' \
  "$build_dir" "$snapshot" "$(wc -l < "$snapshot/source-changes.txt")"
