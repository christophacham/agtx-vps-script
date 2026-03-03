#!/usr/bin/env bash
set -euo pipefail

AGTX_REPO="fynnfluegge/agtx"
AGTX_API_URL="https://api.github.com/repos/${AGTX_REPO}/releases/latest"
GSD_NPM_PACKAGE="get-shit-done-cc@latest"

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
DEFAULT_AGENT="${DEFAULT_AGENT:-codex}"
GSD_RUNTIMES="${GSD_RUNTIMES:-codex}"
AGTX_VERSION="${AGTX_VERSION:-}"
GSD_LOCAL_REPO="${GSD_LOCAL_REPO:-}"
PROJECT_DIR="${PROJECT_DIR:-}"

SKIP_SYSTEM_PACKAGES=0
SKIP_AGTX=0
SKIP_GSD=0
CONFIGURE_PROJECT=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '[setup] %s\n' "$*"
}

warn() {
  printf '[setup][warn] %s\n' "$*" >&2
}

die() {
  printf '[setup][error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  setup-agtx-vps.sh [options]

Options:
  --project-dir <path>      Configure this project with workflow_plugin = "gsd"
  --default-agent <name>    Agent for generated configs (default: codex)
  --gsd-runtimes <csv>      claude,codex,gemini,opencode,all (default: codex)
  --agtx-version <tag>      Install this agtx release tag (default: latest)
  --install-dir <path>      Binary install directory (default: ~/.local/bin)
  --gsd-local-repo <path>   Install GSD from local repo bin/install.js instead of npm
  --skip-system-packages    Skip dnf package installation checks
  --skip-agtx               Skip agtx install/update
  --skip-gsd                Skip get-shit-done install/update
  --no-project-config       Do not modify .agtx/config.toml in project-dir
  -h, --help                Show this help

Environment overrides:
  INSTALL_DIR, DEFAULT_AGENT, GSD_RUNTIMES, AGTX_VERSION, GSD_LOCAL_REPO, PROJECT_DIR
EOF
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_privileged() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return
  fi
  if ! have_cmd sudo; then
    die "sudo is required for system package installation."
  fi
  if ! sudo -n true 2>/dev/null; then
    die "This script needs passwordless sudo for package installation. Configure sudo -n or run as root."
  fi
  sudo "$@"
}

require_fedora() {
  [[ -r /etc/os-release ]] || die "Cannot detect OS (/etc/os-release missing)."
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "fedora" && ! "${ID_LIKE:-}" =~ (fedora|rhel) ]]; then
    die "This bootstrap script targets Fedora/RHEL-like systems. Detected: ID=${ID:-unknown}"
  fi
}

install_system_packages() {
  local missing=()

  have_cmd curl || missing+=("curl")
  have_cmd tar || missing+=("tar")
  have_cmd git || missing+=("git")
  have_cmd tmux || missing+=("tmux")
  have_cmd gh || missing+=("gh")
  have_cmd node || missing+=("nodejs")

  if ((${#missing[@]} == 0)); then
    log "System package requirements already satisfied."
    return
  fi

  require_fedora
  have_cmd dnf || die "dnf command not found on this system."
  log "Installing missing system packages via dnf: ${missing[*]}"
  run_privileged dnf -y install "${missing[@]}"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64' ;;
    aarch64|arm64) printf 'aarch64' ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

resolve_agtx_version() {
  if [[ -n "${AGTX_VERSION}" ]]; then
    printf '%s' "${AGTX_VERSION}"
    return
  fi

  local version
  version="$(curl -fsSL "${AGTX_API_URL}" | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
  [[ -n "${version}" ]] || die "Could not resolve latest agtx release from GitHub API."
  printf '%s' "${version}"
}

install_agtx() {
  local arch version archive url tmp_dir
  arch="$(detect_arch)"
  version="$(resolve_agtx_version)"
  archive="agtx-${version}-${arch}-linux.tar.gz"
  url="https://github.com/${AGTX_REPO}/releases/download/${version}/${archive}"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' RETURN

  log "Installing agtx ${version} (${arch}/linux) from ${url}"
  curl -fsSL "${url}" -o "${tmp_dir}/${archive}"
  tar -xzf "${tmp_dir}/${archive}" -C "${tmp_dir}"

  [[ -f "${tmp_dir}/agtx" ]] || die "agtx binary not found in downloaded archive."
  if ! mkdir -p "${INSTALL_DIR}" 2>/dev/null; then
    run_privileged mkdir -p "${INSTALL_DIR}"
  fi

  if ! install -m 0755 "${tmp_dir}/agtx" "${INSTALL_DIR}/agtx" 2>/dev/null; then
    run_privileged install -m 0755 "${tmp_dir}/agtx" "${INSTALL_DIR}/agtx"
  fi

  log "agtx installed to ${INSTALL_DIR}/agtx"

  if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    local line
    line="export PATH=\"${INSTALL_DIR}:\$PATH\""
    if ! grep -Fq "${line}" "$HOME/.bashrc" 2>/dev/null; then
      printf '\n# Added by agtx VPS bootstrap\n%s\n' "${line}" >> "$HOME/.bashrc"
      log "Added ${INSTALL_DIR} to PATH in ~/.bashrc"
    fi
  fi
}

normalize_runtime() {
  local value
  value="${1,,}"
  value="${value//[[:space:]]/}"
  printf '%s' "${value}"
}

build_gsd_runtime_flags() {
  local raw runtime
  local -a runtimes=()
  local -a flags=("--global")

  IFS=',' read -r -a raw <<< "${GSD_RUNTIMES}"
  for runtime in "${raw[@]}"; do
    runtime="$(normalize_runtime "${runtime}")"
    [[ -n "${runtime}" ]] || continue
    case "${runtime}" in
      all)
        flags+=("--all")
        printf '%s\n' "${flags[@]}"
        return
        ;;
      claude|codex|gemini|opencode)
        runtimes+=("${runtime}")
        ;;
      *)
        die "Unsupported gsd runtime '${runtime}'. Allowed: claude,codex,gemini,opencode,all"
        ;;
    esac
  done

  if ((${#runtimes[@]} == 0)); then
    die "No valid GSD runtimes selected."
  fi

  for runtime in "${runtimes[@]}"; do
    flags+=("--${runtime}")
  done

  printf '%s\n' "${flags[@]}"
}

install_gsd() {
  have_cmd node || die "node is required for get-shit-done install."
  have_cmd npx || die "npx is required for get-shit-done install."

  local -a runtime_flags=()
  local flag
  while IFS= read -r flag; do
    runtime_flags+=("${flag}")
  done < <(build_gsd_runtime_flags)

  if [[ -n "${GSD_LOCAL_REPO}" ]]; then
    local local_installer="${GSD_LOCAL_REPO}/bin/install.js"
    [[ -f "${local_installer}" ]] || die "Local GSD installer not found: ${local_installer}"
    log "Installing get-shit-done from local repo: ${GSD_LOCAL_REPO}"
    node "${local_installer}" "${runtime_flags[@]}"
    return
  fi

  log "Installing get-shit-done from npm package: ${GSD_NPM_PACKAGE}"
  npx -y "${GSD_NPM_PACKAGE}" "${runtime_flags[@]}"
}

install_global_gsd_plugin() {
  local plugin_dir plugin_file
  plugin_dir="$HOME/.config/agtx/plugins/gsd"
  plugin_file="${plugin_dir}/plugin.toml"

  mkdir -p "${plugin_dir}"
  cat > "${plugin_file}" <<'EOF'
name = "gsd"
description = "Get Shit Done - structured spec-driven development framework"
init_script = "npx get-shit-done-cc@latest --{agent} --local --non-interactive"
supported_agents = ["claude", "codex", "gemini", "opencode"]
research_required = true
cyclic = true
copy_files = ["PROJECT.md", "REQUIREMENTS.md", "ROADMAP.md", "STATE.md"]
copy_dirs = [".planning"]

[artifacts]
research = ".planning/1/1-CONTEXT.md"
planning = ".planning/{phase}/*-PLAN.md"
running = ".planning/{phase}/*-SUMMARY.md"
review = ".planning/{phase}/UAT.md"

[commands]
preresearch = "/gsd:new-project"
research = "/gsd:discuss-phase {phase}"
planning = "/gsd:plan-phase {phase}"
running = "/gsd:execute-phase {phase}"
review = "/gsd:verify-work {phase}"

[prompts]
research = "Task: {task}"

[prompt_triggers]
research = "What do you want to build?"

[copy_back]
research = ["PROJECT.md", "REQUIREMENTS.md", "ROADMAP.md", "STATE.md", ".planning"]
EOF

  log "Installed global agtx gsd plugin at ${plugin_file}"
}

ensure_global_agtx_config() {
  local cfg_path cfg_dir
  cfg_path="$HOME/.config/agtx/config.toml"
  cfg_dir="$(dirname "${cfg_path}")"

  mkdir -p "${cfg_dir}"
  if [[ -f "${cfg_path}" ]]; then
    log "Keeping existing global agtx config: ${cfg_path}"
    return
  fi

  cat > "${cfg_path}" <<EOF
default_agent = "${DEFAULT_AGENT}"

[agents]
research = "${DEFAULT_AGENT}"
planning = "${DEFAULT_AGENT}"
running = "${DEFAULT_AGENT}"
review = "${DEFAULT_AGENT}"

[worktree]
enabled = true
auto_cleanup = true
base_branch = "main"
EOF

  log "Created global agtx config: ${cfg_path}"
}

configure_project_plugin() {
  [[ -n "${PROJECT_DIR}" ]] || return
  [[ "${CONFIGURE_PROJECT}" -eq 1 ]] || return
  [[ -d "${PROJECT_DIR}" ]] || die "Project directory does not exist: ${PROJECT_DIR}"

  local cfg_dir cfg_path
  cfg_dir="${PROJECT_DIR}/.agtx"
  cfg_path="${cfg_dir}/config.toml"
  mkdir -p "${cfg_dir}"

  if [[ ! -f "${cfg_path}" ]]; then
    cat > "${cfg_path}" <<EOF
workflow_plugin = "gsd"
EOF
    log "Created project config: ${cfg_path}"
    return
  fi

  if grep -Eq '^[[:space:]]*workflow_plugin[[:space:]]*=' "${cfg_path}"; then
    sed -i -E 's|^[[:space:]]*workflow_plugin[[:space:]]*=.*$|workflow_plugin = "gsd"|' "${cfg_path}"
  else
    printf '\nworkflow_plugin = "gsd"\n' >> "${cfg_path}"
  fi

  log "Configured workflow_plugin = \"gsd\" in ${cfg_path}"
}

install_session_manager() {
  local src dst
  src="${SCRIPT_DIR}/agtx-session.sh"
  dst="${INSTALL_DIR}/agtx-session"

  if [[ ! -f "${src}" ]]; then
    warn "Session manager script not found at ${src}; skipping install."
    return
  fi

  if ! mkdir -p "${INSTALL_DIR}" 2>/dev/null; then
    run_privileged mkdir -p "${INSTALL_DIR}"
  fi

  if ! install -m 0755 "${src}" "${dst}" 2>/dev/null; then
    run_privileged install -m 0755 "${src}" "${dst}"
  fi

  log "Installed session manager command: ${dst}"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --project-dir)
        [[ $# -ge 2 ]] || die "Missing value for --project-dir"
        PROJECT_DIR="$2"
        shift 2
        ;;
      --default-agent)
        [[ $# -ge 2 ]] || die "Missing value for --default-agent"
        DEFAULT_AGENT="$2"
        shift 2
        ;;
      --gsd-runtimes)
        [[ $# -ge 2 ]] || die "Missing value for --gsd-runtimes"
        GSD_RUNTIMES="$2"
        shift 2
        ;;
      --agtx-version)
        [[ $# -ge 2 ]] || die "Missing value for --agtx-version"
        AGTX_VERSION="$2"
        shift 2
        ;;
      --install-dir)
        [[ $# -ge 2 ]] || die "Missing value for --install-dir"
        INSTALL_DIR="$2"
        shift 2
        ;;
      --gsd-local-repo)
        [[ $# -ge 2 ]] || die "Missing value for --gsd-local-repo"
        GSD_LOCAL_REPO="$2"
        shift 2
        ;;
      --skip-system-packages)
        SKIP_SYSTEM_PACKAGES=1
        shift
        ;;
      --skip-agtx)
        SKIP_AGTX=1
        shift
        ;;
      --skip-gsd)
        SKIP_GSD=1
        shift
        ;;
      --no-project-config)
        CONFIGURE_PROJECT=0
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

main() {
  parse_args "$@"

  if [[ "${SKIP_SYSTEM_PACKAGES}" -eq 0 ]]; then
    install_system_packages
  else
    log "Skipping system package installation."
  fi

  if [[ "${SKIP_AGTX}" -eq 0 ]]; then
    install_agtx
  else
    log "Skipping agtx installation."
  fi

  if [[ "${SKIP_GSD}" -eq 0 ]]; then
    install_gsd
  else
    log "Skipping get-shit-done installation."
  fi

  install_global_gsd_plugin
  ensure_global_agtx_config
  configure_project_plugin
  install_session_manager

  cat <<EOF

Setup complete.

Key commands:
  agtx --help
  agtx-session start --project-dir /path/to/your/project
  agtx-session attach
  agtx-session status

If your current shell cannot find agtx/agtx-session yet:
  source ~/.bashrc

EOF
}

main "$@"
