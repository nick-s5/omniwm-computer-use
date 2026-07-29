---
name: omniwm-computer-use
description: Coordinate browser automation, app launches, app testing, and Computer Use with OmniWM's Niri-style scrolling workspaces and multiple displays on macOS. Use whenever Codex may open, activate, focus, move, resize, hide, or close a local Mac window—including Playwright, Chrome, browser plugins, `open`, and apps under test—or when a window may be offscreen, on another workspace/display, or one of several app windows. Preserve the user's current focus and layout unless the user explicitly asks to leave another app active.
---

# OmniWM Computer Use

Use Computer Use for content inside an app. Use `omniwmctl` for window identity, focus, visibility, workspace navigation, and sizing.

OmniWM can place an unfocused Niri column outside the physical display and inactive-workspace windows at negative coordinates. Computer Use can still read such a window's accessibility tree and capture an app-local screenshot. Do not change focus merely to inspect a known single window. Coordinate clicks, drags, multi-window targeting, and cross-display work require explicit OmniWM coordination.

## Install the complete focus-safety stack

For a new machine or cloned copy, follow [references/setup.md](references/setup.md). Use `scripts/install.sh` for an idempotent installation and `scripts/verify-setup.sh` to validate skill registration, the global agent rule, OmniWM IPC, and a real focus capture/restore cycle.

## Locate the CLI

Prefer the CLI over hotkeys. Use the copy bundled with the installed app so its IPC protocol always matches OmniWM; a separately installed `omniwmctl` may be stale.

```bash
BUNDLED_CTL=/Applications/OmniWM.app/Contents/MacOS/omniwmctl
if [[ -x "$BUNDLED_CTL" ]]; then
  CTL=$BUNDLED_CTL
else
  CTL="$(command -v omniwmctl || true)"
fi
[[ -n "$CTL" ]] || { echo "omniwmctl not found" >&2; exit 1; }
"$CTL" ping
```

If `ping` fails, check whether OmniWM is running and whether `general.ipcEnabled` is true in `~/.config/omniwm/settings.toml`. Continue with normal Computer Use when the target window is unmanaged; `omniwmctl query windows` only returns OmniWM-managed windows.

OmniWM's IPC clients are protocol-coupled to the app. Never work around a protocol mismatch with an older binary or old wire/command names; upgrade or rebuild the app, CLI, helper scripts, and any third-party IPC client together.

Use JSON output and `jq` for decisions:

```bash
"$CTL" query focused-window --format json
"$CTL" query windows --format json
"$CTL" query workspaces --format json
"$CTL" query capabilities --format json
```

Treat every returned window ID as session-scoped. Query it again instead of saving it across OmniWM restarts.

## Protect the user's focus

Treat the currently focused window as protected whenever an action may launch or activate a GUI. This includes Playwright or browser-plugin navigation that opens Chrome, `open`, app launches, test runners that launch an app, popups, downloads, and Computer Use actions. Do not leave an automation window active unless the user explicitly requests it.

First decide whether the automation needs the target app to be frontmost:

- Prefer headless, in-app, or explicitly non-activating launch modes whenever they meet the task. Preventing activation avoids both focus churn and visible workspace animations.
- For Playwright and other background-capable automation, start a short-lived guard immediately before each call that may activate or open a window. Restore it immediately after the call, including after errors. Do not leave a guard running between tool calls or while waiting for the user.
- For coordinate actions or other foreground-only work, capture the current focus, focus the exact target, perform one bounded interaction, and restore immediately. Capture again before every later foreground interaction so a user's intervening focus change is respected.
- For read-only accessibility inspection of a known window, do not focus it.

Use the bundled helper. Its guard reacts to OmniWM focus events, polls as a fallback, and expires automatically as a safety measure:

```bash
guard_json=$(scripts/focus-guard.sh guard --ttl 20)
guard_token=$(jq -r '.token' <<<"$guard_json")
# Run exactly one background-capable browser/app action.
scripts/focus-guard.sh restore "$guard_token"

lease_json=$(scripts/focus-guard.sh capture)
lease_token=$(jq -r '.token' <<<"$lease_json")
# Focus the exact target and perform one bounded foreground interaction.
scripts/focus-guard.sh restore "$lease_token"
```

For shell-launched work, install an `EXIT` trap that restores the token. For tool calls that cannot share a shell, call `guard` or `capture`, run the tool, then call `restore` as the very next action.

Before an action that can create a window, query the baseline window IDs. Afterward, diff against a fresh query:

- Close an agent-created temporary window through the owning automation when it is no longer needed.
- If an agent-created window must remain open but does not need foreground interaction, move only that exact fresh window to a dedicated testing workspace or scratchpad, then immediately restore the protected focus.
- Never move, resize, scratchpad, close, or reassign a pre-existing user window merely to make automation easier.
- Avoid layout mutations where possible. Refocusing the protected window restores its workspace, display, and visible Niri column. If the agent changed sizing or placement, reverse that exact change before restoring focus.

If IPC is unavailable, do not proceed with a focus-stealing launch while the user is active or screen sharing. Re-enable compatible OmniWM IPC when authorized, or report that focus containment is unavailable.

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

Use the focus-protection workflow above instead of restoring only at the end of a long task.

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

Focus the target first. Niri sizing follows the monitor's axes: the primary axis is horizontal on a landscape display and vertical on a portrait display. Change the container's primary span for an ordinary one-window container and the window's secondary span for a stack.

```bash
"$CTL" command set-container-primary-span 50%
"$CTL" command set-container-primary-span +10%
"$CTL" command set-container-primary-span -10%
"$CTL" command set-window-secondary-span 75%
"$CTL" command reset-window-secondary-span
"$CTL" command cycle-size forward
"$CTL" command cycle-size backward
"$CTL" command toggle-container-full-primary-span
"$CTL" command expand-container-to-available-primary-span
```

After every resize, poll until the complete `frame` is identical for at least five consecutive 100 ms samples, then fetch a fresh Computer Use state. Do not accept the first changed frame during an animation. OmniWM may return `executed` while an app rule's minimum size prevents a visible change.

On multiple displays, compare against the target display returned by the window query rather than the main or currently focused display. Use `--fit-visible` when an oversized or displaced Niri container must be fully available for coordinate actions. The helper uses `center-column` when the size already fits and `expand-container-to-available-primary-span` when the container is too large along its monitor's primary axis, then verifies containment after the frame settles.

For temporary resizing, prefer a reversible preset step such as `cycle-size forward` followed by `backward`, or record and restore the actual configured preset. Do not assume `100%` was the original span. Read `niri.containerPrimarySpanPresets`, `niri.defaultContainerPrimarySpan`, and app minimums from `~/.config/omniwm/settings.toml`.

Do not infer monitor UUIDs from pre-0.5.9 numeric display IDs. After upgrading, use **Settings → Monitors → Run Monitor Setup…**, then re-save per-monitor Workspace Bar, orientation, Niri, Dwindle, and gap overrides and any specifically assigned workspace. This avoids silently attaching a rule to the wrong physical display.

## Use hotkeys only as a fallback

Hotkeys are user-configurable and can drift. Re-read the `[[hotkeys]]` entries in `~/.config/omniwm/settings.toml` before sending one through Computer Use. Match the desired current action ID to its configured `binding`; ignore entries whose binding is `Unassigned`.

Computer Use key syntax names Option as `alt`, for example `alt+Right` or `alt+shift+equal`. Prefer the equivalent CLI command because it is explicit, verifiable, and independent of the active keyboard focus.
