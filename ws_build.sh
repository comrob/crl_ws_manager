#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=ws_lib.sh
source "$SCRIPT_DIR/ws_lib.sh"

CLEAN_SCRIPT=""
if [[ -x "$SCRIPT_DIR/ws-clean" ]]; then
  CLEAN_SCRIPT="$SCRIPT_DIR/ws-clean"
elif [[ -x "$SCRIPT_DIR/ws_clean.sh" ]]; then
  CLEAN_SCRIPT="$SCRIPT_DIR/ws_clean.sh"
fi

print_usage() {
  ws_load_config
  echo "Usage: ws build [--all] [--clean] [-w|--ws <workspace>]... [-p|--packages <pkg>]... [<pkg>...]"
  echo ""
  echo "Workspace selection (in priority order):"
  echo "  1. Explicit -w/--ws flags."
  echo "  2. Inferred from package location (scans env + default workspaces)."
  echo "  3. All env-detected workspaces (ROS_PACKAGE_PATH / COLCON_PREFIX_PATH)."
  echo "  4. Defaults: ~/sw_ws  ~/drv_ws."
  echo ""
  echo "Notes:"
  if [[ "$WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD" == "true" ]]; then
    echo "  ws build without arguments prints this help."
    echo "  Use --all to build all detected workspaces."
  else
    echo "  ws build without arguments builds all detected workspaces."
  fi
  echo "  Local config: $(ws_config_file)"
  echo ""
  echo "Examples:"
  if [[ "$WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD" == "true" ]]; then
    echo "  ws build --all"
  else
    echo "  ws build"
  fi
  echo "  ws build liorf"
  echo "  ws build -w drv_ws"
  echo "  ws build -w drv_ws -p package_a -p package_b"
  echo "  ws build --clean -p package_a"
}

if ws_is_help_token "${1:-}"; then
  print_usage
  exit 0
fi

build_workspace() {
  local workspace="$1"
  shift

  if [[ ! -d "$workspace/src" ]]; then
    echo "[SKIP] $workspace (missing src directory)"
    return 0
  fi

  local cmd=()
  ws_build_make_command cmd "$@"

  echo "Workspace: $workspace"
  printf 'Executing:'
  printf ' %q' "${cmd[@]}"
  printf '\n'

  (
    cd "$workspace" || exit 1
    "${cmd[@]}"
  )
}

selected_workspaces=()
selected_packages=()
clean_first=false
build_all=false

ws_load_config

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      build_all=true
      shift
      ;;
    --clean)
      clean_first=true
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
      expanded="$(ws_normalize_path "$1")"
      if [[ -d "$expanded/src" ]]; then
        selected_workspaces+=("$expanded")
      else
        selected_packages+=("$1")
      fi
      shift
      ;;
  esac
done

if [[ "$clean_first" == true && ${#selected_packages[@]} -eq 0 ]]; then
  echo "Error: --clean requires at least one package." >&2
  echo "Use 'ws clean --clean-all' to clean an entire workspace." >&2
  exit 1
fi

if [[ "$WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD" == "true" && "$build_all" == false && ${#selected_workspaces[@]} -eq 0 && ${#selected_packages[@]} -eq 0 ]]; then
  print_usage
  exit 0
fi

if [[ "$clean_first" == true && -z "$CLEAN_SCRIPT" ]]; then
  echo "Error: could not find executable clean helper next to ws-build." >&2
  echo "Checked: $SCRIPT_DIR/ws-clean and $SCRIPT_DIR/ws_clean.sh" >&2
  exit 1
fi

declare -A resolved_ws_pkgs=()
ws_resolve_workspaces selected_workspaces selected_packages workspaces resolved_ws_pkgs \
  || exit 1

if [[ -f "/opt/ros/${ROS_DISTRO:-jazzy}/setup.bash" ]]; then
  # shellcheck disable=SC1091
  source "/opt/ros/${ROS_DISTRO:-jazzy}/setup.bash"
fi

built_any=false
status=0

for workspace in "${workspaces[@]}"; do
  # Determine the package list for this specific workspace.
  if [[ "$WS_PKG_INFERRED" == true ]]; then
    ws_pkg_string="${resolved_ws_pkgs[$workspace]:-}"
    read -r -a packages_for_workspace <<< "$ws_pkg_string"
    if [[ ${#packages_for_workspace[@]} -eq 0 ]]; then
      continue
    fi
  else
    packages_for_workspace=("${selected_packages[@]}")
  fi

  if [[ ! -d "$workspace/src" ]]; then
    echo "[SKIP] $workspace (missing src directory)"
    continue
  fi

  built_any=true

  if [[ "$clean_first" == true ]]; then
    clean_cmd=("$CLEAN_SCRIPT" -w "$workspace")
    for pkg in "${packages_for_workspace[@]}"; do
      clean_cmd+=(-p "$pkg")
    done
    echo "Workspace: $workspace"
    printf 'Cleaning:'
    printf ' %q' "${clean_cmd[@]}"
    printf '\n'
    "${clean_cmd[@]}" || status=$?
  fi

  build_workspace "$workspace" "${packages_for_workspace[@]}" || status=$?
done

if [[ "$built_any" == false ]]; then
  echo "No workspaces found to build."
  echo "Checked: ${workspaces[*]}"
  exit 1
fi

exit "$status"
