# OmniWM Computer Use

A Codex skill for protecting the user's active macOS window and layout while agents run browser automation, launch and test apps, or use Computer Use with [OmniWM](https://github.com/BarutSRB/OmniWM).

The skill coordinates GUI work through OmniWM's bundled `omniwmctl`. It can target exact windows across workspaces and displays, and its short-lived focus guard restores the window the user was working in when Chrome or another automated app tries to become active.

## What it provides

- Event-driven focus protection with a polling fallback and automatic TTL.
- Capture and immediate restoration around foreground-only actions.
- Exact window selection by bundle ID, app name, and title.
- Multi-display and Niri scrolling-workspace coordination.
- Stable-frame and visible-frame verification before coordinate actions.
- An idempotent installer for skill registration, OmniWM IPC, and a global Codex rule.
- A live verifier for the complete setup.

## Requirements

- macOS with OmniWM 0.5.9 or a compatible later version
- Codex
- `jq`
- Python 3.11 or later

Use the `omniwmctl` bundled with the installed OmniWM app. The app and CLI IPC protocols must remain compatible.

## Install

```bash
git clone https://github.com/nick-s5/omniwm-computer-use.git
cd omniwm-computer-use
./scripts/install.sh --dry-run
./scripts/install.sh
```

Start a new Codex task after installation so it loads the global rule and skill catalog.

See [Complete setup](references/setup.md) for prerequisites, environment overrides, verification, troubleshooting, rollback, and behavioral limitations.

## Verify

Focus an OmniWM-managed app window, then run:

```bash
./scripts/verify-setup.sh
```

The verifier checks the installed skill, global agent rule, TOML configuration, live IPC connection, and a real capture/status/restore cycle.

## Repository layout

```text
.
├── SKILL.md
├── agents/
│   └── openai.yaml
├── references/
│   └── setup.md
└── scripts/
    ├── focus-guard.sh
    ├── focus-window.sh
    ├── install.sh
    └── verify-setup.sh
```

The repository root is the skill root. This allows the clone to be linked directly into `${CODEX_HOME:-$HOME/.codex}/skills/omniwm-computer-use`.
