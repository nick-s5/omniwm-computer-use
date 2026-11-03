#!/usr/bin/env bash
set -euo pipefail

check_restore=false
case "${1:-}" in
  '') ;;
  --check-restore) check_restore=true ;;
  *) printf '%s\n' 'Usage: verify-setup.sh [--check-restore]' >&2; exit 64 ;;
esac
[[ $# -le 1 ]] || { printf '%s\n' 'Usage: verify-setup.sh [--check-restore]' >&2; exit 64; }

command -v jq >/dev/null 2>&1 || {
  printf '%s\n' 'FAIL: jq is required.' >&2
  exit 69
}
command -v python3 >/dev/null 2>&1 || {
  printf '%s\n' 'FAIL: Python 3 is required.' >&2
  exit 69
}
python3 -c 'import tomllib' >/dev/null 2>&1 || {
  printf '%s\n' 'FAIL: Python 3.11 or later with tomllib is required.' >&2
  exit 69
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
skill_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
codex_root=$(python3 - "${CODEX_HOME:-"$HOME/.codex"}" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
)
settings_file=${OMNIWM_SETTINGS:-"$HOME/.config/omniwm/settings.toml"}
skill_link="$codex_root/skills/omniwm-computer-use"
agents_file="$codex_root/AGENTS.md"
ctl="${OMNIWM_APP_PATH:-/Applications/OmniWM.app}/Contents/MacOS/omniwmctl"

[[ -x "$ctl" ]] || {
  printf 'FAIL: bundled omniwmctl not found at %s\n' "$ctl" >&2
  exit 69
}
[[ -d "$skill_link" ]] || {
  printf 'FAIL: installed skill directory not found: %s\n' "$skill_link" >&2
  exit 2
}
installed_target=$(python3 - "$skill_link" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
)
[[ "$installed_target" == "$skill_dir" ]] || {
  printf 'FAIL: installed skill points to %s instead of %s\n' \
    "$installed_target" "$skill_dir" >&2
  exit 2
}
[[ -f "$agents_file" ]] || {
  printf 'FAIL: global AGENTS.md not found: %s\n' "$agents_file" >&2
  exit 2
}
grep -Fq '<!-- omniwm-computer-use:begin -->' "$agents_file" || {
  printf '%s\n' 'FAIL: global OmniWM rule begin marker is missing.' >&2
  exit 2
}
grep -Fq "$skill_link/SKILL.md" "$agents_file" || {
  printf '%s\n' 'FAIL: global OmniWM rule does not reference the installed skill.' >&2
  exit 2
}

python3 - "$settings_file" <<'PY'
from pathlib import Path
import sys
import tomllib

path = Path(sys.argv[1])
with path.open("rb") as handle:
    settings = tomllib.load(handle)
if settings.get("general", {}).get("ipcEnabled") is not True:
    raise SystemExit(f"FAIL: general.ipcEnabled is not true in {path}")
print("PASS: OmniWM settings are valid and IPC is enabled.")
PY

"$ctl" ping >/dev/null
version_json=$("$ctl" version --format json)
jq -e '
  .ok == true and
  .result.kind == "version" and
  (.result.payload.appVersion | type == "string") and
  (.result.payload.protocolVersion | type == "number")
' <<<"$version_json" >/dev/null || {
  printf '%s\n' 'FAIL: bundled omniwmctl returned an unexpected version response.' >&2
  exit 2
}
protocol_version=$(jq -r '.result.payload.protocolVersion' <<<"$version_json")
app_version=$(jq -r '.result.payload.appVersion' <<<"$version_json")
((protocol_version == 10 || protocol_version == 19)) || {
  printf 'FAIL: OmniWM protocol %s is unsupported (expected 10 or 19).\n' \
    "$protocol_version" >&2
  exit 2
}

capabilities_json=$("$ctl" query capabilities --format json)
jq -e --argjson protocol "$protocol_version" '
  .ok == true and
  .result.kind == "capabilities" and
  .result.payload.protocolVersion == $protocol and
  (.result.payload.commands | type == "array") and
  (.result.payload.queries | type == "array") and
  (.result.payload.subscriptions | type == "array") and
  (.result.payload.windowActions | type == "array") and
  any(.result.payload.queries[]; .name == "focused-window") and
  any(.result.payload.queries[]; .name == "windows") and
  any(.result.payload.subscriptions[];
    .channel == "focus" and .resultKind == "focused-window") and
  any(.result.payload.windowActions[];
    .name == "focus" and .path == "window focus <opaque-id>") and
  any(.result.payload.commands[];
    .name == "resize" and
    .path == "command resize <horizontal|vertical> <grow|shrink>") and
  any(.result.payload.commands[];
    .name == "resize-focused" and
    .path == "command resize-focused <grow|shrink>")
' <<<"$capabilities_json" >/dev/null || {
  printf '%s\n' 'FAIL: OmniWM returned an incompatible capabilities response.' >&2
  exit 2
}
printf 'PASS: OmniWM %s IPC protocol %s and capabilities are compatible.\n' \
  "$app_version" "$protocol_version"

focused_json=$("$ctl" query focused-window --format json)
windows_json=$("$ctl" query windows --format json)
jq -e --argjson focused "$focused_json" '
  .ok == true and .result.kind == "windows" and
  (.result.payload.windows | type == "array") and
  ($focused.ok == true and $focused.result.kind == "focused-window") and
  ($focused.result.payload.window.id | type == "string" and length > 0) and
  ($focused.result.payload.window.app.bundleId | type == "string" and length > 0) and
  ($focused.result.payload.window.app.name | type == "string" and length > 0) and
  any(.result.payload.windows[];
    .id == $focused.result.payload.window.id and
    (.app.bundleId | type == "string") and
    (.app.name | type == "string"))
' <<<"$windows_json" >/dev/null || {
  printf '%s\n' 'FAIL: focused window and window inventory do not match the guard schema.' >&2
  exit 2
}
printf '%s\n' 'PASS: focused-window and windows queries match the guard schema.'

if [[ "$check_restore" != true ]]; then
  printf '%s\n' 'OmniWM focus-safety setup verified (read-only).'
  exit 0
fi

focus_token=''
cleanup() {
  if [[ -n "$focus_token" ]]; then
    OMNIWMCTL="$ctl" "$script_dir/focus-guard.sh" restore "$focus_token" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

capture_json=$(OMNIWMCTL="$ctl" "$script_dir/focus-guard.sh" capture)
focus_token=$(jq -r '.token' <<<"$capture_json")
[[ -n "$focus_token" && "$focus_token" != null ]] || {
  printf '%s\n' 'FAIL: focus capture did not return a token.' >&2
  exit 2
}
status_json=$(OMNIWMCTL="$ctl" "$script_dir/focus-guard.sh" status "$focus_token")
jq -e '.ok == true and .mode == "capture" and .active == false' \
  <<<"$status_json" >/dev/null
restore_json=$(OMNIWMCTL="$ctl" "$script_dir/focus-guard.sh" restore "$focus_token")
focus_token=''
jq -e '.ok == true and .restored == true' <<<"$restore_json" >/dev/null

printf '%s\n' 'PASS: focus capture, status, and restoration succeeded.'
printf '%s\n' 'OmniWM focus-safety setup verified (restore check).'
