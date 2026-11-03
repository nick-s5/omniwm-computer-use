# Complete setup

This setup makes the OmniWM focus-protection workflow available to every Codex task on a Mac. It installs the skill, enables OmniWM IPC, and adds a global agent rule that covers browser automation, app launches, app testing, and Computer Use.

## Prerequisites

- macOS with OmniWM installed in `/Applications/OmniWM.app`
- OmniWM 0.6.1 / IPC protocol 10 or OmniWM 0.7.6 / IPC protocol 19 with the documented CLI commands
- Codex
- `jq`
- Python 3.11 or later

Keep the app and its bundled `omniwmctl` together. The IPC protocol is version-coupled; do not substitute an older standalone CLI.

OmniWM 0.6.1 changed Dwindle CLI resizing from directions to axes. Update the app and CLI together, rebuild third-party IPC clients, replace `resize left|right` with `resize horizontal`, and replace `resize up|down` with `resize vertical`. Custom directional Dwindle resize hotkeys are dropped during the upgrade and must be reassigned in **Settings → Hotkeys → Show Advanced**.

## Install

Clone the skill, enter its directory, review the pending actions, and install:

```bash
git clone https://github.com/nick-s5/omniwm-computer-use.git
cd omniwm-computer-use
./scripts/install.sh --dry-run
./scripts/install.sh
```

The installer is idempotent. It:

1. Links the clone into `$CODEX_HOME/skills/omniwm-computer-use`, or `~/.codex/skills/omniwm-computer-use` when `CODEX_HOME` is unset. A clone already located at that path is used directly.
2. Sets `general.ipcEnabled = true` in `~/.config/omniwm/settings.toml`.
3. Adds a marked `macOS window-focus safety` block to `$CODEX_HOME/AGENTS.md`, or `~/.codex/AGENTS.md` when `CODEX_HOME` is unset.
4. Uses the standard installed-skill path in that global rule instead of the clone's original location.
5. Runs the full verifier when OmniWM is active.

Existing files are preserved. The installer refuses to overwrite a different skill at the target path and creates timestamped backups before changing OmniWM settings or `AGENTS.md`.

Use environment overrides when the defaults are not appropriate:

```bash
CODEX_HOME=/custom/codex \
OMNIWM_SETTINGS=/custom/omniwm/settings.toml \
./scripts/install.sh
```

Start a new Codex task after installation. Tasks that were already running may have loaded the old global instructions.

## Verify

With an OmniWM-managed window focused, run the read-only verifier:

```bash
./scripts/verify-setup.sh
```

The verifier checks:

- the installed skill link and global rule;
- valid TOML with IPC enabled;
- the bundled CLI, live IPC ping, supported protocols 10 and 19, and the capabilities response schema;
- `jq` and Python/TOML support;
- the focused-window and window-inventory schemas without changing focus.

Only with foreground authorization, `./scripts/verify-setup.sh --check-restore` also runs a real `capture`, `status`, and `restore` cycle. Restoration may refocus the captured window; use it when that focus action is allowed.

For an explicit guard test, use a short TTL:

```bash
guard_json=$(./scripts/focus-guard.sh guard --ttl 5 \
  --expect-bundle-id com.google.Chrome)
guard_token=$(jq -r '.token' <<<"$guard_json")
./scripts/focus-guard.sh status "$guard_token"
./scripts/focus-guard.sh restore "$guard_token"
```

## How agents should use it

- Prefer headless, in-app, or non-activating automation.
- Guard one background-capable tool call with the expected bundle ID or app name when known, then clean up immediately.
- Capture immediately before one foreground-only action, then restore immediately.
- Re-capture before later actions so the user's current choice is respected.
- Diff window IDs before and after launches. Contain only fresh agent-created windows.
- Never move, resize, scratchpad, close, or reassign a pre-existing user window for automation convenience.

The guard responds to OmniWM focus events and retains polling as a fallback. It restores an expected automation app once and immediately disarms. An unrelated pre-existing window is treated as user intent, so the guard yields without changing focus. Cleanup does not refocus after a background guard.

## Troubleshooting

If `omniwmctl ping` reports connection refused:

1. Confirm OmniWM is running.
2. Confirm `[general]` contains `ipcEnabled = true`.
3. Confirm the bundled CLI is executable.
4. Restart OmniWM if live reload did not enable IPC.

If verification reports an incompatible protocol, upgrade OmniWM and its bundled `omniwmctl` together. Do not copy an older CLI into place or bypass the protocol handshake.

If capture reports no focused managed window, focus a normal OmniWM-managed app window and retry. OmniWM does not return unmanaged windows through `query focused-window`.

If the skill target already exists, inspect it before changing anything:

```bash
ls -ld "${CODEX_HOME:-$HOME/.codex}/skills/omniwm-computer-use"
```

The installer deliberately will not replace a different file, directory, or symlink.

## Roll back

Remove only the installer-managed skill link:

```bash
skill_link="${CODEX_HOME:-$HOME/.codex}/skills/omniwm-computer-use"
[[ -L "$skill_link" ]] && unlink "$skill_link"
```

Remove the block between these markers from `$CODEX_HOME/AGENTS.md`, or `~/.codex/AGENTS.md` when `CODEX_HOME` is unset:

```text
<!-- omniwm-computer-use:begin -->
<!-- omniwm-computer-use:end -->
```

Restore a timestamped backup if the previous OmniWM or global agent configuration is needed. IPC may also be disabled manually by setting `general.ipcEnabled = false`, but the focus guard cannot operate while IPC is disabled.

## Limitation

Focus restoration cannot guarantee that a newly created macOS window is never rendered for a frame. Headless or explicitly non-activating automation gives the strongest protection. Use a separately identifiable automation app/profile or a dedicated OmniWM workspace when new windows must remain open; do not apply broad rules to a user's existing Chrome windows.

A virtual display can keep automation windows off a shared physical monitor, but it does not isolate the system-wide active macOS application and therefore does not solve focus stealing by itself. Use a separate macOS login session or virtual machine only when hard GUI isolation is required.
