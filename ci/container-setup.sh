#!/usr/bin/env bash
set -euo pipefail
source ci/build.env
[[ $(id -u) == 0 && ${GITHUB_ACTIONS:-} == true ]]
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' \
  "$arch_snapshot" > /etc/pacman.d/mirrorlist
pacman -Syyuu --noconfirm --needed base-devel bc binutils ccache cpio curl \
  flex bison gcc gettext git glibc gzip libelf libgcc openssl pahole perl \
  python rsync tar util-linux xxhash zlib zstd kmod rust
build_uid=$(stat -c %u .)
[[ $build_uid != 0 ]]
useradd --create-home --uid "$build_uid" builder
pacman -Q gcc binutils pahole glibc ccache rust
