#!/usr/bin/env bash
set -euo pipefail

state_dir=${FAKE_OMNIWM_STATE:?FAKE_OMNIWM_STATE is required}

focused_window() {
  local current_id window
  current_id=$(<"$state_dir/current-id")
  window=$(jq -c --arg id "$current_id" '.[] | select(.id == $id)' \
    "$state_dir/windows.json")
  jq -n --argjson window "$window" \
    '{ok: true, result: {payload: {window: $window}}}'
}

case "${1:-}" in
  ping)
    printf '%s\n' pong
    ;;
  version)
    if [[ "${2:-}" == --format && "${3:-}" == json ]]; then
      jq -n '{ok: true, result: {kind: "version", payload: {
        appVersion: "0.6.1-test", protocolVersion: 10
      }}}'
    else
      printf '%s\n' 'test (protocol 10)'
    fi
    ;;
  query)
    case "${2:-}" in
      focused-window)
        focused_window
        ;;
      windows)
        jq -n --argjson windows "$(<"$state_dir/windows.json")" \
          '{ok: true, result: {payload: {windows: $windows}}}'
        ;;
      *)
        exit 64
        ;;
    esac
    ;;
  window)
    [[ "${2:-}" == focus && -n "${3:-}" ]] || exit 64
    printf '%s\n' "$3" >"$state_dir/current-id"
    printf '%s\n' "$3" >>"$state_dir/focus.log"
    ;;
  watch)
    trap 'exit 0' TERM INT
    while :; do
      sleep 0.1
    done
    ;;
  *)
    exit 64
    ;;
esac
