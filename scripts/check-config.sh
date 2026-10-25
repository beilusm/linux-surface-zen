#!/usr/bin/env bash
set -euo pipefail
config=${1:?Usage: check-config.sh CONFIG [ARCH_CONFIG] [POLICY]}
for symbol in HID_IPTS HID_MULTITOUCH HID_SURFACE SURFACE_AGGREGATOR \
              SURFACE_GPE VIDEO_IPU3_CIO2 GPIO_TPS68470 DRM_I915 IWLWIFI NVME_CORE; do
  grep -q "^CONFIG_${symbol}=m$" "$config" || {
    echo "Required CONFIG_${symbol}=m missing after olddefconfig" >&2; exit 1;
  }
done

# A daily build must keep the complete Arch module baseline, including devices
# that were unplugged when the config was generated. Fail on silent pruning.
if [[ -n ${2:-} && -z ${3:-} ]]; then
  python - "$config" "$2" <<'PY'
import sys
from pathlib import Path

def read(path):
    return dict(line.split('=', 1) for line in Path(path).read_text().splitlines()
                if line.startswith('CONFIG_'))

actual, arch = map(read, sys.argv[1:])
# Match linux-surface's explicit AF_ALG AEAD hotfix; no hardware-driver cuts.
excluded = {'CONFIG_CRYPTO_USER_API_AEAD'}
missing = [key for key, value in arch.items()
           if value == 'm' and key not in excluded and actual.get(key) not in ('m', 'y')]
if missing:
    sys.exit('Arch modules were removed: ' + ', '.join(missing))
print(f'Arch driver coverage verified; {sum(v == "m" for v in actual.values())} module options')
PY
  for symbol in USB_SERIAL_CH341 USB_SERIAL_CP210X USB_SERIAL_FTDI_SIO \
                USB_SERIAL_PL2303 USB_ACM USB_PRINTER USB_STORAGE USB_UAS \
                USB_RTL8152 USB_NET_RNDIS_HOST USB_VIDEO_CLASS SND_USB_AUDIO \
                BT_HCIBTUSB FUSE_FS OVERLAY_FS BTRFS_FS NTFS3_FS CIFS NFS_FS \
                TUN VETH BRIDGE WIREGUARD KVM_INTEL NTSYNC; do
    grep -Eq "^CONFIG_${symbol}=(m|y)$" "$config" || {
      echo "Daily CONFIG_${symbol} missing after olddefconfig" >&2; exit 1;
    }
  done
fi
if [[ -n ${3:-} ]]; then
  python - "$config" "$3" <<'PY'
import json, re, sys
from pathlib import Path
cfg = dict(re.findall(r'^CONFIG_(\w+)=(.*)$', Path(sys.argv[1]).read_text(), re.M))
policy = json.loads(Path(sys.argv[2]).read_text())
root = Path(sys.argv[2]).resolve().parents[2]
baseline_path = root / policy['baseline_config']
baseline = dict(re.findall(r'^CONFIG_(\w+)=(.*)$', baseline_path.read_text(), re.M))
exclusions = policy['reviewed_exclusions']
missing = [key for key, value in baseline.items() if value in ('m','y')
           and key not in exclusions and cfg.get(key) not in ('m','y')]
if missing:
    raise SystemExit('Unreviewed config removals: ' + ', '.join(sorted(missing)))
for symbol in ['USB_SERIAL_CH341','USB_SERIAL_CP210X','USB_SERIAL_FTDI_SIO',
               'USB_SERIAL_PL2303','USB_ACM','USB_STORAGE','USB_UAS','USB_RTL8152',
               'USB_VIDEO_CLASS','SND_USB_AUDIO','BT_HCIBTUSB','NVME_CORE',
               'BLK_DEV_SD','BTRFS_FS','EXT4_FS','FUSE_FS','OVERLAY_FS','NTFS3_FS',
               'CIFS','NFS_FS','TUN','VETH','BRIDGE','WIREGUARD','KVM_INTEL','NTSYNC']:
    if cfg.get(symbol) not in ('m', 'y'):
        raise SystemExit(f'Pro7 daily CONFIG_{symbol} missing after olddefconfig')
disabled = set(policy.get('required_disabled', {}))
unexpected = [name for name in disabled if cfg.get(name) in ('m','y')]
if unexpected:
    raise SystemExit('Policy symbols still enabled: ' + ', '.join(sorted(unexpected)))
print(f'Pro7 trim policy verified; {sum(v == "m" for v in cfg.values())} module options')
PY
fi
for symbol in PINCTRL_ICELAKE DEBUG_INFO_BTF DEBUG_INFO_BTF_MODULES BPF_LSM \
              ZEN_INTERACTIVE PREEMPT_DYNAMIC HZ_1000 SCHED_AUTOGROUP; do
  grep -q "^CONFIG_${symbol}=y$" "$config" || {
    echo "Required CONFIG_${symbol}=y missing after olddefconfig" >&2; exit 1;
  }
done
for setting in 'CONFIG_LOCALVERSION="-surface-zen"' 'CONFIG_DRM_PANIC_SCREEN="user"'; do
  grep -Fxq "$setting" "$config" || {
    echo "Required $setting missing after olddefconfig" >&2; exit 1;
  }
done
