#!/usr/bin/env bash
set -euo pipefail
source scripts/lib.sh
minutes=${BUILD_MINUTES:-240}
[[ $minutes =~ ^[1-9][0-9]*$ && $minutes -le 270 ]]
mkdir -p artifacts/reports
gcc --version > artifacts/reports/ci-compiler.txt
ccache --show-stats > artifacts/reports/ci-ccache-before.txt
# Private signing keys are never transferred or cached. Generate a fresh cloud
# key through Kbuild and relink against its certificate, even after a full hit.
if [[ ! -f $build_dir/certs/signing_key.pem &&
      -f $build_dir/.surface-zen-build-sha256 ]]; then
  mv "$build_dir/.surface-zen-build-sha256" \
    "$build_dir/.surface-zen-build-sha256.before-ci-key"
fi
set +e
timeout --signal=TERM --kill-after=30s "${minutes}m" ./scripts/package.sh -f
code=$?
set -e
ccache --show-stats > artifacts/reports/ci-ccache-after.txt
printf '%s\n' "$code" > artifacts/reports/ci-build-exit-code.txt
if [[ $code == 124 ]]; then
  echo 'Build time slice ended. Save the checkpoint and rerun this workflow to continue.'
fi
exit "$code"
