# agtx-vps-scripts

Two Bash scripts to run AGTX on a Fedora VPS with persistent tmux sessions.

Upstream:
- AGTX: https://github.com/fynnfluegge/agtx
- Get Shit Done (GSD): https://github.com/glittercowboy/get-shit-done

## Scripts

- `setup-agtx-vps.sh`: installs `agtx`, installs `get-shit-done`, writes AGTX config/plugin.
- `agtx-session.sh`: start/attach/restart/stop/status for a persistent AGTX tmux UI session.

## Quick Start

```bash
bash setup-agtx-vps.sh --project-dir /srv/your-project --gsd-runtimes codex,claude
source ~/.bashrc
```

That one setup command installs and configures:
- system deps (`tmux`, `git`, `gh`, `nodejs`, etc.) on Fedora if missing
- latest `agtx` binary
- `get-shit-done-cc` for selected runtimes
- AGTX GSD plugin at `~/.config/agtx/plugins/gsd/plugin.toml`
- project plugin selection: `.agtx/config.toml` -> `workflow_plugin = "gsd"`

## Run AGTX

```bash
agtx-session start --project-dir /srv/your-project
# detach (keep running): Ctrl+b then d
agtx-session attach
agtx-session status
```

## GSD workflow in AGTX

- GSD is used through AGTX plugin `gsd`.
- In AGTX: create task (`o`), run Research (`R`), then advance with `m`.
- Plugin is cyclic, so from Review use `p` for the next milestone cycle.

## Recommended `codex + claude` setup

Put this in `~/.config/agtx/config.toml`:

```toml
default_agent = "claude"

[agents]
research = "claude"
planning = "claude"
running = "codex"
review = "claude"
```
