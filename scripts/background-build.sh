#!/usr/bin/env bash
# Detached build + archive validation. No assistant polling is required.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
state_root=$project_root/artifacts/background
action=${1:-status}

# Unlike nohup/setsid, a user service is not a child of the launching tool shell.
# The tool may clean up its descendants on exit even when they ignore SIGHUP.
job_alive() {
  local job=$1 state
  if [[ -f $job/unit ]]; then
    state=$(systemctl --user show "$(<"$job/unit")" -p ActiveState --value 2>/dev/null) || return 1
    [[ $state == active || $state == activating ]]
  elif [[ -f $job/pid ]]; then
    [[ $(ps -p "$(<"$job/pid")" -o args= 2>/dev/null) == *"background-build.sh _worker $job "* ]]
  else
    return 1
  fi
}

refresh_status() {
  local job=$1
  case $(<"$job/status") in
    queued|starting|running|'verifying archives')
      if ! job_alive "$job"; then
        printf 'failed: background worker exited; see log and service journal\n' > "$job/status"
        date -Is > "$job/finished"
      fi ;;
  esac
}

case $action in
  start|adopt)
    mkdir -p "$state_root"
    exec 7>"$state_root/.start.lock"
    flock 7
    if [[ -f $state_root/latest ]]; then
      previous=$(<"$state_root/latest")
      refresh_status "$previous"
      if job_alive "$previous"; then
        echo "A background build is already running: $previous"
        exit 0
      fi
    fi
    run=$(mktemp -d "$state_root/$profile.XXXXXX")
    printf '%s\n' "$run" > "$state_root/latest"
    printf 'starting\n' > "$run/status"
    printf '%s\n' "$flavor" > "$run/flavor"
    printf '%s\n' "$package_release" > "$run/package-release"
    if [[ $action == adopt ]]; then
      existing_log=$(ls -t "$project_root/artifacts/logs/package-$profile-"*.log | head -n 1)
      printf '%s\n' "$existing_log" > "$run/build-log"
    fi
    unit=surface-zen-$(basename -- "$run").service
    printf '%s\n' "$unit" > "$run/unit"
    touch "$run/log"
    if ! systemd-run --user --unit="$unit" --working-directory="$project_root" \
        --property="StandardOutput=append:$run/log" --property=StandardError=inherit \
        --setenv="SURFACE_ZEN_PROFILE=$profile" --setenv="JOBS=${JOBS:-$(nproc)}" \
        --setenv="SURFACE_ZEN_FLAVOR=$flavor" \
        --setenv="USE_CCACHE=${USE_CCACHE:-auto}" \
        --setenv="CCACHE_MAXSIZE=${CCACHE_MAXSIZE:-20G}" \
        /usr/bin/bash "$project_root/scripts/background-build.sh" _worker "$run" "$action"; then
      printf 'failed: could not start systemd user service\n' > "$run/status"
      exit 1
    fi
    printf 'Service: %s\nState directory: %s\nUse: ./scripts/background-build.sh status\n' "$unit" "$run"
    ;;
  _worker)
    run=${2:?} mode=${3:?}
    finish() {
      local code=$?
      if (( code == 0 )); then printf 'success\n' > "$run/status";
      else printf 'failed (exit %s); see log\n' "$code" > "$run/status"; fi
      date -Is > "$run/finished"
    }
    trap finish EXIT
    printf '%s\n' "$$" > "$run/pid"
    date -Is > "$run/started"
    printf 'running\n' > "$run/status"
    if [[ $mode == adopt ]]; then
      # Wait in the OS for the currently running package job, without polling.
      printf 'Waiting for the existing package job to release its lock.\n'
      exec 8>"$project_root/work/.package.lock"
      flock 8
      flock -u 8
      exec 8>&-
    else
      "$project_root/scripts/package.sh" -f
    fi
    printf 'verifying archives\n' > "$run/status"
    "$project_root/scripts/check-package.sh"
    ;;
  stop)
    mkdir -p "$state_root"
    exec 7>"$state_root/.start.lock"
    flock 7
    [[ -f $state_root/latest ]] || { echo 'No background job has been started.'; exit 0; }
    run=$(<"$state_root/latest")
    refresh_status "$run"
    if ! job_alive "$run"; then
      printf 'No active build. State: %s\n' "$(<"$run/status")"
      exit 0
    fi
    [[ -f $run/unit ]] || {
      echo 'Cannot safely stop a legacy worker without a systemd unit.' >&2; exit 1;
    }
    # systemd stops the entire service process tree and waits for it to exit.
    # Write the paused state afterward so the worker EXIT trap cannot replace it.
    systemctl --user stop "$(<"$run/unit")"
    printf 'paused\n' > "$run/status"
    date -Is > "$run/finished"
    printf 'Paused; version, incremental output and ccache retained.\nResume: ./scripts/background-build.sh start\n'
    ;;
  status|log)
    [[ -f $state_root/latest ]] || { echo 'No background job has been started.'; exit 0; }
    run=$(<"$state_root/latest")
    refresh_status "$run"
    if [[ $action == log ]]; then
      # Ctrl-C stops following the log; it does not stop the build.
      log_files=("$run/log")
      [[ ! -f $run/build-log ]] || log_files+=("$(<"$run/build-log")")
      tail -n 30 -f "${log_files[@]}"
    else
      pid=starting
      [[ ! -f $run/pid ]] || pid=$(<"$run/pid")
      printf 'State: %s\nPID: %s\nLog: %s\n' "$(<"$run/status")" "$pid" "$run/log"
      [[ ! -f $run/flavor ]] || printf 'Config flavor: %s\n' "$(<"$run/flavor")"
      [[ ! -f $run/package-release ]] || printf 'Package revision: %s\n' "$(<"$run/package-release")"
      if [[ -f $run/unit ]]; then
        printf 'Service: %s\n' "$(<"$run/unit")"
        [[ ! -f $run/revalidated ]] || printf 'Service result below is historical; archives were subsequently revalidated successfully.\n'
        systemctl --user show "$(<"$run/unit")" -p ActiveState -p SubState -p ExecMainStatus
      fi
      [[ ! -f $run/finished ]] || printf 'Finished: %s\n' "$(<"$run/finished")"
      [[ ! -f $run/revalidated ]] || printf 'Revalidated: %s\nReport log: %s\n' "$(<"$run/revalidated")" "$(<"$run/revalidation-log")"
    fi
    ;;
  *) echo 'Usage: scripts/background-build.sh {start|stop|adopt|status|log}' >&2; exit 2 ;;
esac
