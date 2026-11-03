---
name: omniwm-computer-use
description: Preserve the user's focus during browser automation and Computer Use on macOS. Use for local GUI automation or window targeting. Foreground work follows the user's current authorization and exact-target focus safeguards.
---

# OmniWM Computer Use

## Background-only default and foreground approval boundary

**Temporary remote-work authorization:** While the user says they are working remotely, foreground Computer Use is authorized without fresh approval for each bounded interaction. The agent may choose foreground execution directly when it serves the task; background-first execution is not required during this period. This authorization remains active until the user says the remote period has ended or revokes it. A current request for background-only work takes precedence over this temporary foreground authorization. It does not authorize unrelated layout changes, arbitrary window selection, or leaving an automation app active. Capture the user's current focus immediately before each bounded foreground interaction, focus the exact target, and restore immediately afterward. All other focus guard and user-focus-change rules below still apply. Outside this period, use the default approval boundary in this section.

By default, run browser automation and Computer Use in the background of whatever the user is doing. Prefer regular native Computer Use through app-local accessibility controls over the Chrome extension for browser UI work. Start with non-activating inspection, then use background-capable native interactions. Use browser-extension/CDP/DOM control or headless automation as alternatives when native controls cannot reliably perform the task, or when the user explicitly requests them. Outside the remote-work authorization, do not use OmniWM to bring an automation app forward and then restore focus as a substitute for background execution. Fast capture/focus/restore cycles still disrupt the user.

- Outside the remote-work authorization, do not call `focus-window.sh`, `omniwmctl window focus`, browser visibility/focus APIs, or activating launch commands merely to enable routine automation. Workspace/layout/resize commands still require their own authorization. Read-only OmniWM queries may disambiguate windows; they are not a requirement for ordinary browser DOM control.
- Outside the remote-work authorization, reads, tab creation/navigation, DOM-based clicks, and screenshots must not be pre-focused. Use a genuinely background-capable path; browser CUA/coordinate APIs are acceptable only when they dispatch in-tab input without requiring native foreground access. Do not classify an operation by its name alone.
- An extension timeout does not establish that native Computer Use requires foreground access. Native accessibility reads and app-local interactions may work while Chrome is unfocused or offscreen. Outside the remote-work authorization, try a bounded native accessibility interaction with the one-shot guard and verify both the resulting UI state and guard outcome; do not pre-focus the window. Do not assume every native click, coordinate action, or keypress is background-capable.
- Outside the remote-work authorization, if a control method stalls or fails, report the limitation and try another supported background-capable method when available. Do not fall back to physical pointer/keyboard input or OmniWM focusing that requires foreground access. If safe background targeting is unavailable, stop and let the user choose whether to retry, perform the step themselves, or authorize a bounded foreground interaction.
- Outside the remote-work authorization, before any foreground-only action, explain the target, expected focus disruption, and bounded action, and obtain explicit approval for that foreground interaction. A general request to complete a task does not authorize stealing focus. The foreground procedures below apply after this approval, during the active remote-work authorization, or to window-management actions the user explicitly requested.
- Keep the one-shot background guard as accidental-activation protection, not an execution strategy. If it intercepts unexpected activation, clean it up, stop further automation in that workflow, report the event, and let the user decide what to do. Do not continue a sequence that repeatedly activates and restores apps.
- Do not change browser settings, disable protection, restart browsers, or alter other agents' tabs to work around a background-control limitation without authorization.

This foreground authorization boundary governs all focusing, hotkey, setup-verification, and native-interaction examples below. Layout changes still require an explicit window-management request or approval. Use Computer Use for app content only when the selected operation meets this boundary; use read-only `omniwmctl` queries for window identity when needed.

OmniWM can place an unfocused Niri column outside the physical display and inactive-workspace windows at negative coordinates. Computer Use can still read such a window's accessibility tree and capture an app-local screenshot. Do not change focus merely to inspect a known single window when background inspection serves the task. If native coordinate clicks or drags require foreground access, use the active remote-work authorization or seek approval before exposing the exact target window.

## Install the complete focus-safety stack

For a new machine or cloned copy, follow [references/setup.md](references/setup.md). Use `scripts/install.sh` for an idempotent installation and `scripts/verify-setup.sh` for read-only validation of skill registration, the global agent rule, OmniWM IPC, and guard query schemas. A focus capture/restore check requires the explicit `--check-restore` option and foreground authorization.

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

If `ping` fails, check whether OmniWM is running and whether `general.ipcEnabled` is true in `~/.config/omniwm/settings.toml`. An unmanaged window or unavailable IPC does not remove the focus-capture and exact-target requirements; use a supported non-activating path or report the limitation if foreground focus cannot be contained. `omniwmctl query windows` only returns OmniWM-managed windows.

OmniWM's IPC clients are protocol-coupled to the app. Never work around a protocol mismatch with an older binary or old wire/command names; upgrade or rebuild the app, CLI, helper scripts, and any third-party IPC client together.

This skill supports the existing OmniWM 0.6.1 / IPC protocol 10 contract and the live-validated 0.7.6 / IPC protocol 19 contract. Protocol 10 has fixture regression coverage but was not rechecked against a live 0.6.1 app in this update. Confirm the live contract with `"$CTL" version --format json` and `"$CTL" help` rather than assuming a separately installed or remembered command surface is current. The verifier rejects unknown protocols.

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

- Outside the remote-work authorization, prefer headless, in-app, or explicitly non-activating launch modes whenever they meet the task. Preventing activation avoids both focus churn and visible workspace animations.
- For Playwright and other background-capable automation, start a one-shot guard immediately before each call that may activate or open a window. Supply the expected bundle ID or app name when known. Stop and clean up the guard immediately after the call, including after errors. Do not leave a guard running between tool calls or while waiting for the user.
- For foreground work authorized by explicit approval or the active remote-work period, capture the current focus, focus the exact target, perform one bounded interaction, and restore immediately. Capture again before every later foreground interaction so a user's intervening focus change is respected. Without either authorization, stop and inform the user.
- For background read-only accessibility inspection of a known window, do not focus it. A native tool reporting its app-local focused element does not itself establish that macOS focus changed; use the guard outcome or a read-only focused-window query to verify. After an interaction, verify the requested UI content or state rather than treating a changed URL alone as proof that loading completed.

### Chrome background interaction observed on this Mac

For native Computer Use, `cua.getApp('com.google.Chrome')` followed by `app.getAXState()` inspected Chrome without activating it. In a disposable, task-owned test tab, `app.click(index)` selected a radio control and `app.setValue(textareaIndex, value)` edited a web field while Chrome remained offscreen at x=2055; OmniWM still reported Codex focused and unchanged window frames. Use fresh accessibility indices, semantic clicks, and `setValue` for text fields. The accessibility tree's focused element is app-local state, not proof that macOS changed its active app. Verify the resulting page state and OmniWM focus after each bounded interaction. This observation does not establish that coordinate clicks, global hotkeys, or every custom widget work in the background.

The Chrome extension also filled and selected controls in that tab, but intermittently returned `Detached` after applying a change. Inspect the resulting state before retrying an uncertain action. DevTools `autoConnect` was unavailable here because `DevToolsActivePort` was missing; do not enable remote debugging as a workaround without authorization. Keep the one-shot guard as backup for accidental activation.

Use the bundled helper. Its guard reacts to OmniWM focus events, polls as a fallback, and expires automatically. It makes one decision, then disarms:

- With `--expect-bundle-id` or `--expect-app`, restore only when that expected automation app takes focus.
- Without a selector, restore only when a window created after guard startup takes focus.
- Treat focus moving to an unrelated pre-existing window as user intent; yield and disarm without restoring.
- After one interception, allow all later focus changes. Guard cleanup never changes focus.

```bash
guard_json=$(scripts/focus-guard.sh guard --ttl 20 \
  --expect-bundle-id com.google.Chrome)
guard_token=$(jq -r '.token' <<<"$guard_json")
# Run exactly one background-capable browser/app action.
scripts/focus-guard.sh restore "$guard_token"

lease_json=$(scripts/focus-guard.sh capture)
lease_token=$(jq -r '.token' <<<"$lease_json")
# With explicit approval or active remote-work authorization: focus the exact
# target and perform one bounded foreground interaction.
scripts/focus-guard.sh restore "$lease_token"
```

For shell-launched work, install an `EXIT` trap that cleans up the token. For tool calls that cannot share a shell, call `guard` or `capture`, run the tool, then call `restore` as the very next action. `restore` re-focuses only a foreground `capture` lease; for a background guard it stops and removes state without changing the user's current focus.

macOS does not expose whether an activation came from the user or the app. An expected-app selector can therefore still intercept one deliberate switch to that same app, but never more than once. Prefer non-activating launches whenever possible.

Before an action that can create a window, query the baseline window IDs. Afterward, diff against a fresh query:

- Close an agent-created temporary window through the owning automation when it is no longer needed.
- If an agent-created window must remain open but cannot remain non-disruptively in the background, report the limitation. Moving it to a testing workspace or scratchpad requires approval for that layout change; move only that exact fresh window, then restore the protected focus.
- Never move, resize, scratchpad, close, or reassign a pre-existing user window merely to make automation easier.
- Avoid layout mutations where possible. Refocusing the protected window restores its workspace, display, and visible Niri column. If the agent changed sizing or placement, reverse that exact change before restoring focus.

If IPC is unavailable, do not proceed with a focus-stealing launch while the user is active or screen sharing. Re-enable compatible OmniWM IPC when authorized, or report that focus containment is unavailable.

## Target a window for authorized foreground work

Do not use this focusing procedure for background browser operations or background read-only inspection. Obtain the foreground approval described above or rely on the active remote-work authorization before starting it.

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

## Navigate Niri workspaces and columns when requested

These commands require an explicit window-management request or approval for the foreground/layout change. They are not a fallback for browser or Computer Use tasks.

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

Do not use `move`, `move-to-workspace`, layout toggles, scratchpad commands, or `summon-right` merely to expose a window. Those commands mutate the user's layout. `window focus` requires explicit approval or active remote-work authorization; it does not make Computer Use background-capable.

## Resize for explicitly approved foreground interaction

Resizing is not part of default background automation. Obtain approval for any required foreground/layout change before following this procedure.

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

Dwindle resize commands are axis-based in OmniWM 0.6.1:

```bash
"$CTL" command resize horizontal grow
"$CTL" command resize horizontal shrink
"$CTL" command resize vertical grow
"$CTL" command resize vertical shrink
"$CTL" command resize-focused grow
"$CTL" command resize-focused shrink
```

Do not use the removed directional form `resize <left|right|up|down> <grow|shrink>`. Map left/right intent to `horizontal` and up/down intent to `vertical`. If a user had custom directional Dwindle resize hotkeys, re-read `[[hotkeys]]` after the upgrade; OmniWM drops those bindings instead of migrating them, and they must be reassigned to horizontal or vertical grow/shrink actions.

Do not infer monitor UUIDs from pre-0.5.9 numeric display IDs. After upgrading, use **Settings → Monitors → Run Monitor Setup…**, then re-save per-monitor Workspace Bar, orientation, Niri, Dwindle, and gap overrides and any specifically assigned workspace. This avoids silently attaching a rule to the wrong physical display.

## Use hotkeys only as a fallback

Hotkeys are an alternative within explicitly approved foreground work, the active remote-work authorization, or explicitly requested window-management work. They are never a way around the applicable foreground authorization boundary.

Hotkeys are user-configurable and can drift. Re-read the `[[hotkeys]]` entries in `~/.config/omniwm/settings.toml` before sending one through Computer Use. Match the desired current action ID to its configured `binding`; ignore entries whose binding is `Unassigned`.

Computer Use key syntax names Option as `alt`, for example `alt+Right` or `alt+shift+equal`. Prefer the equivalent CLI command because it is explicit, verifiable, and independent of the active keyboard focus.
