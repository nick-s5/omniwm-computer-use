#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: install.sh [--dry-run]' \
    '' \
    'Environment overrides:' \
    '  CODEX_HOME        Codex configuration root (default: ~/.codex)' \
    '  OMNIWM_SETTINGS   OmniWM settings file (default: ~/.config/omniwm/settings.toml)'
}

dry_run=false
case "${1:-}" in
  '')
    ;;
  --dry-run)
    dry_run=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 64; }

command -v jq >/dev/null 2>&1 || {
  printf '%s\n' 'jq is required.' >&2
  exit 69
}
command -v python3 >/dev/null 2>&1 || {
  printf '%s\n' 'Python 3 is required.' >&2
  exit 69
}
python3 -c 'import tomllib' >/dev/null 2>&1 || {
  printf '%s\n' 'Python 3.11 or later with tomllib is required.' >&2
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
skill_root="$codex_root/skills"
skill_link="$skill_root/omniwm-computer-use"
agents_file="$codex_root/AGENTS.md"
installed_skill_md="$skill_link/SKILL.md"

printf 'Skill source: %s\n' "$skill_dir"
printf 'Skill target: %s\n' "$skill_link"
printf 'Global rules: %s\n' "$agents_file"
printf 'OmniWM settings: %s\n' "$settings_file"

[[ -f "$settings_file" ]] || {
  printf 'OmniWM settings not found: %s\n' "$settings_file" >&2
  exit 66
}

if [[ -e "$skill_link" || -L "$skill_link" ]]; then
  existing_target=$(python3 - "$skill_link" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
)
  if [[ "$existing_target" != "$skill_dir" ]]; then
    printf 'Refusing to replace existing skill target: %s -> %s\n' \
      "$skill_link" "$existing_target" >&2
    exit 73
  fi
  printf '%s\n' 'Installed skill target already resolves to this clone.'
elif [[ "$dry_run" == true ]]; then
  printf '%s\n' 'Would create the installed skill link.'
else
  mkdir -p "$skill_root"
  ln -s "$skill_dir" "$skill_link"
  printf '%s\n' 'Created the installed skill link.'
fi

python3 - "$settings_file" "$dry_run" <<'PY'
import datetime
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import tomllib

path = Path(sys.argv[1])
dry_run = sys.argv[2] == "true"
text = path.read_text()
lines = text.splitlines(keepends=True)
section = None
general_start = None
general_end = len(lines)
key_index = None

for index, line in enumerate(lines):
    match = re.match(r"^\s*\[([^\]]+)\]\s*(?:#.*)?$", line)
    if match:
        next_section = match.group(1).strip()
        if section == "general" and general_end == len(lines):
            general_end = index
        section = next_section
        if section == "general" and general_start is None:
            general_start = index
        continue
    if section == "general" and re.match(r"^\s*ipcEnabled\s*=", line):
        key_index = index

if general_start is None:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.extend(["[general]\n", "ipcEnabled = true\n"])
elif key_index is None:
    lines.insert(general_end, "ipcEnabled = true\n")
else:
    current = lines[key_index]
    replacement = re.sub(
        r"^(\s*ipcEnabled\s*=\s*)(?:true|false)(\s*(?:#.*)?(?:\n)?)$",
        r"\1true\2",
        current,
    )
    if replacement == current and "true" not in current:
        raise SystemExit(f"Could not safely update ipcEnabled in {path}")
    lines[key_index] = replacement

updated = "".join(lines)
parsed = tomllib.loads(updated)
if parsed.get("general", {}).get("ipcEnabled") is not True:
    raise SystemExit("Generated settings did not enable general.ipcEnabled")

if updated == text:
    print("OmniWM IPC is already enabled.")
elif dry_run:
    print("Would enable OmniWM IPC.")
else:
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = path.with_name(f"{path.name}.backup-{timestamp}")
    shutil.copy2(path, backup)
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as handle:
        handle.write(updated)
        temporary = Path(handle.name)
    os.chmod(temporary, path.stat().st_mode)
    os.replace(temporary, path)
    print(f"Enabled OmniWM IPC; backup: {backup}")
PY

python3 - "$agents_file" "$installed_skill_md" "$dry_run" <<'PY'
import datetime
import os
from pathlib import Path
import shutil
import sys
import tempfile

path = Path(sys.argv[1])
skill_md = sys.argv[2]
dry_run = sys.argv[3] == "true"
begin = "<!-- omniwm-computer-use:begin -->"
end = "<!-- omniwm-computer-use:end -->"
block = f"""\
{begin}
## macOS window-focus safety

Before any action that may open, activate, focus, move, resize, hide, or close a Mac app window—including Playwright, Chrome or browser-plugin automation, `open`, app testing, and Computer Use—read and follow `{skill_md}`. Treat the user's currently focused OmniWM window and layout as protected. For background-capable actions, use a one-shot guard with the expected bundle ID or app name when known; yield and disarm on unrelated user focus changes, and never refocus during guard cleanup. For foreground-only interactions, capture immediately before one bounded action and restore immediately afterward. Never leave an automation app active unless the user explicitly requests it.
{end}
"""

text = path.read_text() if path.exists() else ""
if begin in text or end in text:
    if text.count(begin) != 1 or text.count(end) != 1:
        raise SystemExit(f"Malformed OmniWM marker block in {path}")
    start = text.index(begin)
    finish = text.index(end, start) + len(end)
    updated = text[:start] + block.rstrip("\n") + text[finish:]
else:
    separator = "\n\n" if text.strip() else ""
    updated = text.rstrip() + separator + block

if updated == text:
    print("Global OmniWM agent rule is already current.")
elif dry_run:
    print("Would install or update the global OmniWM agent rule.")
else:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = path.with_name(f"{path.name}.backup-{timestamp}")
        shutil.copy2(path, backup)
        print(f"Global rules backup: {backup}")
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as handle:
        handle.write(updated)
        temporary = Path(handle.name)
    if path.exists():
        os.chmod(temporary, path.stat().st_mode)
    os.replace(temporary, path)
    print("Installed the global OmniWM agent rule.")
PY

if [[ "$dry_run" == true ]]; then
  printf '%s\n' 'Dry run complete; no files were changed.'
  exit 0
fi

chmod +x "$script_dir/focus-guard.sh" "$script_dir/focus-window.sh" \
  "$script_dir/install.sh" "$script_dir/verify-setup.sh"

ctl=/Applications/OmniWM.app/Contents/MacOS/omniwmctl
if [[ -x "$ctl" ]] && "$ctl" ping >/dev/null 2>&1; then
  CODEX_HOME="$codex_root" OMNIWM_SETTINGS="$settings_file" \
    "$script_dir/verify-setup.sh"
else
  printf '%s\n' \
    'Configuration installed. Start or restart OmniWM, then run scripts/verify-setup.sh.'
fi
