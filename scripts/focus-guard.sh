#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage:' \
    '  focus-guard.sh capture' \
    '  focus-guard.sh guard [--ttl <seconds>] [--expect-bundle-id <id>] [--expect-app <name>]' \
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
  local expect_bundle_id=${2:-}
  local expect_app=${3:-}
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
  printf '%s\n' "$expect_bundle_id" >"$state_dir/expect-bundle-id"
  printf '%s\n' "$expect_app" >"$state_dir/expect-app"

  if [[ "$mode" == guard ]]; then
    "$ctl" query windows --format json \
      | jq -c '[.result.payload.windows[].id]' \
      >"$state_dir/baseline-window-ids.json"
  fi
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
  local snapshot outcome expect_bundle_id expect_app intercepted_window
  snapshot=$(<"$state_dir/snapshot.json")
  outcome=pending
  [[ -f "$state_dir/outcome" ]] && outcome=$(<"$state_dir/outcome")
  expect_bundle_id=$(<"$state_dir/expect-bundle-id")
  expect_app=$(<"$state_dir/expect-app")
  intercepted_window=null
  if [[ -f "$state_dir/intercepted-window.json" ]]; then
    intercepted_window=$(<"$state_dir/intercepted-window.json")
  fi
  jq -n \
    --arg token "$token" \
    --arg mode "$mode" \
    --argjson active "$active" \
    --arg outcome "$outcome" \
    --arg expectBundleId "$expect_bundle_id" \
    --arg expectApp "$expect_app" \
    --argjson protectedWindow "$(jq '.result.payload.window' <<<"$snapshot")" \
    --argjson interceptedWindow "$intercepted_window" \
    '{ok: true, token: $token, mode: $mode, active: $active,
      outcome: $outcome, expectBundleId: $expectBundleId,
      expectApp: $expectApp, protectedWindow: $protectedWindow,
      interceptedWindow: $interceptedWindow}'
}

run_guard() {
  local state_dir=$1
  local ttl=$2
  local deadline watcher_pid finish_reason
  deadline=$((SECONDS + ttl))

  "$ctl" watch focus --no-send-initial --exec "$0" _event "$state_dir" \
    >/dev/null 2>&1 &
  watcher_pid=$!
  sleep 0.1
  kill -0 "$watcher_pid" >/dev/null 2>&1 || return 1
  : >"$state_dir/ready"

  while [[ ! -e "$state_dir/stop" && ! -e "$state_dir/done" && "$SECONDS" -lt "$deadline" ]]; do
    kill -0 "$watcher_pid" >/dev/null 2>&1 || break
    evaluate_focus_change "$state_dir"
    sleep 0.1
  done

  kill "$watcher_pid" >/dev/null 2>&1 || true
  wait "$watcher_pid" 2>/dev/null || true

  if [[ ! -e "$state_dir/done" ]]; then
    if [[ -e "$state_dir/stop" ]]; then
      finish_reason=cancelled
    elif [[ "$SECONDS" -ge "$deadline" ]]; then
      finish_reason=expired
    else
      finish_reason=watcher-failed
    fi
    printf '%s\n' "$finish_reason" >"$state_dir/outcome"
    : >"$state_dir/done"
  fi
}

evaluate_focus_change() {
  local state_dir=$1
  local target_id current current_id current_bundle_id current_app_name
  local expect_bundle_id expect_app expected_selector matches_expected is_new
  [[ -d "$state_dir" && ! -e "$state_dir/stop" && ! -e "$state_dir/done" ]] || return 0
  ctl=$(find_ctl) || return 0
  target_id=$(<"$state_dir/window-id")
  current=$("$ctl" query focused-window --format json 2>/dev/null) || return 0
  current_id=$(jq -r '.result.payload.window.id // empty' <<<"$current")
  [[ -n "$current_id" && "$current_id" != "$target_id" ]] || return 0

  mkdir "$state_dir/decision.lock" >/dev/null 2>&1 || return 0

  current=$("$ctl" query focused-window --format json 2>/dev/null) || {
    rmdir "$state_dir/decision.lock"
    return 0
  }
  current_id=$(jq -r '.result.payload.window.id // empty' <<<"$current")
  if [[ -z "$current_id" || "$current_id" == "$target_id" ]]; then
    rmdir "$state_dir/decision.lock"
    return 0
  fi

  expect_bundle_id=$(<"$state_dir/expect-bundle-id")
  expect_app=$(<"$state_dir/expect-app")
  current_bundle_id=$(jq -r '.result.payload.window.app.bundleId // empty' <<<"$current")
  current_app_name=$(jq -r '.result.payload.window.app.name // empty' <<<"$current")
  expected_selector=false
  matches_expected=false

  if [[ -n "$expect_bundle_id" || -n "$expect_app" ]]; then
    expected_selector=true
  fi
  if [[ -n "$expect_bundle_id" && "$current_bundle_id" == "$expect_bundle_id" ]]; then
    matches_expected=true
  fi
  if [[ -n "$expect_app" ]] && \
     [[ "$(printf '%s' "$current_app_name" | tr '[:upper:]' '[:lower:]')" == \
        "$(printf '%s' "$expect_app" | tr '[:upper:]' '[:lower:]')" ]]; then
    matches_expected=true
  fi

  is_new=$(jq -r --arg id "$current_id" 'index($id) == null' \
    "$state_dir/baseline-window-ids.json")

  if [[ "$matches_expected" == true ]] || \
     [[ "$expected_selector" == false && "$is_new" == true ]]; then
    jq '.result.payload.window' <<<"$current" >"$state_dir/intercepted-window.json"
    if restore_target "$state_dir"; then
      printf '%s\n' intercepted >"$state_dir/outcome"
    else
      printf '%s\n' restore-failed >"$state_dir/outcome"
    fi
  else
    printf '%s\n' yielded >"$state_dir/outcome"
  fi

  : >"$state_dir/done"
}

handle_focus_event() {
  local state_dir=$1
  command -v jq >/dev/null 2>&1 || return 0
  evaluate_focus_change "$state_dir"
}

command_name=${1:-}
case "$command_name" in
  capture)
    [[ $# -eq 1 ]] || { usage >&2; exit 64; }
    require_dependencies
    create_state capture '' ''
    emit_state "$state_dir" "$token" capture false
    ;;
  guard)
    shift
    ttl=20
    expect_bundle_id=''
    expect_app=''
    while (($#)); do
      case "$1" in
        --ttl)
          [[ $# -ge 2 ]] || { usage >&2; exit 64; }
          ttl=$2
          shift 2
          ;;
        --expect-bundle-id)
          [[ $# -ge 2 ]] || { usage >&2; exit 64; }
          expect_bundle_id=$2
          shift 2
          ;;
        --expect-app)
          [[ $# -ge 2 ]] || { usage >&2; exit 64; }
          expect_app=$2
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
    create_state guard "$expect_bundle_id" "$expect_app"
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
    if [[ "$mode" == capture ]]; then
      if restore_target "$state_dir"; then
        restored=true
        printf '%s\n' restored >"$state_dir/outcome"
      else
        printf '%s\n' restore-failed >"$state_dir/outcome"
      fi
    elif [[ ! -f "$state_dir/outcome" ]]; then
      printf '%s\n' cancelled >"$state_dir/outcome"
    fi
    snapshot=$(<"$state_dir/snapshot.json")
    outcome=pending
    [[ -f "$state_dir/outcome" ]] && outcome=$(<"$state_dir/outcome")
    expect_bundle_id=$(<"$state_dir/expect-bundle-id")
    expect_app=$(<"$state_dir/expect-app")
    intercepted_window=null
    if [[ -f "$state_dir/intercepted-window.json" ]]; then
      intercepted_window=$(<"$state_dir/intercepted-window.json")
    fi
    rm -R "$state_dir"
    jq -n \
      --arg token "$token" \
      --arg mode "$mode" \
      --argjson restored "$restored" \
      --arg outcome "$outcome" \
      --arg expectBundleId "$expect_bundle_id" \
      --arg expectApp "$expect_app" \
      --argjson protectedWindow "$(jq '.result.payload.window' <<<"$snapshot")" \
      --argjson interceptedWindow "$intercepted_window" \
      '{ok: true, token: $token, mode: $mode, restored: $restored,
        outcome: $outcome, expectBundleId: $expectBundleId,
        expectApp: $expectApp, protectedWindow: $protectedWindow,
        interceptedWindow: $interceptedWindow}'
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
