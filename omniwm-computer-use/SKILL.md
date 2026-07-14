---
name: omniwm-computer-use
description: Coordinate Computer Use with OmniWM's Niri-style scrolling workspaces and multiple displays on Nicholas's Mac. Use whenever controlling local Mac app windows with Computer Use on this machine, especially when a window may be offscreen or on an inactive workspace, an app has multiple windows, coordinate clicks or drags fail, or Codex must switch workspaces or displays, focus a precise window, or resize it for reliable interaction.
---

# OmniWM Computer Use

Use Computer Use for content inside an app. Use `omniwmctl` for window identity, focus, visibility, workspace navigation, and sizing.

OmniWM can place an unfocused Niri column outside the physical display and inactive-workspace windows at negative coordinates. Computer Use can still read such a window's accessibility tree and capture an app-local screenshot. Do not change focus merely to inspect a known single window. Coordinate clicks, drags, multi-window targeting, and cross-display work require explicit OmniWM coordination.

## Locate the CLI

Prefer the CLI over hotkeys. It is installed inside the app bundle and is not necessarily on `PATH`.

```bash
CTL="$(command -v omniwmctl || true)"
if [[ -z "$CTL" ]]; then
  CTL=/Applications/OmniWM.app/Contents/MacOS/omniwmctl
fi
"$CTL" ping
```

If `ping` fails, check whether OmniWM is running and whether `general.ipcEnabled` is true in `~/.config/omniwm/settings.toml`. Continue with normal Computer Use when the target window is unmanaged; `omniwmctl query windows` only returns OmniWM-managed windows.

Use JSON output and `jq` for decisions:

```bash
"$CTL" query focused-window --format json
"$CTL" query windows --format json
"$CTL" query workspaces --format json
"$CTL" query capabilities --format json
```

Treat every returned window ID as session-scoped. Query it again instead of saving it across OmniWM restarts.

## Target a window before acting

1. Query OmniWM first for browsers, Slack, or any app that may have multiple windows. `get_app_state` otherwise selects whichever app window the accessibility service prefers, which may be on the wrong display or workspace.
2. Disambiguate by bundle ID and OmniWM title. Never choose an arbitrary result from a multi-window app.
3. Focus the exact opaque window ID. `window focus` switches to its workspace and display, then scrolls its Niri column onscreen.
4. Wait until the focused window's frame is stable for several samples. Focus and resize animations make the first changed frame unreliable.
5. Before coordinate actions, compare the entire window frame with its target display's `visibleFrame`. OmniWM's `isVisible` can mean partially visible.
6. Fetch a fresh Computer Use app state before acting. Accessibility element indexes from the earlier state may be stale.

For a known single window and read-only inspection, call Computer Use directly without changing focus. Offscreen accessibility trees and app-local screenshots still work.

Use the bundled helper for steps 2 through 5:

```bash
scripts/focus-window.sh --bundle-id com.canva.affinity
scripts/focus-window.sh --bundle-id app.zen-browser.zen \
  --title-contains "Private Browsing"
scripts/focus-window.sh --bundle-id com.canva.affinity --fit-visible
```

The helper refuses zero or multiple matches and prints candidates instead of guessing. It waits for a stable focused frame and returns the window, target display, `fullyContained`, `fitApplied`, and `originalFrame` fields. `--fit-visible` is optional and may center or resize a Niri column; use it only when full physical visibility is required for coordinate actions.

OmniWM and the accessibility tree may report different browser titles for the same logical window. Use the OmniWM title only to select the window, then verify logical markers such as a private-browsing label or page URL in Computer Use. Computer Use cannot target the Codex/ChatGPT app itself for safety.

To work manually:

```bash
"$CTL" query windows --bundle-id com.apple.Safari --format json
"$CTL" window focus '<fresh-opaque-id>'
"$CTL" query windows --window '<fresh-opaque-id>' \
  --fields id,app,title,workspace,display,frame,is-focused,is-visible,hidden-reason \
  --format json
"$CTL" query displays --display '<target-display-id>' --format json
```

Capture the initially focused window ID before background work and restore it with `window focus` at the end when leaving another app focused is not part of the request.

## Navigate Niri workspaces and columns

Prefer exact window focus over relative navigation. Use relative commands only when the task itself is spatial.

```bash
"$CTL" workspace focus-name Admin
"$CTL" command switch-workspace anywhere 5
"$CTL" command focus left
"$CTL" command focus right
"$CTL" command focus previous
"$CTL" command focus-column first
"$CTL" command center-column
"$CTL" command focus-monitor next
```

Do not use `move`, `move-to-workspace`, layout toggles, scratchpad commands, or `summon-right` merely to expose a window. Those commands mutate the user's layout; `window focus` is sufficient for Computer Use.

## Resize for reliable interaction

Focus the target first. In a Niri workspace, change the column width for ordinary one-window columns and the window height for vertical stacks.

```bash
"$CTL" command set-column-width 50%
"$CTL" command set-column-width +10%
"$CTL" command set-column-width -10%
"$CTL" command set-window-height 75%
"$CTL" command reset-window-height
"$CTL" command cycle-column-width forward
"$CTL" command cycle-column-width backward
"$CTL" command toggle-column-full-width
"$CTL" command expand-column-to-available-width
```

After every resize, poll until the complete `frame` is identical for at least five consecutive 100 ms samples, then fetch a fresh Computer Use state. Do not accept the first changed frame during an animation. OmniWM may return `executed` while an app rule's minimum size prevents a visible change.

On multiple displays, compare against the target display returned by the window query rather than the main or currently focused display. Use `--fit-visible` when an oversized or displaced Niri column must be fully available for coordinate actions. The helper uses `center-column` when the size already fits and `expand-column-to-available-width` when the column is too wide, then verifies containment after the frame settles.

For temporary resizing, prefer a reversible preset step such as `cycle-column-width forward` followed by `backward`, or record and restore the actual configured preset. Do not assume `100%` was the original width. Read current presets and app minimums from `~/.config/omniwm/settings.toml`.

## Use hotkeys only as a fallback

Hotkeys are user-configurable and can drift. Re-read the `[[hotkeys]]` entries in `~/.config/omniwm/settings.toml` before sending one through Computer Use. In the current configuration, the important mappings are:

- `Option+Left/Right/Up/Down`: focus direction
- `Option+Tab`: focus previous window
- `Option+1` through `Option+9`: switch workspace
- `Option+Comma/Period`: cycle column width backward/forward
- `Option+Minus/Equal`: decrease/increase column width by 10 percent
- `Option+Shift+Minus/Equal`: decrease/increase window height by 10 percent
- `Option+Return`: toggle fullscreen

Computer Use key syntax names Option as `alt`, for example `alt+Right` or `alt+shift+equal`. Prefer the equivalent CLI command because it is explicit, verifiable, and independent of the active keyboard focus.
