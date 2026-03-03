# agtx-vps-scripts

Two Bash scripts to run AGTX on a Fedora VPS with persistent tmux sessions.

## Scripts

- `setup-agtx-vps.sh`: installs `agtx`, installs `get-shit-done`, writes AGTX config/plugin.
- `agtx-session.sh`: start/attach/restart/stop/status for a persistent AGTX tmux UI session.

## Quick Start

```bash
bash setup-agtx-vps.sh --project-dir /srv/your-project --gsd-runtimes codex
agtx-session start --project-dir /srv/your-project
```
