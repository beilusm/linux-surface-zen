#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
root=$PWD
version=7.2.9-zen1
tarball=zen-v${version}.tar.gz
patchfile=patches/surface-zen-7.2.9.patch
source_sha256=814d32e75ca07fcc0bd8290ade366ea66c3ca0c33242995b41b29e3dd9d18bb5
jobs=${JOBS:-6}

printf '%s  %s\n' "$source_sha256" "$tarball" | sha256sum --check --status || {
  if [[ ! -f $tarball ]]; then
    curl -fL --retry 3 -o "$tarball" \
      "https://github.com/zen-kernel/zen-kernel/archive/refs/tags/v${version}.tar.gz"
  fi
  printf '%s  %s\n' "$source_sha256" "$tarball" | sha256sum --check
}

if [[ ! -d kernel ]]; then
  mkdir kernel
  tar -xf "$tarball" --strip-components=1 -C kernel
fi
if git -C kernel apply --reverse --check "$root/$patchfile" 2>/dev/null; then
  echo 'Surface port already present in kernel/'
elif git -C kernel apply --check "$root/$patchfile"; then
  git -C kernel apply "$root/$patchfile"
else
  echo 'kernel/ matches neither the pristine Zen tag nor the known Surface port' >&2
  exit 1
fi

mkdir -p build
# Deterministic Pro 7 profile: derived from Arch Zen + linux-surface via
# localmodconfig on this device, with camera, Type Cover and common USB added.
config_fingerprint=$(sha256sum configs/surface-pro7-fast.config "$patchfile" | sha256sum | cut -d' ' -f1)
if [[ ! -s build/.config || ! -f build/.surface-zen-config-sha256 ||
      $(<build/.surface-zen-config-sha256) != "$config_fingerprint" ]]; then
  cp configs/surface-pro7-fast.config build/.config
  make -C kernel O="$root/build" LOCALVERSION= olddefconfig
  printf '%s\n' "$config_fingerprint" > build/.surface-zen-config-sha256
fi

# LOCALVERSION= prevents a '+' suffix from an untagged, patched git worktree.
make -C kernel O="$root/build" LOCALVERSION= olddefconfig
release=$(make -s -C kernel O="$root/build" LOCALVERSION= kernelrelease)
[[ $release == 7.2.9-zen1-surface-zen ]] || {
  echo "Unexpected kernel release: $release" >&2
  exit 1
}
for symbol in HID_IPTS HID_MULTITOUCH HID_SURFACE SURFACE_AGGREGATOR \
              SURFACE_GPE VIDEO_IPU3_CIO2 DRM_I915 IWLWIFI NVME_CORE; do
  grep -q "^CONFIG_${symbol}=m$" build/.config || {
    echo "Required CONFIG_${symbol}=m missing after olddefconfig" >&2
    exit 1
  }
done

if [[ -s build/arch/x86/boot/bzImage && -s build/vmlinux &&
      -s build/Module.symvers && -s build/drivers/hid/ipts/ipts.ko &&
      -f build/.surface-zen-build-sha256 &&
      $(<build/.surface-zen-build-sha256) == "$config_fingerprint" ]]; then
  echo "Using previously completed $release build"
else
  make -C kernel O="$root/build" LOCALVERSION= -j "$jobs" all
  printf '%s\n' "$config_fingerprint" > build/.surface-zen-build-sha256
fi
printf 'Built %s: %s\n' "$release" "$root/build/arch/x86/boot/bzImage"
