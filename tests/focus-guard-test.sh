#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
guard="$repo_dir/scripts/focus-guard.sh"
fake_ctl="$script_dir/fake-omniwmctl.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/omniwm-focus-guard-test.XXXXXX")
active_token=''

cleanup() {
  if [[ -n "$active_token" ]]; then
    OMNIWMCTL="$fake_ctl" FAKE_OMNIWM_STATE="${FAKE_OMNIWM_STATE:-}" \
      TMPDIR="${case_tmp:-${TMPDIR:-/tmp}}" \
      "$guard" restore "$active_token" >/dev/null 2>&1 || true
  fi
  rm -R "$test_root"
}
trap cleanup EXIT

protected='{"id":"protected","app":{"bundleId":"com.test.Protected","name":"Protected"}}'
user_window='{"id":"user","app":{"bundleId":"com.test.User","name":"User"}}'
agent_window='{"id":"agent","app":{"bundleId":"com.google.Chrome","name":"Google Chrome"}}'

start_case() {
  local name=$1
  FAKE_OMNIWM_STATE="$test_root/$name/state"
  case_tmp="$test_root/$name/tmp"
  export FAKE_OMNIWM_STATE case_tmp
  mkdir -p "$FAKE_OMNIWM_STATE" "$case_tmp"
  printf '%s\n' protected >"$FAKE_OMNIWM_STATE/current-id"
  : >"$FAKE_OMNIWM_STATE/focus.log"
}

write_windows() {
  jq -n "$1" >"$FAKE_OMNIWM_STATE/windows.json"
}

set_focus() {
  printf '%s\n' "$1" >"$FAKE_OMNIWM_STATE/current-id"
}

start_guard() {
  local response
  if (($#)); then
    response=$(OMNIWMCTL="$fake_ctl" TMPDIR="$case_tmp" \
      "$guard" guard --ttl 3 "$@")
  else
    response=$(OMNIWMCTL="$fake_ctl" TMPDIR="$case_tmp" \
      "$guard" guard --ttl 3)
  fi
  token=$(jq -r '.token' <<<"$response")
  active_token=$token
}

wait_for_outcome() {
  local expected=$1
  local response outcome
  for _ in {1..60}; do
    response=$(OMNIWMCTL="$fake_ctl" TMPDIR="$case_tmp" \
      "$guard" status "$token")
    outcome=$(jq -r '.outcome' <<<"$response")
    if [[ "$outcome" == "$expected" ]]; then
      printf '%s\n' "$response"
      return 0
    fi
    sleep 0.05
  done
  printf 'Timed out waiting for outcome %s; last outcome was %s\n' \
    "$expected" "${outcome:-unknown}" >&2
  return 1
}

finish_guard() {
  local response
  response=$(OMNIWMCTL="$fake_ctl" TMPDIR="$case_tmp" \
    "$guard" restore "$token")
  active_token=''
  printf '%s\n' "$response"
}

# Guard cleanup is cancellation only; foreground capture cleanup still restores.
start_case cancelled-guard
write_windows "[$protected, $user_window]"
start_guard
cleanup_result=$(finish_guard)
jq -e '.outcome == "cancelled" and .restored == false' \
  <<<"$cleanup_result" >/dev/null
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == protected ]]

start_case capture-lease
write_windows "[$protected, $user_window]"
capture_response=$(OMNIWMCTL="$fake_ctl" TMPDIR="$case_tmp" "$guard" capture)
token=$(jq -r '.token' <<<"$capture_response")
active_token=$token
set_focus user
cleanup_result=$(finish_guard)
jq -e '.outcome == "restored" and .restored == true' \
  <<<"$cleanup_result" >/dev/null
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == protected ]]

# An existing unrelated window represents user intent. Yield without refocusing.
start_case user-yield
write_windows "[$protected, $user_window]"
start_guard
set_focus user
status=$(wait_for_outcome yielded)
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == user ]]
[[ ! -s "$FAKE_OMNIWM_STATE/focus.log" ]]
cleanup_result=$(finish_guard)
jq -e '.outcome == "yielded" and .restored == false' \
  <<<"$cleanup_result" >/dev/null
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == user ]]

# A newly created window is intercepted once, then later user focus is untouched.
start_case new-window
write_windows "[$protected, $user_window]"
start_guard
write_windows "[$protected, $user_window, $agent_window]"
set_focus agent
status=$(wait_for_outcome intercepted)
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == protected ]]
[[ "$(wc -l <"$FAKE_OMNIWM_STATE/focus.log" | tr -d ' ')" == 1 ]]
set_focus user
sleep 0.3
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == user ]]
[[ "$(wc -l <"$FAKE_OMNIWM_STATE/focus.log" | tr -d ' ')" == 1 ]]
cleanup_result=$(finish_guard)
jq -e '.outcome == "intercepted" and .restored == false' \
  <<<"$cleanup_result" >/dev/null
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == user ]]

# An expected automation app is intercepted even when its window already existed.
start_case expected-app
write_windows "[$protected, $user_window, $agent_window]"
start_guard --expect-bundle-id com.google.Chrome
set_focus agent
status=$(wait_for_outcome intercepted)
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == protected ]]
[[ "$(wc -l <"$FAKE_OMNIWM_STATE/focus.log" | tr -d ' ')" == 1 ]]
set_focus user
sleep 0.3
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == user ]]
cleanup_result=$(finish_guard)
jq -e '.outcome == "intercepted" and .restored == false' \
  <<<"$cleanup_result" >/dev/null
[[ "$(<"$FAKE_OMNIWM_STATE/current-id")" == user ]]

printf '%s\n' 'PASS: focus guard yields to users and intercepts automation once.'
