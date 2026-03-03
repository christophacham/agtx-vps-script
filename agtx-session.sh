#!/usr/bin/env bash
set -euo pipefail

TMUX_SERVER="${AGTX_UI_TMUX_SERVER:-agtx-ui}"
SESSION_NAME="${AGTX_UI_SESSION:-agtx-main}"
PROJECT_DIR="${AGTX_PROJECT_DIR:-$PWD}"
AGTX_COMMAND="${AGTX_COMMAND:-agtx}"
ATTACH_AFTER_START=1

COMMAND="${1:-start}"
if (($# > 0)); then
  shift
fi

log() {
  printf '[agtx-session] %s\n' "$*"
}

die() {
  printf '[agtx-session][error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  agtx-session [command] [options]

Commands:
  start      Start agtx in a detached tmux session (default command)
  attach     Attach to the existing agtx tmux session
  restart    Restart the agtx tmux session
  stop       Stop (kill) the agtx tmux session
  status     Show status and tmux window info
  list       List sessions in this tmux server
  help       Show this help

Options:
  --project-dir <path>   Project directory to run agtx in (default: current dir)
  --session <name>       tmux session name (default: agtx-main)
  --server <name>        tmux server name (default: agtx-ui)
  --agtx-command <cmd>   Command to run inside session (default: agtx)
  --no-attach            Start/restart without auto-attaching
  -h, --help             Show this help

Examples:
  agtx-session start --project-dir ~/code/my-project
  agtx-session attach
  agtx-session status
  agtx-session restart --no-attach
EOF
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

attach_session() {
  if ! session_exists; then
    die "Session '${SESSION_NAME}' not found on tmux server '${TMUX_SERVER}'. Run: agtx-session start"
  fi

  log "Attaching to ${TMUX_SERVER}:${SESSION_NAME}"
  exec tmux -L "${TMUX_SERVER}" attach -t "${SESSION_NAME}"
}

start_session() {
  local command_bin
  have_cmd tmux || die "tmux is not installed."
  command_bin="${AGTX_COMMAND%% *}"
  have_cmd "${command_bin}" || die "${command_bin} is not installed or not on PATH."
  [[ -d "${PROJECT_DIR}" ]] || die "Project directory does not exist: ${PROJECT_DIR}"

  if session_exists; then
    log "Session already running: ${TMUX_SERVER}:${SESSION_NAME}"
  else
    log "Starting session ${TMUX_SERVER}:${SESSION_NAME} in ${PROJECT_DIR}"
    tmux_cmd new-session -d -s "${SESSION_NAME}" -c "${PROJECT_DIR}" "${AGTX_COMMAND}"
  fi

  if [[ "${ATTACH_AFTER_START}" -eq 1 ]]; then
    attach_session
  fi
}

stop_session() {
  if ! session_exists; then
    log "Session already stopped: ${TMUX_SERVER}:${SESSION_NAME}"
    return
  fi

  tmux_cmd kill-session -t "${SESSION_NAME}"
  log "Stopped session ${TMUX_SERVER}:${SESSION_NAME}"
}

status_session() {
  if session_exists; then
    log "Session is running: ${TMUX_SERVER}:${SESSION_NAME}"
    tmux_cmd list-sessions -F '#{session_name} created=#{session_created} windows=#{session_windows}' \
      | grep -E "^${SESSION_NAME} " || true
    tmux_cmd list-windows -t "${SESSION_NAME}" -F '  window=#{window_index} name=#{window_name} active=#{window_active}'
  else
    log "Session is not running: ${TMUX_SERVER}:${SESSION_NAME}"
  fi

  if tmux -L agtx list-sessions >/dev/null 2>&1; then
    log "agtx internal agent server has active sessions (tmux -L agtx):"
    tmux -L agtx list-sessions -F '  #{session_name} windows=#{session_windows}' || true
  fi
}

list_sessions() {
  if tmux_cmd list-sessions >/dev/null 2>&1; then
    tmux_cmd list-sessions -F '#{session_name} windows=#{session_windows} attached=#{session_attached}'
  else
    log "No sessions found on tmux server '${TMUX_SERVER}'."
  fi
}

restart_session() {
  stop_session
  start_session
}

main() {
  parse_args "$@"

  case "${COMMAND}" in
    start|up)
      start_session
      ;;
    attach|a)
      attach_session
      ;;
    restart)
      restart_session
      ;;
    stop|down)
      stop_session
      ;;
    status)
      status_session
      ;;
    list)
      list_sessions
      ;;
    help)
      usage
      ;;
    *)
      die "Unknown command: ${COMMAND}. Run 'agtx-session help'."
      ;;
  esac
}

main "$@"
