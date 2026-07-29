#!/usr/bin/env bash
set -euo pipefail

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
ctl=/Applications/OmniWM.app/Contents/MacOS/omniwmctl

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
version=$("$ctl" version)
printf 'PASS: OmniWM IPC is live: %s\n' "$version"

focus_token=''
cleanup() {
  if [[ -n "$focus_token" ]]; then
    "$script_dir/focus-guard.sh" restore "$focus_token" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

capture_json=$("$script_dir/focus-guard.sh" capture)
focus_token=$(jq -r '.token' <<<"$capture_json")
[[ -n "$focus_token" && "$focus_token" != null ]] || {
  printf '%s\n' 'FAIL: focus capture did not return a token.' >&2
  exit 2
}
status_json=$("$script_dir/focus-guard.sh" status "$focus_token")
jq -e '.ok == true and .mode == "capture" and .active == false' \
  <<<"$status_json" >/dev/null
restore_json=$("$script_dir/focus-guard.sh" restore "$focus_token")
focus_token=''
jq -e '.ok == true and .restored == true' <<<"$restore_json" >/dev/null

printf '%s\n' 'PASS: focus capture, status, and restoration succeeded.'
printf '%s\n' 'OmniWM focus-safety setup verified.'
