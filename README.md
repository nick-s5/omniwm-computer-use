# OmniWM Computer Use

A Codex skill for reliably controlling macOS apps through Computer Use when [OmniWM](https://github.com/BarutSRB/OmniWM) uses Niri-style scrolling workspaces and multiple displays.

OmniWM can keep unfocused columns outside the physical display or place inactive-workspace windows at negative coordinates. Computer Use can often inspect those windows, but coordinate actions and multi-window apps need explicit window targeting. This skill coordinates both systems through `omniwmctl`.

## What it handles

- Targets an exact window by bundle ID, app name, and optional title text.
- Refuses ambiguous multi-window matches instead of guessing.
- Switches to the correct workspace and display.
- Waits for focus and resize animations to settle.
- Verifies full containment against the target display's visible frame.
- Optionally centers or fits a Niri column with `--fit-visible`.
- Documents current OmniWM hotkey fallbacks and Computer Use limitations.

## Requirements

- macOS with OmniWM running.
- OmniWM IPC enabled with `general.ipcEnabled = true`.
- The `omniwmctl` binary, normally at `/Applications/OmniWM.app/Contents/MacOS/omniwmctl`.
- `jq`.
- Codex with the Computer Use plugin for app interaction.

Tested with OmniWM 0.5.4, IPC protocol 6, on built-in and Sidecar displays.

## Install

```bash
git clone https://github.com/nick-s5/omniwm-computer-use.git
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
cp -R omniwm-computer-use/omniwm-computer-use \
  "${CODEX_HOME:-$HOME/.codex}/skills/omniwm-computer-use"
```

Start a new Codex task after installation so the skill catalog refreshes.

## Helper usage

```bash
omniwm-computer-use/scripts/focus-window.sh \
  --bundle-id com.canva.affinity

omniwm-computer-use/scripts/focus-window.sh \
  --bundle-id app.zen-browser.zen \
  --title-contains "Private Browsing"

omniwm-computer-use/scripts/focus-window.sh \
  --app Slack \
  --fit-visible
```

The helper returns JSON containing the focused window, target display, stable frame, containment result, and any fit action applied.

`--fit-visible` can change the focused column's size or position. Its output includes `originalFrame`, but restoring a semantic OmniWM preset is usually more reliable than restoring raw points after moving between differently sized displays.

## Repository layout

```text
omniwm-computer-use/
  SKILL.md
  agents/openai.yaml
  scripts/focus-window.sh
```
