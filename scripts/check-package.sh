#!/usr/bin/env bash
# Inspect actual archives and build an external module without installing/loading.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
[[ $# == 0 || $# == 2 ]] || {
  echo 'Usage: scripts/check-package.sh [KERNEL_PACKAGE HEADERS_PACKAGE]' >&2; exit 2;
}
kernel_package=${1:-$project_root/artifacts/packages/linux-surface-zen-${zen_version/-/.}-$package_release-x86_64.pkg.tar.zst}
headers_package=${2:-$project_root/artifacts/packages/linux-surface-zen-headers-${zen_version/-/.}-$package_release-x86_64.pkg.tar.zst}
mkdir -p "$project_root/artifacts/reports"
probe=$(mktemp -d "$project_root/artifacts/reports/package-check-$profile.XXXXXX")
trap 'code=$?; printf "FAIL (exit %s): line %s: %s\nReport: %s\n" "$code" "$LINENO" "$BASH_COMMAND" "$probe" >&2' ERR
trap 'rm -rf -- "$probe/root" "$probe/module"' EXIT
mkdir -p "$probe/root" "$probe/module"
bsdtar -xf "$kernel_package" -C "$probe/root"
bsdtar -xf "$headers_package" -C "$probe/root"
# Arch's filesystem package supplies /lib -> usr/lib. Kernel archives alone
# do not contain it, but kmod defaults to /lib/modules in an alternate root.
ln -s usr/lib "$probe/root/lib"
modulesdir=$probe/root/usr/lib/modules/$expected_release
headers=$modulesdir/build
[[ -s $modulesdir/vmlinuz && $(<"$modulesdir/pkgbase") == linux-surface-zen ]]
"$project_root/scripts/check-config.sh" "$headers/.config" \
  "${arch_config_file:+$project_root/$arch_config_file}" \
  "${config_policy_file:+$project_root/$config_policy_file}"
python - "$build_dir/modules.order" "$modulesdir" <<'PY'
import sys
from pathlib import Path
order, root = map(Path, sys.argv[1:])
expected = [root / ('kernel/' + str(Path(line).with_suffix('.ko.zst')))
            for line in order.read_text().splitlines()]
missing = [str(p.relative_to(root)) for p in expected if not p.is_file()]
if not expected or missing:
    sys.exit('Missing packaged modules: ' + ', '.join(missing))
print(f'All {len(expected)} compiled modules are present in the package')
PY
readelf -SW "$headers/vmlinux" > "$probe/vmlinux-sections.txt"
grep ' \.BTF ' "$probe/vmlinux-sections.txt" >/dev/null
[[ -x $headers/tools/bpf/resolve_btfids/resolve_btfids ]]
depmod -b "$probe/root" "$expected_release" 2> "$probe/depmod.log"
for name in ch341 cp210x ftdi_sio pl2303 cdc_acm usb_storage uas r8152 \
            uvcvideo snd_usb_audio ipts surface_aggregator; do
  modinfo -b "$probe/root" -k "$expected_release" "$name" > "$probe/modinfo-$name.txt"
  [[ $(modinfo -b "$probe/root" -k "$expected_release" -F vermagic "$name") == "$expected_release "* ]]
  modprobe -d "$probe/root" -S "$expected_release" --show-depends "$name" \
    > "$probe/modprobe-$name.txt"
done
cat > "$probe/module/surface_zen_headers_test.c" <<'EOF'
#include <linux/init.h>
#include <linux/module.h>
static int __init headers_test_init(void) { pr_info("headers test\n"); return 0; }
static void __exit headers_test_exit(void) { }
module_init(headers_test_init);
module_exit(headers_test_exit);
MODULE_LICENSE("GPL");
EOF
printf 'obj-m := surface_zen_headers_test.o\n' > "$probe/module/Makefile"
make -C "$headers" M="$probe/module" CC=gcc modules > "$probe/external-module.log" 2>&1
readelf -SW "$probe/module/surface_zen_headers_test.ko" > "$probe/external-module-sections.txt"
grep ' \.BTF ' "$probe/external-module-sections.txt" >/dev/null
grep ' \.BTF.base ' "$probe/external-module-sections.txt" >/dev/null
printf 'PASS: archives, complete modules, aliases/dependencies, BTF and external module\nReport: %s\n' "$probe"
