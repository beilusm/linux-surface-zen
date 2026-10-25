#!/usr/bin/env bash
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true ]]
source project.conf
tag=ci-$default_profile-$SURFACE_ZEN_FLAVOR-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT
mkdir -p artifacts/logs artifacts/reports .cache
tar --exclude='*/root' --exclude='*/module' --exclude='*.pem' \
  -czf .cache/diagnostics.tar.gz artifacts/logs artifacts/reports
assets=(.cache/diagnostics.tar.gz)
notes=.cache/ci-release-notes.md
if [[ ${VERIFIED:-false} == true ]]; then
  shopt -s nullglob
  packages=(artifacts/packages/*.pkg.tar.zst)
  [[ ${#packages[@]} == 2 ]]
  assets+=("${packages[@]}")
  printf 'Kernel and headers packages passed complete module, BTF and external module validation. Hardware boot testing remains outstanding.\n\n' > "$notes"
else
  printf 'Build incomplete or validation failed. This release contains diagnostic logs only; no kernel packages are published.\n\n' > "$notes"
fi
printf 'Workflow run: %s/%s/actions/runs/%s\nCommit: %s\n' \
  "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID" "$GITHUB_SHA" >> "$notes"
gh release create "$tag" "${assets[@]}" --repo "$GITHUB_REPOSITORY" \
  --target "$GITHUB_SHA" --prerelease \
  --title "Surface Zen $default_profile ($SURFACE_ZEN_FLAVOR), run $GITHUB_RUN_NUMBER" \
  --notes-file "$notes"
printf 'Results: https://github.com/%s/releases/tag/%s\n' "$GITHUB_REPOSITORY" "$tag" >> "$GITHUB_STEP_SUMMARY"
