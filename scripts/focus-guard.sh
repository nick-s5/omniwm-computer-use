#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage:' \
    '  focus-guard.sh capture' \
    '  focus-guard.sh guard [--ttl <seconds>]' \
    '  focus-guard.sh restore <token>' \
    '  focus-guard.sh status <token>'
}

find_ctl() {
  local bundled=/Applications/OmniWM.app/Contents/MacOS/omniwmctl
  if [[ -n "${OMNIWMCTL:-}" ]]; then
    printf '%s\n' "$OMNIWMCTL"
  elif [[ -x "$bundled" ]]; then
    printf '%s\n' "$bundled"
  elif command -v omniwmctl >/dev/null 2>&1; then
    command -v omniwmctl
  else
    return 1
  fi
}

require_dependencies() {
  command -v jq >/dev/null 2>&1 || {
    printf '%s\n' 'focus-guard.sh requires jq.' >&2
    exit 69
  }
  ctl=$(find_ctl) || {
    printf '%s\n' 'omniwmctl not found.' >&2
    exit 69
  }
  [[ -x "$ctl" ]] || {
    printf 'omniwmctl is not executable at %s\n' "$ctl" >&2
    exit 69
  }
  "$ctl" ping >/dev/null
}

state_root="${TMPDIR:-/tmp}"
state_root="${state_root%/}/omniwm-agent-focus"

validate_token() {
  local value=$1
  [[ "$value" =~ ^focus\.[A-Za-z0-9]+$ ]] || {
    printf 'Invalid focus token: %s\n' "$value" >&2
    exit 64
  }
}

create_state() {
  local mode=$1
  mkdir -p "$state_root"
  chmod 700 "$state_root"

  state_dir=$(mktemp -d "$state_root/focus.XXXXXX")
  token=${state_dir##*/}
  chmod 700 "$state_dir"

  snapshot=$("$ctl" query focused-window --format json)
  target_id=$(jq -r '.result.payload.window.id // empty' <<<"$snapshot")
  if [[ -z "$target_id" ]]; then
    rmdir "$state_dir"
    printf '%s\n' 'OmniWM did not report a focused managed window.' >&2
    exit 2
  fi

  printf '%s\n' "$snapshot" >"$state_dir/snapshot.json"
  printf '%s\n' "$target_id" >"$state_dir/window-id"
  printf '%s\n' "$mode" >"$state_dir/mode"
}

restore_target() {
  local state_dir=$1
  local target_id
  target_id=$(<"$state_dir/window-id")
  "$ctl" window focus "$target_id" >/dev/null 2>&1
}

emit_state() {
  local state_dir=$1
  local token=$2
  local mode=$3
  local active=$4
  local snapshot
  snapshot=$(<"$state_dir/snapshot.json")
  jq -n \
    --arg token "$token" \
    --arg mode "$mode" \
    --argjson active "$active" \
    --argjson protectedWindow "$(jq '.result.payload.window' <<<"$snapshot")" \
    '{ok: true, token: $token, mode: $mode, active: $active,
      protectedWindow: $protectedWindow}'
}

run_guard() {
  local state_dir=$1
  local ttl=$2
  local target_id current current_id deadline watcher_pid
  target_id=$(<"$state_dir/window-id")
  deadline=$((SECONDS + ttl))

  "$ctl" watch focus --no-send-initial --exec "$0" _event "$state_dir" \
    >/dev/null 2>&1 &
  watcher_pid=$!
  sleep 0.1
  kill -0 "$watcher_pid" >/dev/null 2>&1 || return 1
  : >"$state_dir/ready"

  while [[ ! -e "$state_dir/stop" && "$SECONDS" -lt "$deadline" ]]; do
    kill -0 "$watcher_pid" >/dev/null 2>&1 || break
    current=$("$ctl" query focused-window --format json 2>/dev/null) || break
    current_id=$(jq -r '.result.payload.window.id // empty' <<<"$current")
    if [[ -n "$current_id" && "$current_id" != "$target_id" ]]; then
      "$ctl" window focus "$target_id" >/dev/null 2>&1 || break
    fi
    sleep 0.25
  done

  kill "$watcher_pid" >/dev/null 2>&1 || true
  wait "$watcher_pid" 2>/dev/null || true
  restore_target "$state_dir" >/dev/null 2>&1 || true
  : >"$state_dir/done"
}

handle_focus_event() {
  local state_dir=$1
  local target_id current current_id
  [[ -d "$state_dir" && ! -e "$state_dir/stop" ]] || return 0
  ctl=$(find_ctl) || return 0
  target_id=$(<"$state_dir/window-id")
  current=$("$ctl" query focused-window --format json 2>/dev/null) || return 0
  current_id=$(jq -r '.result.payload.window.id // empty' <<<"$current")
  if [[ -n "$current_id" && "$current_id" != "$target_id" ]]; then
    "$ctl" window focus "$target_id" >/dev/null 2>&1 || true
  fi
}

command_name=${1:-}
case "$command_name" in
  capture)
    [[ $# -eq 1 ]] || { usage >&2; exit 64; }
    require_dependencies
    create_state capture
    emit_state "$state_dir" "$token" capture false
    ;;
  guard)
    shift
    ttl=20
    while (($#)); do
      case "$1" in
        --ttl)
          [[ $# -ge 2 ]] || { usage >&2; exit 64; }
          ttl=$2
          shift 2
          ;;
        *)
          usage >&2
          exit 64
          ;;
      esac
    done
    [[ "$ttl" =~ ^[0-9]+$ ]] && ((ttl >= 1 && ttl <= 300)) || {
      printf '%s\n' 'TTL must be an integer from 1 through 300 seconds.' >&2
      exit 64
    }
    require_dependencies
    create_state guard
    nohup "$0" _run "$state_dir" "$ttl" >/dev/null 2>&1 &
    worker_pid=$!
    printf '%s\n' "$worker_pid" >"$state_dir/pid"
    ready=false
    for _ in {1..20}; do
      if [[ -e "$state_dir/ready" ]]; then
        ready=true
        break
      fi
      kill -0 "$worker_pid" >/dev/null 2>&1 || break
      sleep 0.05
    done
    if [[ "$ready" != true ]]; then
      : >"$state_dir/stop"
      kill "$worker_pid" >/dev/null 2>&1 || true
      wait "$worker_pid" 2>/dev/null || true
      rm -R "$state_dir"
      printf '%s\n' 'Focus guard failed to start.' >&2
      exit 1
    fi
    emit_state "$state_dir" "$token" guard true
    ;;
  restore)
    [[ $# -eq 2 ]] || { usage >&2; exit 64; }
    token=$2
    validate_token "$token"
    require_dependencies
    state_dir="$state_root/$token"
    [[ -d "$state_dir" && -f "$state_dir/window-id" ]] || {
      printf 'Unknown or expired focus token: %s\n' "$token" >&2
      exit 2
    }
    mode=$(<"$state_dir/mode")
    : >"$state_dir/stop"
    if [[ -f "$state_dir/pid" ]]; then
      worker_pid=$(<"$state_dir/pid")
      for _ in {1..20}; do
        [[ -e "$state_dir/done" ]] && break
        kill -0 "$worker_pid" >/dev/null 2>&1 || break
        sleep 0.05
      done
    fi
    restored=false
    if restore_target "$state_dir"; then
      restored=true
    fi
    snapshot=$(<"$state_dir/snapshot.json")
    rm -R "$state_dir"
    jq -n \
      --arg token "$token" \
      --arg mode "$mode" \
      --argjson restored "$restored" \
      --argjson protectedWindow "$(jq '.result.payload.window' <<<"$snapshot")" \
      '{ok: true, token: $token, mode: $mode, restored: $restored,
        protectedWindow: $protectedWindow}'
    ;;
  status)
    [[ $# -eq 2 ]] || { usage >&2; exit 64; }
    token=$2
    validate_token "$token"
    state_dir="$state_root/$token"
    [[ -d "$state_dir" && -f "$state_dir/window-id" ]] || {
      jq -n --arg token "$token" \
        '{ok: false, token: $token, active: false, error: "unknown_or_expired"}'
      exit 2
    }
    mode=$(<"$state_dir/mode")
    active=false
    if [[ "$mode" == guard && ! -e "$state_dir/done" && -f "$state_dir/pid" ]]; then
      worker_pid=$(<"$state_dir/pid")
      kill -0 "$worker_pid" >/dev/null 2>&1 && active=true
    fi
    emit_state "$state_dir" "$token" "$mode" "$active"
    ;;
  _run)
    [[ $# -eq 3 ]] || exit 64
    require_dependencies
    run_guard "$2" "$3"
    ;;
  _event)
    [[ $# -eq 2 ]] || exit 64
    command -v jq >/dev/null 2>&1 || exit 0
    handle_focus_event "$2"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
