#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=lib/ws_lib.sh
source "$SCRIPT_DIR/../lib/ws_lib.sh"

# ---------------------------------------------------------------------------
# Colour helpers (only when stdout is a terminal).
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  _C_GREEN=$'\033[0;32m'
  _C_RED=$'\033[0;31m'
  _C_BLUE=$'\033[0;34m'
  _C_BOLD=$'\033[1m'
  _C_DIM=$'\033[2m'
  _C_RESET=$'\033[0m'
else
  _C_GREEN='' _C_RED='' _C_BLUE='' _C_BOLD='' _C_DIM='' _C_RESET=''
fi

print_usage() {
  echo "Usage: ws list [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  (none)               List workspaces and packages (default)"
  echo "  -W, --workspaces     Workspace-only view (no package expansion)"
  echo "  -p, --packages       Explicit package-expanded view"
  echo "  -w, --ws <workspace> Scope to a single workspace"
  echo "  --installed          Show only packages that have been built"
  echo "  -q, --quiet          Machine-readable output (no decoration or colour)"
  echo "  -h, --help           Show this help"
  echo ""
  echo "Workspace selection follows the standard hierarchy:"
  echo "  1. Explicit -w/--ws flag"
  echo "  2. ROS_PACKAGE_PATH / COLCON_PREFIX_PATH (env-detected)"
  echo "  3. WS_DEFAULT_WORKSPACES (default: ~/sw_ws  ~/drv_ws; override in ws_config.bash)."
  echo ""
  echo "Definitions:"
  echo "  sourced   — workspace/install/ appears in COLCON_PREFIX_PATH"
  echo "  installed — workspace/install/<pkg>/ directory exists (package is built)"
  echo ""
  echo "Examples:"
  echo "  ws list"
  echo "  ws list -W"
  echo "  ws list --installed"
  echo "  ws list -w sw_ws"
  echo "  ws list -q"
  echo "  ws list -W -q"
}

if ws_is_help_token "${1:-}"; then
  print_usage
  exit 0
fi

# ---------------------------------------------------------------------------
# Formatting helpers.
# ---------------------------------------------------------------------------
_fmt_workspace() {
  local ws="$1"
  local sourced="$2"   # "true" / "false"
  local short="${ws/#$HOME/\~}"

  if [[ "$quiet" == true ]]; then
    if [[ "$sourced" == true ]]; then
      printf '%s sourced\n' "$ws"
    else
      printf '%s not-sourced\n' "$ws"
    fi
  else
    if [[ "$sourced" == true ]]; then
      printf "${_C_BOLD}%s${_C_RESET}  ${_C_GREEN}[sourced]${_C_RESET}\n" "$short"
    else
      printf "${_C_BOLD}%s${_C_RESET}  ${_C_DIM}[NOT sourced]${_C_RESET}\n" "$short"
    fi
  fi
}

_fmt_package() {
  local ws="$1"
  local pkg="$2"
  local _is_last="$3"   # compatibility arg; unused in list rendering
  local installed=false
  local pkg_dir=""
  local symlink_target=""

  ws_is_package_installed "$ws" "$pkg" && installed=true

  if pkg_dir=$(ws_package_dir "$ws" "$pkg" 2>/dev/null); then
    if [[ -L "$pkg_dir" ]]; then
      symlink_target=$(readlink -f "$pkg_dir" 2>/dev/null || readlink "$pkg_dir" 2>/dev/null || true)
    fi
  fi

  if [[ "$quiet" == true ]]; then
    local status_word="not-installed"
    [[ "$installed" == true ]] && status_word="installed"

    if [[ "$installed" == true ]]; then
      if [[ -n "$symlink_target" ]]; then
        printf '%s %s %s symlink=%s\n' "$ws" "$pkg" "$status_word" "$symlink_target"
      else
        printf '%s %s %s\n' "$ws" "$pkg" "$status_word"
      fi
    else
      if [[ -n "$symlink_target" ]]; then
        printf '%s %s %s symlink=%s\n' "$ws" "$pkg" "$status_word" "$symlink_target"
      else
        printf '%s %s %s\n' "$ws" "$pkg" "$status_word"
      fi
    fi
  else
    local symlink_suffix=""

    if [[ -n "$symlink_target" ]]; then
      symlink_suffix=" ${_C_BLUE}-> $symlink_target${_C_RESET}"
    fi

    if [[ "$installed" == true ]]; then
      printf "  - %s%s ${_C_GREEN}[installed]${_C_RESET}\n" "$pkg" "$symlink_suffix"
    else
      printf "  - %s%s ${_C_RED}[NOT installed]${_C_RESET}\n" "$pkg" "$symlink_suffix"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
show_packages=true
installed_only=false
quiet=false
selected_workspaces=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    help|-h|--help)
      print_usage
      exit 0
      ;;
    -p|--packages)
      show_packages=true
      shift
      ;;
    -W|--workspaces)
      show_packages=false
      shift
      ;;
    -w|--ws)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a workspace path." >&2
        exit 1
      fi
      selected_workspaces+=("$(ws_normalize_path "$2")")
      shift 2
      ;;
    --installed)
      installed_only=true
      shift
      ;;
    -q|--quiet)
      quiet=true
      shift
      ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      print_usage >&2
      exit 1
      ;;
    *)
      echo "Error: unexpected argument '$1'" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

# --installed only makes sense with package expansion.
if [[ "$installed_only" == true && "$show_packages" == false ]]; then
  echo "Note: --installed implies package-expanded output." >&2
  show_packages=true
fi

# ---------------------------------------------------------------------------
# Resolve workspaces.
# ---------------------------------------------------------------------------
if [[ ${#selected_workspaces[@]} -eq 0 ]]; then
  ws_detect_from_env selected_workspaces
fi

# Filter to only workspaces that have a src/ dir (skip missing defaults).
workspaces=()
for _ws in "${selected_workspaces[@]}"; do
  [[ -d "$_ws/src" ]] && workspaces+=("$_ws")
done

if [[ ${#workspaces[@]} -eq 0 ]]; then
  if [[ "$quiet" == true ]]; then
    echo "no-workspaces" >&2
  else
    echo "No workspaces found." >&2
    echo "Tip: source a workspace or use -w/--ws to specify one." >&2
  fi
  exit 1
fi

# ---------------------------------------------------------------------------
# Section 1: Workspace summary (always shown).
# ---------------------------------------------------------------------------
if [[ "$quiet" == false && "$show_packages" == true ]]; then
  printf '%b\n' "${_C_BOLD}Workspaces${_C_RESET}"
fi

for ws in "${workspaces[@]}"; do
  sourced=false
  ws_is_workspace_sourced "$ws" && sourced=true
  _fmt_workspace "$ws" "$sourced"
done

# ---------------------------------------------------------------------------
# Section 2: Package expansion (default, unless -W/--workspaces).
# ---------------------------------------------------------------------------
[[ "$show_packages" == false ]] && exit 0

if [[ "$quiet" == false ]]; then
  printf '\n'
fi

for ws in "${workspaces[@]}"; do
  local_packages=()
  ws_list_packages_in_workspace "$ws" local_packages

  # Apply --installed filter.
  if [[ "$installed_only" == true ]]; then
    filtered=()
    for pkg in "${local_packages[@]}"; do
      ws_is_package_installed "$ws" "$pkg" && filtered+=("$pkg")
    done
    local_packages=("${filtered[@]}")
  fi

  [[ ${#local_packages[@]} -eq 0 ]] && continue

  if [[ "$quiet" == false ]]; then
    short_ws="${ws/#$HOME/\~}"
    printf '%b\n' "${_C_BOLD}${short_ws}${_C_RESET}"
  fi

  total=${#local_packages[@]}
  for i in "${!local_packages[@]}"; do
    pkg="${local_packages[$i]}"
    is_last=false
    [[ $((i + 1)) -eq $total ]] && is_last=true
    _fmt_package "$ws" "$pkg" "$is_last"
  done

  [[ "$quiet" == false ]] && printf '\n'
done
