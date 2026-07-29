# Complete setup

This setup makes the OmniWM focus-protection workflow available to every Codex task on a Mac. It installs the skill, enables OmniWM IPC, and adds a global agent rule that covers browser automation, app launches, app testing, and Computer Use.

## Prerequisites

- macOS with OmniWM installed in `/Applications/OmniWM.app`
- OmniWM 0.5.9 or a later version that supports the documented CLI commands
- Codex
- `jq`
- Python 3.11 or later

Keep the app and its bundled `omniwmctl` together. The IPC protocol is version-coupled; do not substitute an older standalone CLI.

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

Focus an OmniWM-managed window, then run:

```bash
./scripts/verify-setup.sh
```

The verifier checks:

- the installed skill link and global rule;
- valid TOML with IPC enabled;
- the bundled CLI, live IPC ping, and protocol version;
- `jq` and Python/TOML support;
- a real `capture`, `status`, and `restore` cycle without moving or resizing a window.

For an explicit guard test, use a short TTL:

```bash
guard_json=$(./scripts/focus-guard.sh guard --ttl 5)
guard_token=$(jq -r '.token' <<<"$guard_json")
./scripts/focus-guard.sh status "$guard_token"
./scripts/focus-guard.sh restore "$guard_token"
```

## How agents should use it

- Prefer headless, in-app, or non-activating automation.
- Guard one background-capable tool call, then restore immediately.
- Capture immediately before one foreground-only action, then restore immediately.
- Re-capture before later actions so the user's current choice is respected.
- Diff window IDs before and after launches. Contain only fresh agent-created windows.
- Never move, resize, scratchpad, close, or reassign a pre-existing user window for automation convenience.

The guard responds to OmniWM focus events and retains polling as a fallback. Its TTL prevents an abandoned guard from indefinitely fighting user input.

## Troubleshooting

If `omniwmctl ping` reports connection refused:

1. Confirm OmniWM is running.
2. Confirm `[general]` contains `ipcEnabled = true`.
3. Confirm the bundled CLI is executable.
4. Restart OmniWM if live reload did not enable IPC.

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
