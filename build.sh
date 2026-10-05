#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
root=$PWD
version=7.2.9-zen1
tarball=zen-v${version}.tar.gz
patchfile=patches/surface-zen-7.2.9.patch
source_sha256=814d32e75ca07fcc0bd8290ade366ea66c3ca0c33242995b41b29e3dd9d18bb5
jobs=${JOBS:-3}

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
# Preserve an identical .config so an incremental makepkg build stays incremental.
config_fingerprint=$(
  sha256sum configs/arch-zen-7.2.9.config configs/surface-6.19.config "$patchfile"
  printf '%s\n' 'surface-zen-config-v1: localversion=-surface-zen, no debug info, no Rust'
)
config_fingerprint=$(printf '%s\n' "$config_fingerprint" | sha256sum | cut -d' ' -f1)
if [[ ! -s build/.config || ! -f build/.surface-zen-config-sha256 ||
      $(<build/.surface-zen-config-sha256) != "$config_fingerprint" ]]; then
  kernel/scripts/kconfig/merge_config.sh -m -O "$root/build" \
    configs/arch-zen-7.2.9.config configs/surface-6.19.config
  kernel/scripts/config --file build/.config \
    --set-str LOCALVERSION '-surface-zen' --disable LOCALVERSION_AUTO \
    --enable DEBUG_INFO_NONE --disable DEBUG_INFO_DWARF5 --disable DEBUG_INFO_BTF \
    --disable RUST
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
for symbol in HID_IPTS SURFACE_AGGREGATOR SURFACE_GPE VIDEO_IPU3_CIO2; do
  grep -q "^CONFIG_${symbol}=m$" build/.config || {
    echo "Required CONFIG_${symbol}=m missing after olddefconfig" >&2
    exit 1
  }
done

make -C kernel O="$root/build" LOCALVERSION= -j "$jobs" all
printf 'Built %s: %s\n' "$release" "$root/build/arch/x86/boot/bzImage"
