# Builds the same pinned profile as ./build.sh.
source "$startdir/scripts/lib.sh" || return 1
pkgbase=linux-surface-zen
pkgver=${zen_version/-/.}
pkgrel=$package_release
pkgdesc='Zen Linux kernel with Surface support and everyday peripheral drivers'
arch=(x86_64)
url='https://github.com/linux-surface/linux-surface'
license=(GPL-2.0-only)
makedepends=(bc binutils cpio curl flex bison gcc gettext git glibc gzip libelf libgcc
             openssl pahole perl python rsync tar util-linux xxhash zlib zstd)
options=(!debug !strip !lto)
source=()
sha256sums=()
pkgname=("$pkgbase" "$pkgbase-headers")

_make() {
  zen_make -s "$@"
}
_release() {
  local release
  release=$(_make kernelrelease) || return 1
  [[ $release == "$expected_release" ]] || {
    echo "Unexpected package kernel release: $release" >&2; return 1;
  }
  printf '%s\n' "$release"
}

build() {
  "$startdir/build.sh"
}

package_linux-surface-zen() {
  depends=(coreutils initramfs kmod wireless-regdb)
  optdepends=("$pkgbase-headers: headers and scripts for building external modules"
              'iptsd: touchscreen and pen support'
              'scx-scheds: sched-ext schedulers'
              'linux-firmware: device firmware')
  provides=(KSMBD-MODULE NTSYNC-MODULE VIRTUALBOX-GUEST-MODULES WIREGUARD-MODULE)
  local release modulesdir
  release=$(_release)
  modulesdir="$pkgdir/usr/lib/modules/$release"

  install -Dm644 "$build_dir/arch/x86/boot/bzImage" "$modulesdir/vmlinuz"
  printf '%s\n' "$pkgbase" | install -Dm644 /dev/stdin "$modulesdir/pkgbase"
  ZSTD_CLEVEL=3 _make INSTALL_MOD_PATH="$pkgdir/usr" INSTALL_MOD_STRIP=1 \
    DEPMOD=/bin/true modules_install
  rm -f "$modulesdir/build" "$modulesdir/source"
}

package_linux-surface-zen-headers() {
  pkgdesc="Headers and build scripts for the $pkgdesc"
  depends=(binutils glibc libelf libgcc openssl pahole xxhash zlib zstd)
  provides=(LINUX-HEADERS)
  local release builddir src out
  release=$(_release)
  builddir="$pkgdir/usr/lib/modules/$release/build"
  src="$kernel_dir"
  out="$build_dir"

  install -d "$builddir" "$builddir/kernel" "$builddir/arch/x86/kernel"
  install -m644 "$src/Makefile" "$src/Kbuild" "$src/Kconfig" "$builddir/"
  install -m644 "$out/.config" "$out/Module.symvers" "$out/System.map" \
    "$out/vmlinux" "$builddir/"
  install -m644 "$src/kernel/Makefile" "$builddir/kernel/"
  install -m644 "$src/arch/x86/Makefile" "$builddir/arch/x86/"

  cp -a "$src/scripts" "$builddir/"
  cp -a "$out/scripts/." "$builddir/scripts/"
  cp -a "$src/include" "$builddir/"
  cp -a "$out/include/." "$builddir/include/"
  cp -a "$src/arch/x86/include" "$builddir/arch/x86/"
  cp -a "$out/arch/x86/include/." "$builddir/arch/x86/include/"
  install -m644 "$out/arch/x86/kernel/asm-offsets.s" "$builddir/arch/x86/kernel/"

  for subdir in drivers/md net/mac80211 drivers/media/i2c \
                drivers/media/usb/dvb-usb drivers/media/dvb-frontends \
                drivers/media/tuners drivers/iio/common/hid-sensors; do
    install -d "$builddir/$subdir"
    find "$src/$subdir" -maxdepth 1 -name '*.h' -exec cp -t "$builddir/$subdir" -- {} +
  done
  (cd "$src" && find . -name 'Kconfig*' -not -path './.git/*' -print0) |
    while IFS= read -r -d '' file; do
      install -Dm644 "$src/$file" "$builddir/$file"
    done

  if [[ -f $out/tools/objtool/objtool ]]; then
    install -Dm755 "$out/tools/objtool/objtool" "$builddir/tools/objtool/objtool"
  fi
  if grep -q '^CONFIG_DEBUG_INFO_BTF_MODULES=y$' "$out/.config"; then
    install -Dm755 "$out/tools/bpf/resolve_btfids/resolve_btfids" \
      "$builddir/tools/bpf/resolve_btfids/resolve_btfids"
  fi
  # Preserve .BTF for external modules while omitting bulky DWARF sections.
  objcopy --strip-debug "$builddir/vmlinux"
  _make INSTALL_MOD_PATH="$pkgdir/usr" vdso_install link=

  find "$builddir/arch" -mindepth 1 -maxdepth 1 -type d ! -name x86 -exec rm -rf -- {} +
  rm -rf "$builddir/Documentation"
  find -L "$builddir" -type l -delete
  find "$builddir" -type f -name '*.o' -delete
  install -d "$pkgdir/usr/src"
  ln -sr "$builddir" "$pkgdir/usr/src/$pkgbase"
}
