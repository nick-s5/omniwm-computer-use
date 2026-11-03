# OmniWM Computer Use

A Codex skill for protecting the user's active macOS window and layout while agents run browser automation, launch and test apps, or use Computer Use with [OmniWM](https://github.com/BarutSRB/OmniWM).

The skill coordinates GUI work through OmniWM's bundled `omniwmctl`. It can target exact windows across workspaces and displays, and its one-shot focus guard restores the window the user was working in when an expected automation window tries to become active—without locking the user into that window afterward.

## What it provides

- One-shot, target-aware focus protection with event and polling inputs.
- Immediate yielding when the user selects an unrelated existing window.
- Capture and immediate restoration around foreground-only actions.
- Exact window selection by bundle ID, app name, and title.
- Multi-display and Niri scrolling-workspace coordination.
- Stable-frame and visible-frame verification before coordinate actions.
- An idempotent installer for skill registration, OmniWM IPC, and a global Codex rule.
- A live verifier for the complete setup.

## Requirements

- macOS with OmniWM IPC protocol 10 or 19
- Codex
- `jq`
- Python 3.11 or later

Use the `omniwmctl` bundled with the installed OmniWM app. The app and CLI IPC protocols must remain compatible.

The skill supports OmniWM 0.6.1 / IPC protocol 10 (the prior contract, covered by fixture tests) and 0.7.6 / IPC protocol 19 (checked against the live app). In particular,
Dwindle CLI resizing is axis-based: use `resize horizontal|vertical`, not the
removed `resize left|right|up|down` form.

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

With an OmniWM-managed app window focused, run the read-only verifier:

```bash
./scripts/verify-setup.sh
```

The verifier checks the installed skill, global agent rule, TOML configuration, live IPC connection, capabilities, and focus/window query schemas without changing focus. If foreground interaction is authorized and a capture/status/restore cycle is needed, run `./scripts/verify-setup.sh --check-restore`; this may restore focus to the captured window.

Run the deterministic focus-policy regression tests with:

```bash
./tests/focus-guard-test.sh
./tests/verify-setup-test.sh
```

## Repository layout

```text
.
├── SKILL.md
├── agents/
│   └── openai.yaml
├── references/
│   └── setup.md
├── scripts/
    ├── focus-guard.sh
    ├── focus-window.sh
    ├── install.sh
    └── verify-setup.sh
└── tests/
    ├── fake-omniwmctl.sh
    ├── focus-guard-test.sh
    └── verify-setup-test.sh
```

The repository root is the skill root. This allows the clone to be linked directly into `${CODEX_HOME:-$HOME/.codex}/skills/omniwm-computer-use`.
