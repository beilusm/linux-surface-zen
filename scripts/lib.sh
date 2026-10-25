#!/usr/bin/env bash
# Shared pinned inputs, sourced by build tools and PKGBUILD.
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$project_root/project.conf"
profile=${SURFACE_ZEN_PROFILE:-$default_profile}
[[ $profile =~ ^[0-9]+\.[0-9]+\.[0-9]+-zen[0-9]+$ ]] || {
  echo "Invalid profile: $profile" >&2; return 1;
}
source "$project_root/versions/$profile.conf" || return 1
flavor=${SURFACE_ZEN_FLAVOR:-pro7}
case $flavor in
  pro7) ;;
  full) source "$project_root/versions/$profile.full.conf" || return 1 ;;
  *) echo 'SURFACE_ZEN_FLAVOR must be pro7 or full' >&2; return 1 ;;
esac
[[ $zen_version == "$profile" && $package_release =~ ^[1-9][0-9]*$ &&
   $source_sha256 =~ ^[0-9a-f]{64}$ ]] || {
  echo 'Invalid pinned version metadata' >&2; return 1;
}
for project_input in "$config_file" "$patch_file"; do
  [[ $project_input != /* && $project_input != *..* && -f $project_root/$project_input ]] || {
    echo "Missing or invalid input: $project_input" >&2; return 1;
  }
done
if [[ -n ${config_policy_file:-} ]]; then
  [[ $config_policy_file != /* && $config_policy_file != *..* &&
     -f $project_root/$config_policy_file ]] || {
    echo "Missing or invalid config policy: $config_policy_file" >&2; return 1;
  }
fi
if [[ -n ${arch_config_file:-} ]]; then
  [[ $arch_config_file != /* && $arch_config_file != *..* &&
     -f $project_root/$arch_config_file ]] || {
    echo "Missing or invalid Arch reference config: $arch_config_file" >&2; return 1;
  }
fi
config_path=$project_root/$config_file
patch_path=$project_root/$patch_file
expected_release=$zen_version-surface-zen
# A reviewed update may retain the existing absolute Kbuild paths. Changing
# these paths invalidates saved compiler commands even for unchanged sources.
work_profile=${work_profile:-$profile}
[[ $work_profile =~ ^[0-9]+\.[0-9]+\.[0-9]+-zen[0-9]+$ ]] || {
  echo 'Invalid cache workspace profile' >&2; return 1;
}
work_dir=$project_root/work/$work_profile
kernel_dir=$work_dir/kernel
build_subdir=${build_subdir:-build}
[[ $build_subdir =~ ^[a-zA-Z0-9_-]+$ ]] || {
  echo 'Invalid build directory name' >&2; return 1;
}
build_dir=$work_dir/$build_subdir
download_dir=$project_root/.cache/downloads
tarball=$download_dir/zen-v$zen_version.tar.gz

# Use the same compiler for direct builds, makepkg and headers packaging.
zen_cc=gcc
case ${USE_CCACHE:-auto} in
  auto|1)
    if command -v ccache >/dev/null; then
      zen_cc='ccache gcc'
      export CCACHE_DIR="$project_root/.cache/ccache"
      export CCACHE_MAXSIZE=${CCACHE_MAXSIZE:-20G}
    elif [[ ${USE_CCACHE:-auto} == 1 ]]; then
      echo 'USE_CCACHE=1 requires ccache' >&2; return 1
    fi ;;
  0) ;;
  *) echo 'USE_CCACHE must be auto, 0 or 1' >&2; return 1 ;;
esac
zen_make() { make -C "$kernel_dir" O="$build_dir" LOCALVERSION= CC="$zen_cc" "$@"; }

zen_modules_complete() {
  python - "$build_dir" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
order = root / 'modules.order'
if not order.is_file():
    sys.exit(1)
modules = order.read_text().splitlines()
# Kbuild records .o paths; the completed loadable files have .ko extensions.
sys.exit(0 if modules and all((root / m).with_suffix('.ko').is_file()
                             for m in modules) else 1)
PY
}

zen_digest() { sha256sum "$1" | cut -d' ' -f1; }
zen_apply() {
  local tree=$1
  shift
  # git apply inside this project's ignored work/ tree otherwise silently skips
  # paths because it discovers the parent Git repository. Treat kernel sources
  # as independent trees, including when makepkg inherits Git environment vars.
  env -u GIT_DIR -u GIT_WORK_TREE GIT_CEILING_DIRECTORIES="$project_root" \
    git -C "$tree" apply "$@" "$patch_path"
}
zen_source_identity() {
  printf '%s\n' "$zen_version" "$source_sha256" "$(zen_digest "$patch_path")" |
    sha256sum | cut -d' ' -f1
}
zen_input_identity() {
  {
    zen_source_identity
    zen_digest "$config_path"
    printf '%s\n' "$zen_cc"
    gcc -dumpfullversion -dumpversion
    ld --version | sed -n '1p'
    pahole --version
  } | sha256sum | cut -d' ' -f1
}
zen_download() (
  local version=$1 archive=$2 checksum=${3:-} actual download_lock partial
  mkdir -p "$(dirname -- "$archive")"
  exec {download_lock}>"$archive.lock"
  flock "$download_lock"
  if [[ ! -f $archive ]]; then
    partial=$(mktemp "$archive.part.XXXXXX")
    if [[ $version == "$zen_version" && ${source_archive_mode:-github} == delta ]]; then
      "$project_root/scripts/reconstruct-source.sh" "$partial" || return 1
    else
      curl -fL --retry 3 -o "$partial" \
        "https://github.com/zen-kernel/zen-kernel/archive/refs/tags/v${version}.tar.gz" || return 1
    fi
    actual=$(zen_digest "$partial")
    if [[ -n $checksum && $actual != "$checksum" ]]; then
      echo "SHA-256 mismatch: $partial (kept for inspection)" >&2; return 1
    fi
    mv -- "$partial" "$archive"
  fi
  actual=$(zen_digest "$archive")
  [[ -z $checksum || $actual == "$checksum" ]] || {
    echo "SHA-256 mismatch: $archive" >&2; return 1;
  }
  exec {download_lock}>&-
)
