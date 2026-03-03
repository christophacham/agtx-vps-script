# agtx-vps-scripts

Scripts to run AI coding agents (AGTX, Claude Code, Codex) on a VPS with persistent tmux sessions that survive SSH disconnects.

Upstream:
- AGTX: https://github.com/fynnfluegge/agtx
- Get Shit Done (GSD): https://github.com/glittercowboy/get-shit-done

## Scripts

- `setup-agtx-vps.sh`: installs `agtx`, installs `get-shit-done`, writes AGTX config/plugin.
- `persist.sh`: generic persistent session manager — run any TUI command (agtx, claude, codex) in a tmux session that survives SSH disconnects.

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

## persist — persistent session manager

Run any command in a tmux session that survives SSH disconnects, with auto-respawn.

```bash
# Install
cp persist.sh ~/.local/bin/persist && chmod +x ~/.local/bin/persist

# Run agtx
persist start --run agtx --dir ~/my-project

# Run Claude Code
persist start --run claude --dir ~/my-project --session claude-1

# Run Codex
persist start --run codex --dir ~/my-project --session codex-1

# Run multiple agents simultaneously
persist start --run claude --dir ~/project --session claude-1 --no-attach
persist start --run codex --dir ~/project --session codex-1 --no-attach
persist list

# Interactive menu
persist
```

### Survives SSH disconnects

Sessions run on a dedicated tmux server with `destroy-unattached off`. Close your SSH connection, come back later, attach.

```bash
persist start --run agtx --dir ~/my-project
# detach: Ctrl+b then d
# close SSH, come back later...
persist attach   # pick up where you left off
```

### Auto-respawn

If the command crashes or exits, the session restarts it after 3 seconds. Disable with `--no-respawn`.

### Commands

| Command   | Description                              |
|-----------|------------------------------------------|
| `start`   | Start a command in a persistent session  |
| `attach`  | Attach to a running session              |
| `restart` | Restart the session                      |
| `stop`    | Stop the session                         |
| `status`  | Show session status and uptime           |
| `logs`    | Show last 100 lines of session output    |
| `list`    | List all sessions                        |
| `help`    | Show help                                |

### Options

| Option              | Description                                |
|---------------------|--------------------------------------------|
| `--run <cmd>`       | Command to run (required for start)        |
| `--dir <path>`      | Working directory (default: `$HOME`)       |
| `--session <name>`  | Session name (default: `main`)             |
| `--server <name>`   | tmux server name (default: `persist`)      |
| `--no-attach`       | Start without auto-attaching               |
| `--no-respawn`      | Don't auto-restart on exit                 |

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
