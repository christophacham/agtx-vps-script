# agtx-vps-scripts

Two Bash scripts to run AGTX on a Fedora VPS with persistent tmux sessions.

## Scripts

- `setup-agtx-vps.sh`: installs `agtx`, installs `get-shit-done`, writes AGTX config/plugin.
- `agtx-session.sh`: start/attach/restart/stop/status for a persistent AGTX tmux UI session.

## Quick Start

```bash
bash setup-agtx-vps.sh --project-dir /srv/your-project --gsd-runtimes codex,claude
source ~/.bashrc
```

## Run AGTX

```bash
agtx-session start --project-dir /srv/your-project
# detach (keep running): Ctrl+b then d
agtx-session attach
agtx-session status
```

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
