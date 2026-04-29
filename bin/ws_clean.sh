#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=../lib/ws_lib.sh
source "$SCRIPT_DIR/../lib/ws_lib.sh"

print_usage() {
  echo "Usage: ws clean [--clean-all] [-w|--ws <workspace>]... [-p <package>]... [<package>...]"
  echo "       ws clean --clean-all [-w|--ws <workspace>]"
  echo ""
  echo "Options:"
  echo "  --clean-all          Remove build/, install/, and log/ for the entire workspace"
  echo "  -w, --ws <workspace> Target a specific workspace"
  echo "  -p, --packages <pkg> Package to clean (repeatable)"
  echo "  <package>            One or more package names to clean (positional)"
  echo ""
  echo "Workspace selection (in priority order):"
  echo "  1. Explicit -w/--ws flags."
  echo "  2. Inferred from package location (scans env + default workspaces)."
  echo "  3. All env-detected workspaces (ROS_PACKAGE_PATH / COLCON_PREFIX_PATH)."
  echo "  4. WS_DEFAULT_WORKSPACES (configurable in ws_config.bash; default: ~/sw_ws  ~/drv_ws)."
  echo ""
  echo "Examples:"
  echo "  ws clean pylon_instant_camera"
  echo "  ws clean -p pylon_instant_camera"
  echo "  ws clean -w drv_ws pylon_instant_camera"
  echo "  ws clean -w drv_ws -p pkg_a -p pkg_b"
  echo "  ws clean --clean-all"
  echo "  ws clean --clean-all -w drv_ws"
}

if ws_is_help_token "${1:-}"; then
  print_usage
  exit 0
fi

clean_all=false
selected_workspaces=()
selected_packages=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean-all)
      clean_all=true
      shift
      ;;
    -w|--ws)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a workspace name or path." >&2
        exit 1
      fi
      selected_workspaces+=("$(ws_normalize_path "$2")")
      shift 2
      ;;
    -p|--packages)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a package name." >&2
        exit 1
      fi
      selected_packages+=("$2")
      shift 2
      ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      print_usage >&2
      exit 1
      ;;
    *)
      selected_packages+=("$1")
      shift
      ;;
  esac
done

# Nothing requested → print usage and exit cleanly.
if [[ "$clean_all" == false && ${#selected_packages[@]} -eq 0 ]]; then
  print_usage
  exit 0
fi

do_clean_workspace() {
  local workspace="$1"
  shift
  # Remaining args are the packages to clean (empty = use $selected_packages).
  local -a pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && pkgs=("${selected_packages[@]}")

  if [[ ! -d "$workspace" ]]; then
    echo "[SKIP] $workspace (directory does not exist)"
    return 0
  fi

  if [[ "$clean_all" == true ]]; then
    echo "Cleaning workspace: $workspace"
    local dir
    for dir in build install log; do
      if [[ -d "$workspace/$dir" ]]; then
        echo "  Removing $workspace/$dir"
        rm -rf "$workspace/$dir"
      fi
    done
  else
    local pkg found_any dir
    for pkg in "${pkgs[@]}"; do
      found_any=false
      for dir in build install log; do
        if [[ -d "$workspace/$dir/$pkg" ]]; then
          echo "  Removing $workspace/$dir/$pkg"
          rm -rf "$workspace/$dir/$pkg"
          found_any=true
        fi
      done
      if [[ "$found_any" == false ]]; then
        if ws_has_package "$workspace" "$pkg"; then
          echo "  [SKIP] $pkg: no build/install/log folders found (already clean?)"
        else
          echo "  [WARN] $pkg: package not found in $workspace"
        fi
      fi
    done
  fi
}

declare -A resolved_ws_pkgs=()
ws_resolve_workspaces selected_workspaces selected_packages workspaces resolved_ws_pkgs \
  || exit 1

for workspace in "${workspaces[@]}"; do
  if [[ "$WS_PKG_INFERRED" == true && "$clean_all" == false ]]; then
    ws_pkg_string="${resolved_ws_pkgs[$workspace]:-}"
    read -r -a packages_for_workspace <<< "$ws_pkg_string"
    if [[ ${#packages_for_workspace[@]} -eq 0 ]]; then
      continue
    fi
    do_clean_workspace "$workspace" "${packages_for_workspace[@]}"
  else
    do_clean_workspace "$workspace"
  fi
done
