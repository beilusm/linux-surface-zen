#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
mode=${1:-build}
[[ $# -le 1 && ( $mode == build || $mode == --check ) ]] || {
  echo 'Usage: ./build.sh [--check]' >&2; exit 2;
}
# Use all available logical CPUs by default; JOBS explicitly overrides this.
jobs=${JOBS:-$(nproc)}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 2; }
mkdir -p "$work_dir"
exec 9>"$work_dir/.build.lock"
flock 9
zen_download "$zen_version" "$tarball" "$source_sha256"
source_identity=$(zen_source_identity)
if [[ ! -d $kernel_dir ]]; then
  staging=$(mktemp -d "$work_dir/kernel.extract.XXXXXX")
  trap 'rm -rf -- "$staging"' EXIT
  tar -xf "$tarball" --strip-components=1 -C "$staging"
  zen_apply "$staging" --check
  zen_apply "$staging"
  printf '%s\n' "$source_identity" > "$staging/.surface-zen-source-sha256"
  mv -- "$staging" "$kernel_dir"
  trap - EXIT
fi
[[ -f $kernel_dir/.surface-zen-source-sha256 &&
   $(<"$kernel_dir/.surface-zen-source-sha256") == "$source_identity" ]] || {
  echo 'Source identity changed. Use a new version profile/work directory; do not reuse this source tree.' >&2
  exit 1
}
zen_apply "$kernel_dir" --reverse --check
mkdir -p "$build_dir"
input_identity=$(zen_input_identity)
if [[ ! -s $build_dir/.config || ! -f $build_dir/.surface-zen-config-sha256 ||
      $(<"$build_dir/.surface-zen-config-sha256") != "$input_identity" ||
      ! -f $build_dir/.surface-zen-normalized-sha256 ||
      $(<"$build_dir/.surface-zen-normalized-sha256") != "$(zen_digest "$build_dir/.config")" ]]; then
  cp -- "$config_path" "$build_dir/.config"
  zen_make olddefconfig
  printf '%s\n' "$input_identity" > "$build_dir/.surface-zen-config-sha256"
fi
zen_make olddefconfig
"$project_root/scripts/check-config.sh" "$build_dir/.config" \
  "${arch_config_file:+$project_root/$arch_config_file}" \
  "${config_policy_file:+$project_root/$config_policy_file}"
release=$(zen_make -s kernelrelease)
[[ $release == "$expected_release" ]] || {
  echo "Unexpected kernel release: $release (expected $expected_release)" >&2; exit 1;
}
normalized_identity=$(zen_digest "$build_dir/.config")
printf '%s\n' "$normalized_identity" > "$build_dir/.surface-zen-normalized-sha256"
build_identity=$(printf '%s\n' "$input_identity" "$normalized_identity" | sha256sum | cut -d' ' -f1)
if [[ $mode == --check ]]; then
  printf 'Verified source, patch, normalized config and release: %s\n' "$release"
  exit
fi
if [[ -s $build_dir/arch/x86/boot/bzImage && -s $build_dir/vmlinux &&
      -s $build_dir/Module.symvers && -s $build_dir/drivers/hid/ipts/ipts.ko &&
      -x $build_dir/tools/bpf/resolve_btfids/resolve_btfids &&
      -f $build_dir/.surface-zen-build-sha256 &&
      $(<"$build_dir/.surface-zen-build-sha256") == "$build_identity" ]] &&
      readelf -SW "$build_dir/vmlinux" | grep ' \.BTF ' >/dev/null &&
      zen_modules_complete; then
  echo "Using previously completed $release build"
else
  printf 'Building with %s jobs, CC=%s; incremental output: %s\n' "$jobs" "$zen_cc" "$build_dir"
  # A desktop makepkg.conf may export -j8: explicitly bound this build.
  MAKEFLAGS= zen_make -j "$jobs" all
  zen_modules_complete || { echo 'Incomplete module output' >&2; exit 1; }
  printf '%s\n' "$build_identity" > "$build_dir/.surface-zen-build-sha256"
fi
printf 'Built %s: %s\n' "$release" "$build_dir/arch/x86/boot/bzImage"
