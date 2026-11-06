#!/usr/bin/env bash

# Safe bootstrap for a reproducible macOS workspace.
# This script never changes an existing destination path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LINKS_MANIFEST="${REPO_ROOT}/manifests/links.conf"
DEPENDENCIES_MANIFEST="${REPO_ROOT}/manifests/dependencies.conf"
REPOSITORIES_MANIFEST="${REPO_ROOT}/manifests/repositories.conf"
WORKSPACE_ROOT="${HOME}/workspace"

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh <action>

Actions:
  --check  Validate macOS, Git, Homebrew, and declared dependencies. Read-only.
  --link   Create symlinks declared in manifests/links.conf.
  --repos  Clone declared repositories into ~/workspace only when absent.
  --help   Show this help text.
EOF
}

info() { printf 'INFO: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

is_safe_relative_path() {
  case "$1" in
    ''|/*|../*|*/../*|*/..|.|*/./*|*/.) return 1 ;;
    *) return 0 ;;
  esac
}

is_safe_absolute_destination() {
  case "$1" in
    ''|/|*/../*|*/..|*/./*|*/.) return 1 ;;
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

is_managed_source_path() {
  [[ "$1" == managed/* ]] && is_safe_relative_path "$1"
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

is_expected_link() {
  local destination="$1"
  local source="$2"

  [[ -L "${destination}" ]] && [[ "$(readlink "${destination}")" == "${source}" ]]
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    error "This workspace bootstrap currently supports macOS only."
    return 1
  fi
}

check_dependencies() {
  local kind name check hint extra status=0

  while IFS='|' read -r kind name check hint extra; do
    kind="$(trim_whitespace "${kind}")"
    name="$(trim_whitespace "${name}")"
    check="$(trim_whitespace "${check}")"
    hint="$(trim_whitespace "${hint}")"
    extra="$(trim_whitespace "${extra}")"
    [[ -z "${kind}" || "${kind}" == \#* ]] && continue
    if [[ -n "${extra}" ]]; then
      error "Invalid dependency manifest row for '${name}': use four pipe-separated fields."
      status=1
      continue
    fi

    case "${kind}" in
      cli)
        if command -v "${check}" >/dev/null 2>&1; then
          info "Dependency available: ${name}"
        else
          warn "Dependency missing: ${name}. Hint: ${hint}"
          status=1
        fi
        ;;
      app)
        if [[ -d "${check}" ]]; then
          info "Application available: ${name}"
        else
          warn "Application missing: ${name}. Hint: ${hint}"
          status=1
        fi
        ;;
      manual)
        info "Manual dependency: ${name}. Hint: ${hint}"
        ;;
      *)
        error "Unknown dependency kind '${kind}' for '${name}'."
        status=1
        ;;
    esac
  done < "${DEPENDENCIES_MANIFEST}"

  return "${status}"
}

run_check() {
  local status=0

  require_macos || status=1
  if command -v git >/dev/null 2>&1; then
    info "Git is available."
  else
    warn "Git is missing. Install Xcode Command Line Tools or Git for macOS."
    status=1
  fi
  if command -v brew >/dev/null 2>&1; then
    info "Homebrew is available."
  else
    warn "Homebrew is not available. Install it only if you want to use the provided Homebrew hints."
  fi
  check_dependencies || status=1
  return "${status}"
}

run_links() {
  local source_rel destination extra source destination parent declared=0

  require_macos

  while IFS='|' read -r source_rel destination extra; do
    source_rel="$(trim_whitespace "${source_rel}")"
    destination="$(trim_whitespace "${destination}")"
    extra="$(trim_whitespace "${extra}")"
    [[ -z "${source_rel}" || "${source_rel}" == \#* ]] && continue
    declared=$((declared + 1))

    if [[ -n "${extra}" ]]; then
      error "Invalid link manifest row for '${source_rel}': use two pipe-separated fields."
      return 1
    fi
    if ! is_managed_source_path "${source_rel}"; then
      error "Link sources must be safe paths below managed/: ${source_rel}"
      return 1
    fi
    if ! is_safe_absolute_destination "${destination}"; then
      error "Link destinations must be safe absolute paths: ${destination}"
      return 1
    fi

    source="${REPO_ROOT}/${source_rel}"
    if [[ ! -e "${source}" && ! -L "${source}" ]]; then
      error "Source does not exist: ${source_rel}"
      return 1
    fi
    if [[ -L "${source}" ]]; then
      error "Link sources must not be symlinks: ${source_rel}"
      return 1
    fi
    if is_expected_link "${destination}" "${source}"; then
      continue
    fi
    if [[ -e "${destination}" || -L "${destination}" ]]; then
      error "Destination already exists and will not be changed: ${destination}"
      return 1
    fi
  done < "${LINKS_MANIFEST}"

  if [[ "${declared}" -eq 0 ]]; then
    info "No links declared."
    return 0
  fi

  while IFS='|' read -r source_rel destination extra; do
    source_rel="$(trim_whitespace "${source_rel}")"
    destination="$(trim_whitespace "${destination}")"
    extra="$(trim_whitespace "${extra}")"
    [[ -z "${source_rel}" || "${source_rel}" == \#* ]] && continue
    source="${REPO_ROOT}/${source_rel}"
    if is_expected_link "${destination}" "${source}"; then
      info "Already linked ${destination}"
      continue
    fi
    parent="$(dirname "${destination}")"
    mkdir -p "${parent}"
    ln -s "${source}" "${destination}"
    info "Linked ${destination}"
  done < "${LINKS_MANIFEST}"
}

run_repositories() {
  local name url destination_rel extra destination parent planned=0

  require_macos

  if ! command -v git >/dev/null 2>&1; then
    error "Git is required to clone external repositories."
    return 1
  fi

  while IFS='|' read -r name url destination_rel extra; do
    name="$(trim_whitespace "${name}")"
    url="$(trim_whitespace "${url}")"
    destination_rel="$(trim_whitespace "${destination_rel}")"
    extra="$(trim_whitespace "${extra}")"
    [[ -z "${name}" || "${name}" == \#* ]] && continue
    if [[ -n "${extra}" ]] || [[ -z "${url}" ]] || ! is_safe_relative_path "${destination_rel}"; then
      error "Invalid repository manifest row for '${name}'."
      return 1
    fi
    destination="${WORKSPACE_ROOT}/${destination_rel}"
    if [[ -e "${destination}" || -L "${destination}" ]]; then
      error "Destination already exists and will not be changed: ${destination}"
      return 1
    fi
    planned=$((planned + 1))
  done < "${REPOSITORIES_MANIFEST}"

  if [[ "${planned}" -eq 0 ]]; then
    info "No external repositories declared."
    return 0
  fi

  while IFS='|' read -r name url destination_rel extra; do
    name="$(trim_whitespace "${name}")"
    url="$(trim_whitespace "${url}")"
    destination_rel="$(trim_whitespace "${destination_rel}")"
    [[ -z "${name}" || "${name}" == \#* ]] && continue
    destination="${WORKSPACE_ROOT}/${destination_rel}"
    parent="$(dirname "${destination}")"
    mkdir -p "${parent}"
    git clone -- "${url}" "${destination}"
    info "Cloned ${name} to ${destination}"
  done < "${REPOSITORIES_MANIFEST}"
}

if [[ "$#" -ne 1 ]]; then
  usage >&2
  exit 2
fi

case "$1" in
  --check) run_check ;;
  --link) run_links ;;
  --repos) run_repositories ;;
  --help) usage ;;
  *) error "Unknown action: $1"; usage >&2; exit 2 ;;
esac
