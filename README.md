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
# Interactive menu (just run with no args):
agtx-session

# Or use commands directly:
agtx-session start --project-dir /srv/your-project
agtx-session status
agtx-session logs
agtx-session attach
```

### Survives SSH disconnects

The session runs on a dedicated tmux server (`agtx-ui`) with `destroy-unattached off`.
Close your SSH connection, go away, come back — agtx keeps running.

```bash
agtx-session start --project-dir ~/my-project
# detach: Ctrl+b then d
# close SSH, come back later...
agtx-session attach   # pick up where you left off
```

### Auto-respawn

If agtx crashes or exits, the session automatically restarts it after 3 seconds.
Disable with `--no-respawn`.

### Commands

| Command   | Description                              |
|-----------|------------------------------------------|
| `start`   | Start agtx in a persistent tmux session  |
| `attach`  | Attach to a running session              |
| `restart` | Restart the session                      |
| `stop`    | Stop the session                         |
| `status`  | Show session status and uptime           |
| `logs`    | Show last 100 lines of session output    |
| `help`    | Show help                                |

### Options

| Option              | Description                                |
|---------------------|--------------------------------------------|
| `--project-dir`     | Project directory (default: `$HOME`)       |
| `--no-attach`       | Start without auto-attaching               |
| `--no-respawn`      | Don't auto-restart agtx if it exits        |
| `--session <name>`  | tmux session name (default: `agtx-main`)   |
| `--server <name>`   | tmux server name (default: `agtx-ui`)      |

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
