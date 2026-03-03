#!/usr/bin/env bash
set -euo pipefail

TMUX_SERVER="${PERSIST_TMUX_SERVER:-persist}"
SESSION_NAME="${PERSIST_SESSION:-main}"
PROJECT_DIR="${PERSIST_PROJECT_DIR:-$HOME}"
RUN_COMMAND="${PERSIST_COMMAND:-}"
ATTACH_AFTER_START=1
RESPAWN="${PERSIST_RESPAWN:-1}"
RESPAWN_DELAY="${PERSIST_RESPAWN_DELAY:-3}"

# First arg is the command if it doesn't start with --
COMMAND=""
if (($# > 0)) && [[ "$1" != --* ]]; then
  COMMAND="$1"
  shift
fi

log() {
  printf '\033[1;34m[persist]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[persist]\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31m[persist]\033[0m %s\n' "$*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

tmux_cmd() {
  tmux -L "${TMUX_SERVER}" "$@"
}

session_exists() {
  tmux_cmd has-session -t "${SESSION_NAME}" >/dev/null 2>&1
}

# Harden the tmux server so sessions survive SSH disconnect
harden_server() {
  tmux_cmd set-option -g destroy-unattached off 2>/dev/null || true
  tmux_cmd set-option -g exit-unattached off 2>/dev/null || true
  tmux_cmd set-option -g detach-on-destroy on 2>/dev/null || true
}

session_uptime() {
  if ! session_exists; then
    echo "not running"
    return
  fi
  local created
  created=$(tmux_cmd display -p -t "${SESSION_NAME}" '#{session_created}' 2>/dev/null) || { echo "?"; return; }
  local now elapsed h m s
  now=$(date +%s)
  elapsed=$((now - created))
  h=$((elapsed / 3600))
  m=$(( (elapsed % 3600) / 60 ))
  s=$((elapsed % 60))
  printf '%dh %dm %ds' "$h" "$m" "$s"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --dir)
        [[ $# -ge 2 ]] || die "Missing value for --dir"
        PROJECT_DIR="$2"
        shift 2
        ;;
      --run)
        [[ $# -ge 2 ]] || die "Missing value for --run"
        RUN_COMMAND="$2"
        shift 2
        ;;
      --session)
        [[ $# -ge 2 ]] || die "Missing value for --session"
        SESSION_NAME="$2"
        shift 2
        ;;
      --server)
        [[ $# -ge 2 ]] || die "Missing value for --server"
        TMUX_SERVER="$2"
        shift 2
        ;;
      --no-attach)
        ATTACH_AFTER_START=0
        shift
        ;;
      --no-respawn)
        RESPAWN=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

usage() {
  cat <<'EOF'
Usage: persist [command] [options]

Run with no arguments for interactive menu.

Commands:
  start      Start a command in a persistent tmux session
  attach     Attach to running session
  restart    Restart the session
  stop       Stop the session
  status     Show session status
  logs       Show last 100 lines of session output
  list       List all sessions
  help       Show this help

Options:
  --run <cmd>            Command to run (required for start)
  --dir <path>           Working directory (default: $HOME)
  --session <name>       Session name (default: main)
  --server <name>        tmux server name (default: persist)
  --no-attach            Don't auto-attach after start
  --no-respawn           Don't auto-restart on exit
  -h, --help             Show this help

Examples:
  persist start --run agtx --dir ~/my-project
  persist start --run claude --dir ~/my-project --session claude-1
  persist start --run codex --dir ~/my-project --session codex-1
  persist attach --session claude-1
  persist list
  persist                # interactive menu

Environment variables:
  PERSIST_COMMAND        Default command to run
  PERSIST_PROJECT_DIR    Default working directory
  PERSIST_SESSION        Default session name
  PERSIST_TMUX_SERVER    Default tmux server name
  PERSIST_RESPAWN        Auto-respawn on exit (1=on, 0=off, default: 1)
  PERSIST_RESPAWN_DELAY  Seconds between respawns (default: 3)

Sessions survive SSH disconnects. Close your terminal, come back, attach.
EOF
}

# ── Core actions ─────────────────────────────────────────────

attach_session() {
  if ! session_exists; then
    die "No session '${SESSION_NAME}' running. Use 'persist start' first."
  fi
  log "Attaching to '${SESSION_NAME}' (detach: Ctrl-b then d)"
  exec tmux -L "${TMUX_SERVER}" attach -t "${SESSION_NAME}"
}

start_session() {
  have_cmd tmux || die "tmux is not installed."
  [[ -n "${RUN_COMMAND}" ]] || die "No command specified. Use --run <cmd>."
  local command_bin="${RUN_COMMAND%% *}"
  have_cmd "${command_bin}" || die "'${command_bin}' not found on PATH."
  [[ -d "${PROJECT_DIR}" ]] || die "Directory does not exist: ${PROJECT_DIR}"

  if session_exists; then
    log "Session '${SESSION_NAME}' already running (uptime: $(session_uptime))"
  else
    local inner_cmd
    if [[ "${RESPAWN}" -eq 1 ]]; then
      inner_cmd="while true; do ${RUN_COMMAND}; rc=\$?; echo; echo \"[persist] exited (code \$rc). Restarting in ${RESPAWN_DELAY}s... (Ctrl-C to stop)\"; sleep ${RESPAWN_DELAY}; done"
    else
      inner_cmd="${RUN_COMMAND}"
    fi

    log "Starting '${SESSION_NAME}': ${RUN_COMMAND} in ${PROJECT_DIR}"
    tmux_cmd new-session -d -s "${SESSION_NAME}" -c "${PROJECT_DIR}" bash -c "${inner_cmd}"
    harden_server
    log "Session started on server '${TMUX_SERVER}'"
  fi

  if [[ "${ATTACH_AFTER_START}" -eq 1 ]]; then
    attach_session
  else
    log "Running detached. Attach with: persist attach --session ${SESSION_NAME}"
  fi
}

stop_session() {
  if ! session_exists; then
    log "No session '${SESSION_NAME}' running."
    return
  fi
  tmux_cmd kill-session -t "${SESSION_NAME}"
  log "Session '${SESSION_NAME}' stopped."
}

restart_session() {
  stop_session
  start_session
}

show_status() {
  echo
  if session_exists; then
    log "Session: ${SESSION_NAME}"
    log "Status:  RUNNING"
    log "Uptime:  $(session_uptime)"
    log "Server:  ${TMUX_SERVER}"
    echo
    tmux_cmd list-windows -t "${SESSION_NAME}" \
      -F '  window ##{window_index}: #{window_name} #{?window_active,(active),}' 2>/dev/null || true
  else
    log "Session '${SESSION_NAME}': STOPPED"
  fi
  echo
}

show_all() {
  echo
  if tmux_cmd list-sessions >/dev/null 2>&1; then
    log "Sessions on server '${TMUX_SERVER}':"
    tmux_cmd list-sessions -F '  #{session_name}  windows=#{session_windows}  attached=#{?session_attached,yes,no}' || true
  else
    log "No sessions on server '${TMUX_SERVER}'."
  fi
  echo
}

show_logs() {
  if ! session_exists; then
    die "No session '${SESSION_NAME}' running."
  fi
  tmux_cmd capture-pane -t "${SESSION_NAME}" -p -S -100
}

# ── Interactive menu ─────────────────────────────────────────

interactive_menu() {
  local running=false
  session_exists && running=true

  echo
  echo "  ┌───────────────────────┐"
  echo "  │       persist         │"
  echo "  └───────────────────────┘"
  echo

  if $running; then
    log "Session '${SESSION_NAME}' is RUNNING (uptime: $(session_uptime))"
  else
    log "Session '${SESSION_NAME}' is STOPPED"
  fi

  # Show all sessions if any exist
  if tmux_cmd list-sessions >/dev/null 2>&1; then
    echo
    log "All sessions:"
    tmux_cmd list-sessions -F '  #{session_name}  #{?session_attached,attached,detached}' || true
  fi
  echo

  local options=()
  if $running; then
    options+=("attach:Attach to '${SESSION_NAME}'")
    options+=("logs:View recent output")
    options+=("restart:Restart session")
    options+=("stop:Stop session")
    options+=("status:Detailed status")
  else
    options+=("start:Start session")
    options+=("start-bg:Start (detached)")
  fi

  local i=1
  for opt in "${options[@]}"; do
    local label="${opt#*:}"
    printf '  \033[1;36m%d)\033[0m %s\n' "$i" "$label"
    ((i++))
  done
  echo
  printf '  \033[2mq) Quit\033[0m\n'
  echo

  local choice
  read -rp "  Pick an option: " choice

  case "$choice" in
    q|Q|"")
      exit 0
      ;;
    [0-9]*)
      if ((choice >= 1 && choice <= ${#options[@]})); then
        local picked="${options[$((choice - 1))]}"
        local cmd="${picked%%:*}"
        echo
        case "$cmd" in
          attach)      attach_session ;;
          logs)        show_logs ;;
          restart)     restart_session ;;
          stop)        stop_session ;;
          status)      show_status ;;
          start)       start_session ;;
          start-bg)    ATTACH_AFTER_START=0; start_session ;;
        esac
      else
        die "Invalid choice."
      fi
      ;;
    *)
      die "Invalid choice."
      ;;
  esac
}

# ── Main ─────────────────────────────────────────────────────

main() {
  parse_args "$@"

  # No command → interactive menu (if terminal)
  if [[ -z "${COMMAND}" ]]; then
    if [[ -t 0 ]]; then
      interactive_menu
      exit 0
    else
      die "No command given. Run 'persist help'."
    fi
  fi

  case "${COMMAND}" in
    start|up)       start_session ;;
    attach|a)       attach_session ;;
    restart)        restart_session ;;
    stop|down)      stop_session ;;
    status|st)      show_status ;;
    logs|log)       show_logs ;;
    list|ls)        show_all ;;
    help|-h|--help) usage ;;
    *)              die "Unknown command: ${COMMAND}. Run 'persist help'." ;;
  esac
}

main "$@"
