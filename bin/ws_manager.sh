#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=lib/ws_lib.sh
source "$SCRIPT_DIR/../lib/ws_lib.sh"

# ---------------------------------------------------------------------------
# _ws_dispatch <subcommand> [args...]
#   Resolve and exec the helper script for a given subcommand name.
#   Looks for ws-<name> (symlinked binary) then ws_<name>.sh (source file).
# ---------------------------------------------------------------------------
_ws_dispatch() {
  local name="$1"; shift
  local script=""
  if [[ -x "$SCRIPT_DIR/ws-${name}" ]]; then
    script="$SCRIPT_DIR/ws-${name}"
  elif [[ -x "$SCRIPT_DIR/ws_${name}.sh" ]]; then
    script="$SCRIPT_DIR/ws_${name}.sh"
  else
    echo "Error: could not find helper for 'ws ${name}'." >&2
    echo "Expected: $SCRIPT_DIR/ws-${name} or $SCRIPT_DIR/ws_${name}.sh" >&2
    exit 1
  fi
  exec "$script" "$@"
}

print_usage() {
  ws_print_main_help
  echo ""
  echo "  ws version / --version       Show version"
  echo "  ws update                    Pull latest changes and reinstall"
  echo "  ws doctor                    Diagnose common configuration issues"
}

print_version() {
  local version_file="$SCRIPT_DIR/../VERSION"
  local version="unknown"
  [[ -f "$version_file" ]] && version="$(cat "$version_file")"
  echo "ws_manager $version"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  ""|help|-h|--help)
    print_usage
    exit 0
    ;;
  version|--version)
    print_version
    exit 0
    ;;
  cd)
    if ws_is_help_token "${1:-}"; then
      _ws_dispatch "cd_resolve" --help
    fi
    echo "Error: 'ws cd' must run as a shell function to change your current directory." >&2
    echo "Run ./install.sh, then source ~/.bashrc and use: ws cd <package_name>" >&2
    exit 2
    ;;
  build|clean|list|open|config|which)
    _ws_dispatch "$cmd" "$@"
    ;;
  update)
    repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    if [[ ! -d "$repo_root/.git" ]]; then
      echo "Error: ws_manager was not cloned from git — cannot auto-update." >&2
      echo "Update manually: replace the repo files and run ./install.sh" >&2
      exit 1
    fi
    echo "Pulling latest changes in $repo_root ..."
    git -C "$repo_root" pull
    echo "Reinstalling ..."
    exec "$repo_root/install.sh"
    ;;
  doctor)
    ok=true       # tracks hard failures (broken install)
    warn=false    # tracks soft warnings (missing optional deps)

    _check() {
      local label="$1" result="$2" detail="${3:-}"
      if [[ "$result" == "ok" ]]; then
        printf '  [ OK ] %s\n' "$label"
      else
        printf '  [FAIL] %s\n' "$label"
        [[ -n "$detail" ]] && printf '         %s\n' "$detail"
        ok=false
      fi
    }
    _warn() {
      local label="$1" detail="${2:-}"
      printf '  [WARN] %s\n' "$label"
      [[ -n "$detail" ]] && printf '         %s\n' "$detail"
      warn=true
    }

    echo "ws_manager doctor"
    echo "-----------------"

    # 1. Binary on PATH
    if command -v ws >/dev/null 2>&1; then
      _check "ws binary on PATH" ok "$(command -v ws)"
    else
      _check "ws binary on PATH" fail "$HOME/.local/bin not on PATH — run: source ~/.bashrc"
    fi

    # 2. Subcommand binaries present
    for sub in ws-build ws-clean ws-cd-resolve ws-list ws-open ws-config ws-which; do
      if command -v "$sub" >/dev/null 2>&1; then
        _check "$sub on PATH" ok
      else
        _check "$sub on PATH" fail "run: make install"
      fi
    done

    # 3. Config file
    cfg="$(ws_config_file)"
    if [[ -f "$cfg" ]]; then
      _check "Config file exists" ok "$cfg"
    else
      _check "Config file exists" fail "run: ws config init"
    fi

    # 4. Shell functions loaded
    func_file="$(ws_functions_file)"
    if [[ -f "$func_file" ]]; then
      _check "Shell functions file present" ok "$func_file"
    else
      _check "Shell functions file present" fail "run: make install"
    fi

    # 5. ROS environment  (warning only — ws cd/list/which work without it)
    if [[ -n "${ROS_DISTRO:-}" ]]; then
      _check "ROS_DISTRO set" ok "$ROS_DISTRO"
    else
      _warn "ROS_DISTRO not set" "ws build requires it; run: source /opt/ros/<distro>/setup.bash"
    fi

    # 6. colcon available  (warning only — ws cd/list/open/which/config work without it)
    if command -v colcon >/dev/null 2>&1; then
      _check "colcon available" ok "$(command -v colcon)"
    else
      _warn "colcon not found" "required for ws build; install: pip install colcon-common-extensions"
    fi

    # 7. Detected workspaces
    ws_load_config
    declare -a _ws_list=()
    ws_detect_from_env _ws_list
    if [[ ${#_ws_list[@]} -gt 0 ]]; then
      _check "Workspaces detected (${#_ws_list[@]})" ok "${_ws_list[*]}"
    else
      _warn "No workspaces detected" "source a workspace or set WS_DEFAULT_WORKSPACES in ws_config.bash"
    fi

    echo ""
    if [[ "$ok" == true && "$warn" == false ]]; then
      echo "All checks passed."
    elif [[ "$ok" == true ]]; then
      echo "Install OK — some optional components are missing (see warnings above)."
    else
      echo "Some checks failed — see details above."
      exit 1
    fi
    ;;
  *)
    echo "Error: unknown subcommand '$cmd'" >&2
    print_usage >&2
    exit 1
    ;;
esac
