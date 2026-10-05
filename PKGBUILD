# Builds local, pinned Zen + Surface sources from ./build.sh.
pkgbase=linux-surface-zen
pkgver=7.2.9.zen1
pkgrel=1
pkgdesc='Zen Linux kernel with Surface Pro 7 support'
arch=(x86_64)
url='https://github.com/linux-surface/linux-surface'
license=(GPL-2.0-only)
makedepends=(bc binutils cpio flex bison gcc git libelf openssl pahole perl python rsync)
options=(!debug !strip)
source=()
sha256sums=()
pkgname=("$pkgbase" "$pkgbase-headers")

_make() {
  make -s -C "$startdir/kernel" O="$startdir/build" LOCALVERSION= "$@"
}
_release() {
  _make kernelrelease
}

build() {
  "$startdir/build.sh"
}

package_linux-surface-zen() {
  depends=(coreutils initramfs kmod)
  optdepends=('iptsd: touchscreen and pen support'
              'linux-firmware: device firmware')
  provides=(KSMBD-MODULE NTSYNC-MODULE WIREGUARD-MODULE)
  local release modulesdir
  release=$(_release)
  modulesdir="$pkgdir/usr/lib/modules/$release"

  install -Dm644 "$startdir/build/arch/x86/boot/bzImage" "$modulesdir/vmlinuz"
  printf '%s\n' "$pkgbase" | install -Dm644 /dev/stdin "$modulesdir/pkgbase"
  ZSTD_CLEVEL=9 _make INSTALL_MOD_PATH="$pkgdir/usr" INSTALL_MOD_STRIP=1 \
    DEPMOD=/bin/true modules_install
  rm -f "$modulesdir/build" "$modulesdir/source"
}

package_linux-surface-zen-headers() {
  pkgdesc="Headers and build scripts for the $pkgdesc"
  depends=(binutils glibc libelf openssl pahole zstd)
  provides=(LINUX-HEADERS)
  local release builddir src out
  release=$(_release)
  builddir="$pkgdir/usr/lib/modules/$release/build"
  src="$startdir/kernel"
  out="$startdir/build"

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
  _make INSTALL_MOD_PATH="$pkgdir/usr" vdso_install link=

  find "$builddir/arch" -mindepth 1 -maxdepth 1 -type d ! -name x86 -exec rm -rf -- {} +
  rm -rf "$builddir/Documentation"
  find -L "$builddir" -type l -delete
  find "$builddir" -type f -name '*.o' -delete
  install -d "$pkgdir/usr/src"
  ln -sr "$builddir" "$pkgdir/usr/src/$pkgbase"
}
