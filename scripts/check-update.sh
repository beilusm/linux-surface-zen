#!/usr/bin/env bash
# Probe an explicit Zen tag in an isolated tree; never activate/install it.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
candidate=${1:-}
checksum=${2:-}
[[ $# -ge 1 && $# -le 2 && $candidate =~ ^[0-9]+\.[0-9]+\.[0-9]+-zen[0-9]+$ &&
   ( -z $checksum || $checksum =~ ^[0-9a-f]{64}$ ) ]] || {
  echo 'Usage: scripts/check-update.sh VERSION-zenN [EXPECTED_SHA256]' >&2; exit 2;
}
archive=$download_dir/zen-v$candidate.tar.gz
if [[ $candidate == "$zen_version" && -z $checksum ]]; then checksum=$source_sha256; fi
zen_download "$candidate" "$archive" "$checksum"
actual=$(zen_digest "$archive")
mkdir -p "$project_root/work/preflight" "$project_root/artifacts/reports"
probe=$(mktemp -d "$project_root/work/preflight/$candidate.XXXXXX")
report=$project_root/artifacts/reports/$(basename -- "$probe")
mkdir -p "$probe/kernel" "$probe/build" "$report"
printf 'candidate=%s\nsha256=%s\nbase_profile=%s\nwork=%s\n' \
  "$candidate" "$actual" "$profile" "$probe" > "$report/summary.txt"
if [[ -z $checksum ]]; then
  echo 'Checksum was computed from the download, not compared to a supplied value.' |
    tee -a "$report/summary.txt"
fi
tar -xf "$archive" --strip-components=1 -C "$probe/kernel"
if ! zen_apply "$probe/kernel" --check > "$report/patch-check.log" 2>&1; then
  printf 'patch=FAIL (port required)\n' >> "$report/summary.txt"
  cat "$report/patch-check.log"
  echo "Patch incompatible. Report: $report" >&2
  exit 1
fi
zen_apply "$probe/kernel"
zen_apply "$probe/kernel" --reverse --check
printf 'patch=PASS\n' >> "$report/summary.txt"
cp -- "$config_path" "$probe/build/.config"
if ! make -C "$probe/kernel" O="$probe/build" LOCALVERSION= olddefconfig \
    > "$report/olddefconfig.log" 2>&1; then
  echo 'config=FAIL' >> "$report/summary.txt"
  cat "$report/olddefconfig.log"
  echo "Configuration failed. Report: $report" >&2
  exit 1
fi
candidate_config_name=$(basename -- "$config_file")
cp -- "$probe/build/.config" "$report/$candidate_config_name"
set +e
diff -u "$config_path" "$report/$candidate_config_name" > "$report/config.diff"
diff_status=$?
set -e
[[ $diff_status -le 1 ]] || exit "$diff_status"
if ! "$project_root/scripts/check-config.sh" "$probe/build/.config" \
    "${arch_config_file:+$project_root/$arch_config_file}" \
    "${config_policy_file:+$project_root/$config_policy_file}" > "$report/config-check.log" 2>&1; then
  echo 'config=FAIL (required options missing)' >> "$report/summary.txt"
  cat "$report/config-check.log"
  echo "Configuration incompatible. Report: $report" >&2
  exit 1
fi
release=$(make -s -C "$probe/kernel" O="$probe/build" LOCALVERSION= kernelrelease)
[[ $release == "$candidate-surface-zen" ]] || {
  echo "release=FAIL ($release)" >> "$report/summary.txt"; exit 1;
}
printf 'config=PASS\nrelease=%s\n' "$release" >> "$report/summary.txt"
candidate_policy=
[[ -z ${config_policy_file:-} ]] || candidate_policy=configs/policies/surface-pro7-$candidate.json
cat > "$report/candidate.conf" <<EOF
# Draft only: review/copy the port and normalized config before activation.
zen_version=$candidate
package_release=1
source_sha256=$actual
config_file=configs/$candidate/$candidate_config_name
arch_config_file=configs/reference/arch-zen-${candidate%-zen*}.config
config_policy_file=$candidate_policy
build_subdir=$build_subdir
patch_file=patches/surface-zen-${candidate%-zen*}.patch
# Provenance of the base used in this preflight, not newly selected upstream commits.
surface_commit=$surface_commit
surface_patch_baseline=$surface_patch_baseline
arch_config_commit=$arch_config_commit
EOF
echo 'Preflight passed; a full build and hardware tests are still required.' |
  tee -a "$report/summary.txt"
printf 'Report: %s\nCurrent default remains: %s\n' "$report" "$default_profile"
