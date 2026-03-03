#!/usr/bin/env bash
set -euo pipefail

TMUX_SERVER="${AGTX_UI_TMUX_SERVER:-agtx-ui}"
SESSION_NAME="${AGTX_UI_SESSION:-agtx-main}"
PROJECT_DIR="${AGTX_PROJECT_DIR:-$HOME}"
AGTX_COMMAND="${AGTX_COMMAND:-agtx}"
ATTACH_AFTER_START=1
RESPAWN="${AGTX_RESPAWN:-1}"
RESPAWN_DELAY="${AGTX_RESPAWN_DELAY:-3}"

# First arg is the command (if it doesn't start with --)
COMMAND=""
if (($# > 0)) && [[ "$1" != --* ]]; then
  COMMAND="$1"
  shift
fi

log() {
  printf '\033[1;34m[agtx]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[agtx]\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31m[agtx]\033[0m %s\n' "$*" >&2
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
      --project-dir)
        [[ $# -ge 2 ]] || die "Missing value for --project-dir"
        PROJECT_DIR="$2"
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
      --agtx-command)
        [[ $# -ge 2 ]] || die "Missing value for --agtx-command"
        AGTX_COMMAND="$2"
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
Usage: agtx-session [command] [options]

Run with no arguments for interactive menu.

Commands:
  start      Start agtx in a persistent tmux session
  attach     Attach to running session
  restart    Restart the session
  stop       Stop the session
  status     Show session status
  logs       Show last 100 lines of session output
  help       Show this help

Options:
  --project-dir <path>   Project directory (default: $HOME)
  --no-attach            Don't auto-attach after start
  --no-respawn           Don't auto-restart agtx if it exits
  -h, --help             Show this help

The session runs on a dedicated tmux server and survives SSH disconnects.
Just close your terminal — agtx keeps running. Reconnect and attach anytime.
EOF
}

# ── Core actions ─────────────────────────────────────────────

attach_session() {
  if ! session_exists; then
    die "No session running. Use 'agtx-session start' first."
  fi
  log "Attaching to session (detach: Ctrl-b then d)"
  exec tmux -L "${TMUX_SERVER}" attach -t "${SESSION_NAME}"
}

start_session() {
  have_cmd tmux || die "tmux is not installed."
  local command_bin="${AGTX_COMMAND%% *}"
  have_cmd "${command_bin}" || die "${command_bin} not found on PATH."
  [[ -d "${PROJECT_DIR}" ]] || die "Project dir does not exist: ${PROJECT_DIR}"

  if session_exists; then
    log "Session already running (uptime: $(session_uptime))"
  else
    # Build the command that runs inside the tmux pane
    local inner_cmd
    if [[ "${RESPAWN}" -eq 1 ]]; then
      # Respawn loop: if agtx exits, wait a few seconds and restart
      inner_cmd="while true; do ${AGTX_COMMAND}; rc=\$?; echo; echo \"[agtx-session] agtx exited (code \$rc). Restarting in ${RESPAWN_DELAY}s... (Ctrl-C to stop)\"; sleep ${RESPAWN_DELAY}; done"
    else
      inner_cmd="${AGTX_COMMAND}"
    fi

    log "Starting session in ${PROJECT_DIR}"
    tmux_cmd new-session -d -s "${SESSION_NAME}" -c "${PROJECT_DIR}" bash -c "${inner_cmd}"
    harden_server
    log "Session started (server: ${TMUX_SERVER}, session: ${SESSION_NAME})"
  fi

  if [[ "${ATTACH_AFTER_START}" -eq 1 ]]; then
    attach_session
  else
    log "Running detached. Attach with: agtx-session attach"
  fi
}

stop_session() {
  if ! session_exists; then
    log "No session running."
    return
  fi
  tmux_cmd kill-session -t "${SESSION_NAME}"
  log "Session stopped."
}

restart_session() {
  stop_session
  start_session
}

show_status() {
  echo
  if session_exists; then
    local uptime
    uptime=$(session_uptime)
    log "Status: RUNNING"
    log "Uptime: ${uptime}"
    log "Server: ${TMUX_SERVER}"
    log "Session: ${SESSION_NAME}"
    echo
    tmux_cmd list-windows -t "${SESSION_NAME}" \
      -F '  window ##{window_index}: #{window_name} #{?window_active,(active),}' 2>/dev/null || true
  else
    log "Status: STOPPED"
  fi

  if tmux -L agtx list-sessions >/dev/null 2>&1; then
    echo
    log "Agent sub-sessions (tmux -L agtx):"
    tmux -L agtx list-sessions -F '  #{session_name} (#{session_windows} windows)' || true
  fi
  echo
}

show_logs() {
  if ! session_exists; then
    die "No session running."
  fi
  tmux_cmd capture-pane -t "${SESSION_NAME}" -p -S -100
}

# ── Interactive menu ─────────────────────────────────────────

interactive_menu() {
  local running=false
  session_exists && running=true

  echo
  echo "  ┌─────────────────────────────┐"
  echo "  │     agtx session manager    │"
  echo "  └─────────────────────────────┘"
  echo

  if $running; then
    log "Session is RUNNING (uptime: $(session_uptime))"
  else
    log "Session is STOPPED"
  fi
  echo

  # Build menu options based on state
  local options=()
  if $running; then
    options+=("attach:Attach to session")
    options+=("logs:View recent output")
    options+=("restart:Restart session")
    options+=("stop:Stop session")
    options+=("status:Detailed status")
  else
    options+=("start:Start session")
    options+=("start-bg:Start (detached, no attach)")
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

  # No command given and stdin is a terminal → interactive menu
  if [[ -z "${COMMAND}" ]]; then
    if [[ -t 0 ]]; then
      interactive_menu
      exit 0
    else
      die "No command given. Run 'agtx-session help'."
    fi
  fi

  case "${COMMAND}" in
    start|up)       start_session ;;
    attach|a)       attach_session ;;
    restart)        restart_session ;;
    stop|down)      stop_session ;;
    status|st)      show_status ;;
    logs|log)       show_logs ;;
    list|ls)        tmux_cmd list-sessions 2>/dev/null || log "No sessions." ;;
    help|-h|--help) usage ;;
    *)              die "Unknown command: ${COMMAND}. Run 'agtx-session help'." ;;
  esac
}

main "$@"
