#!/usr/bin/env bash
# ws_lib.sh — shared helpers for ws_build.sh and ws_clean.sh.
#
# Source this file; do not execute it directly.
#
# Workspace resolution hierarchy (highest to lowest priority):
#   1. Explicit -w/--ws flags passed by the caller.
#   2. Package-driven lookup: scan env-detected workspaces (+ default fallbacks)
#      for workspaces that actually contain the requested packages.
#   3. Environment-detected workspaces from ROS_PACKAGE_PATH / COLCON_PREFIX_PATH.
#   4. Configured fallbacks from WS_DEFAULT_WORKSPACES.
#
# Only levels 3 and 4 are used when no packages are requested (build-all /
# clean-all scenarios).

# ---------------------------------------------------------------------------
# ws_config_dir / ws_legacy_config_dir / ws_config_file / ws_functions_file
#   Resolve the local configuration locations for this tool.
# ---------------------------------------------------------------------------
ws_config_dir() {
  printf '%s' "${WS_CONFIG_DIR:-${CRL_WS_CONFIG_DIR:-$HOME/.config/crl_ws_manager}}"
}

ws_legacy_config_dir() {
  printf '%s' "${WS_LEGACY_CONFIG_DIR:-${CRL_WS_LEGACY_CONFIG_DIR:-$HOME/.config/crl_husky_deployment}}"
}

ws_config_file() {
  printf '%s/ws_config.bash' "$(ws_config_dir)"
}

ws_legacy_config_file() {
  printf '%s/ws_config.bash' "$(ws_legacy_config_dir)"
}

ws_functions_file() {
  printf '%s/ws_manager.bash' "$(ws_config_dir)"
}

ws_lib_file() {
  printf '%s/ws_lib.sh' "$(ws_config_dir)"
}

# ---------------------------------------------------------------------------
# ws_print_main_help
#   Print the shared top-level help text for the ws command.
# ---------------------------------------------------------------------------
ws_print_main_help() {
  echo "ROS workspace manager"
  echo "Run 'ws --help' to see available commands."
  echo ""
  echo "Usage: ws [build | clean | cd | list | open | config] <args>"
  echo "  ws build [options]           Build workspaces/packages"
  echo "  ws build --all               Build all detected workspaces"
  echo "  ws build --clean -p <pkg>    Clean package artifacts before build"
  echo "  ws clean [options]           Clean package build/install/log dirs"
  echo "  ws clean --clean-all         Clean entire workspace"
  echo "  ws cd [--source|--install] <package_name>"
  echo "  ws cd --help                 Show cd usage"
  echo "  ws list                      List workspaces + packages"
  echo "  ws list -W                   Workspace-only view"
  echo "  ws list --installed          Only show built packages"
  echo "  ws list -w <ws>              Scope to one workspace"
  echo "  ws which <pkg> [launch]      Show package and artifact file paths"
  echo "  ws open <pkg>                Open package path in configured editor"
  echo "  ws config [show|edit|path]   Manage local ws configuration"
  echo ""
  echo "Local config: $(ws_config_file)"
}

# ---------------------------------------------------------------------------
# ws_is_help_token token
#   Return 0 when the provided token should trigger help output.
# ---------------------------------------------------------------------------
ws_is_help_token() {
  case "${1:-}" in
    help|-h|--help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# ws_load_config
#   Load built-in defaults and then source the local config file, if present.
# ---------------------------------------------------------------------------
ws_load_config() {
  if [[ "${WS_CONFIG_LOADED:-false}" == "true" ]]; then
    return 0
  fi

  : "${WS_BUILD_PROGRAM:=colcon}"
  : "${WS_BUILD_SUBCOMMAND:=build}"
  if ! declare -p WS_BUILD_DEFAULT_ARGS >/dev/null 2>&1; then
    WS_BUILD_DEFAULT_ARGS=(--symlink-install --continue-on-error)
  fi
  : "${WS_BUILD_PACKAGE_SELECT_FLAG:=--packages-select}"
  : "${WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD:=true}"
  : "${WS_EDITOR_PROGRAM:=code}"
  if ! declare -p WS_EDITOR_ARGS >/dev/null 2>&1; then
    WS_EDITOR_ARGS=()
  fi
  if ! declare -p WS_DEFAULT_WORKSPACES >/dev/null 2>&1; then
    WS_DEFAULT_WORKSPACES=("$HOME/sw_ws" "$HOME/drv_ws")
  fi

  local cfg_file=""
  if [[ -f "$(ws_config_file)" ]]; then
    cfg_file="$(ws_config_file)"
  elif [[ -f "$(ws_legacy_config_file)" ]]; then
    cfg_file="$(ws_legacy_config_file)"
  fi

  if [[ -n "$cfg_file" ]]; then
    # shellcheck disable=SC1090
    source "$cfg_file"
  fi

  WS_CONFIG_LOADED=true
}

# ---------------------------------------------------------------------------
# ws_init_config_file_if_missing
#   Create a local config template if one does not already exist.
# ---------------------------------------------------------------------------
ws_init_config_file_if_missing() {
  local cfg_file
  cfg_file="$(ws_config_file)"

  mkdir -p "$(ws_config_dir)"

  if [[ -f "$cfg_file" ]]; then
    return 0
  fi

  cat > "$cfg_file" <<'EOF'
# Local configuration for the ROS workspace manager.
#
# This file is sourced by ws_* scripts, so use valid Bash syntax.
# CLI arguments still take precedence over these defaults.

WS_BUILD_PROGRAM="colcon"
WS_BUILD_SUBCOMMAND="build"
WS_BUILD_DEFAULT_ARGS=(
  --symlink-install
  --continue-on-error
)
WS_BUILD_PACKAGE_SELECT_FLAG="--packages-select"
WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD=true

# Fallback workspace roots used when none are detectable from the ROS
# environment (ROS_PACKAGE_PATH / COLCON_PREFIX_PATH).  Add or remove paths
# to match your setup.
WS_DEFAULT_WORKSPACES=(
  "$HOME/sw_ws"
  "$HOME/drv_ws"
)

# Editor command used by: ws open <package>
WS_EDITOR_PROGRAM="code"
WS_EDITOR_ARGS=()
EOF
}

# ---------------------------------------------------------------------------
# ws_append_config_line
#   Append a setting line to the local config file.
# ---------------------------------------------------------------------------
ws_append_config_line() {
  local line="$1"
  ws_init_config_file_if_missing
  printf '%s\n' "$line" >> "$(ws_config_file)"
}

# ---------------------------------------------------------------------------
# ws_upsert_config_assignment key assignment-line
#   Replace (or append) a top-level KEY=... or KEY=(...) assignment in the
#   local config file so repeated ws config set-* commands stay idempotent.
# ---------------------------------------------------------------------------
ws_upsert_config_assignment() {
  local key="$1"
  local assignment="$2"
  local cfg tmp

  ws_init_config_file_if_missing
  cfg="$(ws_config_file)"
  tmp="$(mktemp)"

  awk -v key="$key" -v assignment="$assignment" '
    BEGIN { replaced = 0 }
    $0 ~ "^" key "=" || $0 ~ "^" key "\\(" {
      if (replaced == 0) {
        print assignment
        replaced = 1
      }
      next
    }
    { print }
    END {
      if (replaced == 0) {
        print assignment
      }
    }
  ' "$cfg" > "$tmp"

  mv "$tmp" "$cfg"
}

# ---------------------------------------------------------------------------
# ws_build_make_command out-array-name package...
#   Build the effective build command from local configuration.
# ---------------------------------------------------------------------------
ws_build_make_command() {
  local out_name="$1"
  shift
  local -n _wbmc_ref="$out_name"
  local -a packages=("$@")

  ws_load_config

  _wbmc_ref=("$WS_BUILD_PROGRAM")
  if [[ -n "$WS_BUILD_SUBCOMMAND" ]]; then
    _wbmc_ref+=("$WS_BUILD_SUBCOMMAND")
  fi
  _wbmc_ref+=("${WS_BUILD_DEFAULT_ARGS[@]}")

  if [[ ${#packages[@]} -gt 0 && -n "$WS_BUILD_PACKAGE_SELECT_FLAG" ]]; then
    _wbmc_ref+=("$WS_BUILD_PACKAGE_SELECT_FLAG" "${packages[@]}")
  fi
}

# ---------------------------------------------------------------------------
# ws_editor_make_command out-array-name target-path
#   Build the effective editor command from local configuration.
# ---------------------------------------------------------------------------
ws_editor_make_command() {
  local out_name="$1"
  local target_path="$2"
  local -n _wemc_ref="$out_name"

  ws_load_config

  _wemc_ref=("$WS_EDITOR_PROGRAM")
  _wemc_ref+=("${WS_EDITOR_ARGS[@]}")
  _wemc_ref+=("$target_path")
}

# ---------------------------------------------------------------------------
# ws_normalize_path path-string
#   Expand leading ~ and make relative paths absolute under $HOME.
#   Prints the normalized path to stdout.
# ---------------------------------------------------------------------------
ws_normalize_path() {
  local p="${1/#\~/$HOME}"
  if [[ "$p" != /* ]]; then
    p="$HOME/$p"
  fi
  printf '%s' "$p"
}

# ---------------------------------------------------------------------------
# _ws_append_unique array-name value
#   Append value to the named array only if it is not already present.
#   (Internal helper; prefer the public wrappers below.)
# ---------------------------------------------------------------------------
_ws_append_unique() {
  local out_name="$1"
  local value="$2"
  local -n _au_ref="$out_name"
  local existing

  for existing in "${_au_ref[@]+"${_au_ref[@]}"}"; do
    [[ "$existing" == "$value" ]] && return 0
  done
  _au_ref+=("$value")
}

# ---------------------------------------------------------------------------
# ws_detect_from_env array-name
#   Populate the named array with workspace roots detected from the current
#   ROS environment (ROS_PACKAGE_PATH and COLCON_PREFIX_PATH).  Duplicate
#   entries are suppressed.  WS_DEFAULT_WORKSPACES entries (configurable via
#   ws_config.bash; defaults to ~/sw_ws ~/drv_ws) are appended as fallbacks.
# ---------------------------------------------------------------------------
ws_detect_from_env() {
  local out_name="$1"
  local -n _env_ref="$out_name"
  local entry ws_root
  local -a _env_paths=()

  ws_load_config
  _env_ref=()

  if [[ -n "${ROS_PACKAGE_PATH:-}" ]]; then
    IFS=':' read -r -a _env_paths <<< "$ROS_PACKAGE_PATH"
    for entry in "${_env_paths[@]}"; do
      [[ -z "$entry" ]] && continue
      entry="${entry/#\~/$HOME}"
      if [[ "$entry" == */src* ]]; then
        ws_root="${entry%%/src*}"
        [[ -d "$ws_root/src" ]] && _ws_append_unique "$out_name" "$ws_root"
      fi
    done
  fi

  if [[ -n "${COLCON_PREFIX_PATH:-}" ]]; then
    IFS=':' read -r -a _env_paths <<< "$COLCON_PREFIX_PATH"
    for entry in "${_env_paths[@]}"; do
      [[ -z "$entry" ]] && continue
      entry="${entry/#\~/$HOME}"
      if [[ "$entry" == */install* ]]; then
        ws_root="${entry%%/install*}"
        [[ -d "$ws_root/src" ]] && _ws_append_unique "$out_name" "$ws_root"
      fi
    done
  fi

  # Append user-configured fallback workspaces (from WS_DEFAULT_WORKSPACES).
  local _default_ws
  for _default_ws in "${WS_DEFAULT_WORKSPACES[@]:-}"; do
    [[ -n "$_default_ws" ]] && _ws_append_unique "$out_name" "$_default_ws"
  done
}

# ---------------------------------------------------------------------------
# ws_has_package workspace package-name
#   Return 0 if package-name exists in workspace/src (matched by <name> tag
#   in package.xml), 1 otherwise.
# ---------------------------------------------------------------------------
ws_has_package() {
  local workspace="$1"
  local package_name="$2"
  local pkg_xml found_name

  [[ -d "$workspace/src" ]] || return 1

  while IFS= read -r -d '' pkg_xml; do
    found_name=$(sed -n 's:.*<name>[[:space:]]*\([^<]*\)[[:space:]]*</name>.*:\1:p' "$pkg_xml" | head -n 1)
    [[ "$found_name" == "$package_name" ]] && return 0
  done < <(find -L "$workspace/src" -type f -name package.xml -print0 2>/dev/null)

  return 1
}

# ---------------------------------------------------------------------------
# ws_resolve_workspaces  selected_ws_array  packages_array  out_ws_array  out_ws_pkgs_assoc
#
#   Resolve the final set of workspaces to operate on, following the
#   hierarchy documented at the top of this file.
#
#   Arguments:
#     selected_ws_array  — name of an array of explicitly supplied -w paths
#                          (may be empty).
#     packages_array     — name of an array of package names (may be empty).
#     out_ws_array       — name of the output array that will receive the
#                          ordered list of workspace paths to operate on.
#     out_ws_pkgs_assoc  — name of the output associative array that maps
#                          workspace → space-separated list of packages for
#                          that workspace.  Only populated when workspace
#                          selection was driven by package lookup (i.e. when
#                          selected_ws_array is empty and packages_array is
#                          non-empty).  Callers should check with
#                          ws_is_pkg_inferred before trusting this field.
#
#   Sets the global-ish variable WS_PKG_INFERRED to "true" when per-workspace
#   package filtering was applied (package-driven selection), "false" otherwise.
#
#   Returns 0 on success.  Prints diagnostics and returns 1 on failure.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034  # out variables are assigned by nameref
ws_resolve_workspaces() {
  local sel_ws_name="$1"
  local sel_pkg_name="$2"
  local out_ws_name="$3"
  local out_ws_pkgs_name="$4"

  local -n _srw_sel_ws="$sel_ws_name"
  local -n _srw_sel_pkg="$sel_pkg_name"
  local -n _srw_out_ws="$out_ws_name"
  local -n _srw_out_pkgs="$out_ws_pkgs_name"

  _srw_out_ws=()
  _srw_out_pkgs=()
  WS_PKG_INFERRED=false

  # ── Level 1: explicit workspaces ─────────────────────────────────────────
  if [[ ${#_srw_sel_ws[@]} -gt 0 ]]; then
    _srw_out_ws=("${_srw_sel_ws[@]}")
    return 0
  fi

  # ── Level 2: package-driven workspace inference ───────────────────────────
  if [[ ${#_srw_sel_pkg[@]} -gt 0 ]]; then
    WS_PKG_INFERRED=true
    local -a _candidate_ws=()
    ws_detect_from_env _candidate_ws

    local pkg ws found_any
    local -a _unresolved=()
    for pkg in "${_srw_sel_pkg[@]}"; do
      found_any=false
      for ws in "${_candidate_ws[@]}"; do
        if ws_has_package "$ws" "$pkg"; then
          _ws_append_unique "$out_ws_name" "$ws"
          if [[ " ${_srw_out_pkgs[ws]:-} " != *" $pkg "* ]]; then
            _srw_out_pkgs[ws]="${_srw_out_pkgs[ws]:-} $pkg"
          fi
          found_any=true
        fi
      done
      [[ "$found_any" == false ]] && _unresolved+=("$pkg")
    done

    if [[ ${#_srw_out_ws[@]} -eq 0 ]]; then
      echo "Error: could not find package(s) in any detected workspace." >&2
      echo "  Packages: ${_srw_sel_pkg[*]}" >&2
      if [[ ${#_candidate_ws[@]} -gt 0 ]]; then
        echo "  Searched: ${_candidate_ws[*]}" >&2
      else
        echo "  No workspaces detected from ROS_PACKAGE_PATH / COLCON_PREFIX_PATH." >&2
      fi
      echo "  Tip: use -w/--ws to specify a workspace explicitly." >&2
      return 1
    fi

    if [[ ${#_unresolved[@]} -gt 0 ]]; then
      echo "Warning: package(s) not found in any detected workspace: ${_unresolved[*]}" >&2
      echo "  Proceeding with the matched package/workspace pairs only." >&2
    fi

    return 0
  fi

  # ── Levels 3 + 4: no packages and no explicit workspaces ─────────────────
  # Build from all env-detected workspaces (includes defaults via ws_detect_from_env).
  local -a _env_ws=()
  ws_detect_from_env _env_ws
  _srw_out_ws=("${_env_ws[@]}")
  return 0
}

# ---------------------------------------------------------------------------
# ws_is_workspace_sourced workspace
#   Return 0 if the workspace's install/ directory appears in
#   COLCON_PREFIX_PATH (i.e. the workspace has been sourced), 1 otherwise.
# ---------------------------------------------------------------------------
ws_is_workspace_sourced() {
  local workspace="$1"
  local entry
  local -a _cpp=()

  [[ -n "${COLCON_PREFIX_PATH:-}" ]] || return 1

  IFS=':' read -r -a _cpp <<< "$COLCON_PREFIX_PATH"
  for entry in "${_cpp[@]}"; do
    entry="${entry/#\~/$HOME}"
    # Normalise: strip trailing slashes and /install suffix variants.
    local ws_root="${entry%%/install*}"
    [[ "$ws_root" == "$workspace" ]] && return 0
    # Also match when the entry itself equals workspace/install.
    [[ "$entry" == "$workspace/install" ]] && return 0
  done

  return 1
}

# ---------------------------------------------------------------------------
# ws_is_package_installed workspace package-name
#   Return 0 if workspace/install/<package-name>/ directory exists (the
#   package has been built), 1 otherwise.
# ---------------------------------------------------------------------------
ws_is_package_installed() {
  local workspace="$1"
  local package_name="$2"
  [[ -d "$workspace/install/$package_name" ]]
}

# ---------------------------------------------------------------------------
# ws_list_packages_in_workspace workspace out-array-name
#   Populate the named array with all package names found under workspace/src
#   (enumerated from package.xml <name> tags), sorted alphabetically.
# ---------------------------------------------------------------------------
ws_list_packages_in_workspace() {
  local workspace="$1"
  local out_name="$2"
  local -n _lpw_ref="$out_name"
  local pkg_xml pkg_name

  _lpw_ref=()

  [[ -d "$workspace/src" ]] || return 0

  local -a _unsorted=()
  while IFS= read -r -d '' pkg_xml; do
    pkg_name=$(sed -n 's:.*<name>[[:space:]]*\([^<]*\)[[:space:]]*</name>.*:\1:p' "$pkg_xml" | head -n 1)
    [[ -n "$pkg_name" ]] && _unsorted+=("$pkg_name")
  done < <(find -L "$workspace/src" -type f -name package.xml -print0 2>/dev/null)

  if [[ ${#_unsorted[@]} -gt 0 ]]; then
    mapfile -t _lpw_ref < <(printf '%s\n' "${_unsorted[@]}" | sort -u)
  fi
}

# ---------------------------------------------------------------------------
# ws_package_dir workspace package-name
#   Print the package source directory path for package-name in workspace/src.
#   Returns 0 on success, 1 if package is not found.
# ---------------------------------------------------------------------------
ws_package_dir() {
  local workspace="$1"
  local package_name="$2"
  local pkg_xml found_name

  [[ -d "$workspace/src" ]] || return 1

  while IFS= read -r -d '' pkg_xml; do
    found_name=$(sed -n 's:.*<name>[[:space:]]*\([^<]*\)[[:space:]]*</name>.*:\1:p' "$pkg_xml" | head -n 1)
    if [[ "$found_name" == "$package_name" ]]; then
      dirname "$pkg_xml"
      return 0
    fi
  done < <(find -L "$workspace/src" -type f -name package.xml -print0 2>/dev/null)

  return 1
}

# ---------------------------------------------------------------------------
# ws_package_source_dir_any package-name
#   Print the source directory for package-name from detected workspaces.
#   Returns 0 when found, 1 otherwise.
# ---------------------------------------------------------------------------
ws_package_source_dir_any() {
  local package_name="$1"
  local -a _workspaces=()
  local ws

  ws_detect_from_env _workspaces
  for ws in "${_workspaces[@]}"; do
    if ws_package_dir "$ws" "$package_name" >/dev/null 2>&1; then
      ws_package_dir "$ws" "$package_name"
      return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------
# ws_package_install_prefix package-name
#   Print install prefix for package-name when available.
#   Returns 0 when found, 1 otherwise.
# ---------------------------------------------------------------------------
ws_package_install_prefix() {
  local package_name="$1"
  local prefix=""
  local -a _workspaces=()
  local ws

  if command -v ros2 >/dev/null 2>&1; then
    prefix=$(ros2 pkg prefix "$package_name" 2>/dev/null || true)
    if [[ -n "$prefix" && -d "$prefix" ]]; then
      printf '%s\n' "$prefix"
      return 0
    fi
  fi

  ws_detect_from_env _workspaces
  for ws in "${_workspaces[@]}"; do
    if [[ -d "$ws/install/$package_name" ]]; then
      printf '%s\n' "$ws/install/$package_name"
      return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------
# ws_package_launch_dir_from_source source-dir
#   Print source launch directory path if present.
# ---------------------------------------------------------------------------
ws_package_launch_dir_from_source() {
  local source_dir="$1"
  if [[ -d "$source_dir/launch" ]]; then
    printf '%s\n' "$source_dir/launch"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# ws_package_launch_dir_from_install install-prefix package-name
#   Print installed launch directory path if present.
# ---------------------------------------------------------------------------
ws_package_launch_dir_from_install() {
  local install_prefix="$1"
  local package_name="$2"
  local launch_dir=""

  launch_dir="$install_prefix/share/$package_name/launch"
  if [[ -d "$launch_dir" ]]; then
    printf '%s\n' "$launch_dir"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# ws_find_launchfile launch-dir launch-name
#   Print matching launch file path in launch-dir.
#   Returns 0 when found, 1 otherwise.
# ---------------------------------------------------------------------------
ws_find_launchfile() {
  local launch_dir="$1"
  local launch_name="$2"
  local candidate
  local -a suffixes=("" ".launch.py" ".launch.xml" ".launch.yaml" ".launch.yml")
  local suffix

  [[ -d "$launch_dir" ]] || return 1

  for suffix in "${suffixes[@]}"; do
    candidate="$launch_dir/$launch_name$suffix"
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  candidate=$(find "$launch_dir" -type f -name "$launch_name" -print -quit 2>/dev/null || true)
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# ws_list_installed_launchfile_basenames package-name
#   Print launch file basenames for package-name, one per line.
#   Prefers install tree; falls back to source tree for non-installed packages.
# ---------------------------------------------------------------------------
ws_list_installed_launchfile_basenames() {
  local package_name="$1"
  local install_prefix="" launch_dir=""
  local _lf_pat='\( -name *.launch.py -o -name *.launch.xml -o -name *.launch.yaml -o -name *.launch.yml \)'

  install_prefix=$(ws_package_install_prefix "$package_name" 2>/dev/null || true)
  if [[ -n "$install_prefix" ]]; then
    launch_dir=$(ws_package_launch_dir_from_install "$install_prefix" "$package_name" 2>/dev/null || true)
    if [[ -n "$launch_dir" ]]; then
      find "$launch_dir" \( -type f -o -type l \) \( -name '*.launch.py' -o -name '*.launch.xml' -o -name '*.launch.yaml' -o -name '*.launch.yml' \) -printf '%f\n' 2>/dev/null | sort -u
      return 0
    fi
  fi

  # Fallback: source tree.
  local source_dir=""
  source_dir=$(ws_package_source_dir_any "$package_name" 2>/dev/null || true)
  [[ -n "$source_dir" ]] || return 0
  local src_launch_dir="$source_dir/launch"
  [[ -d "$src_launch_dir" ]] || return 0
  find "$src_launch_dir" \( -type f -o -type l \) \( -name '*.launch.py' -o -name '*.launch.xml' -o -name '*.launch.yaml' -o -name '*.launch.yml' \) -printf '%f\n' 2>/dev/null | sort -u
}

# ---------------------------------------------------------------------------
# ws_package_executable_dir_from_install install-prefix package-name
#   Print installed executable directory path if present.
# ---------------------------------------------------------------------------
ws_package_executable_dir_from_install() {
  local install_prefix="$1"
  local package_name="$2"
  local exe_dir=""

  exe_dir="$install_prefix/lib/$package_name"
  if [[ -d "$exe_dir" ]]; then
    printf '%s\n' "$exe_dir"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# ws_find_executable exe-dir executable-name
#   Print matching executable path from exe-dir.
#   Returns 0 when found, 1 otherwise.
# ---------------------------------------------------------------------------
ws_find_executable() {
  local exe_dir="$1"
  local exe_name="$2"
  local candidate=""

  [[ -d "$exe_dir" ]] || return 1

  candidate="$exe_dir/$exe_name"
  if [[ -f "$candidate" || -L "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate=$(find "$exe_dir" -maxdepth 1 \( -type f -o -type l \) -name "$exe_name" -print -quit 2>/dev/null || true)
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# ws_find_named_file_in_dirs file-name dir...
#   Print the first matching file path for file-name across dir arguments.
#   Returns 0 when found, 1 otherwise.
# ---------------------------------------------------------------------------
ws_find_named_file_in_dirs() {
  local file_name="$1"
  shift
  local dir candidate

  for dir in "$@"; do
    [[ -d "$dir" ]] || continue

    candidate="$dir/$file_name"
    if [[ -f "$candidate" || -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi

    candidate=$(find "$dir" \( -type f -o -type l \) -name "$file_name" -print -quit 2>/dev/null || true)
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------
# ws_list_installed_executable_basenames package-name
#   Print executable basenames for package-name, one per line.
#   Prefers install tree; falls back to source tree (scripts/ and bin/).
# ---------------------------------------------------------------------------
ws_list_installed_executable_basenames() {
  local package_name="$1"
  local install_prefix="" exe_dir=""

  install_prefix=$(ws_package_install_prefix "$package_name" 2>/dev/null || true)
  if [[ -n "$install_prefix" ]]; then
    exe_dir=$(ws_package_executable_dir_from_install "$install_prefix" "$package_name" 2>/dev/null || true)
    if [[ -n "$exe_dir" ]]; then
      find "$exe_dir" -maxdepth 1 \( -type f -o -type l \) -printf '%f\n' 2>/dev/null | sort -u
      return 0
    fi
  fi

  # Fallback: source tree scripts/ and bin/.
  local source_dir=""
  source_dir=$(ws_package_source_dir_any "$package_name" 2>/dev/null || true)
  [[ -n "$source_dir" ]] || return 0
  for _sd in "$source_dir/scripts" "$source_dir/bin"; do
    [[ -d "$_sd" ]] && find "$_sd" -maxdepth 1 \( -type f -o -type l \) -printf '%f\n' 2>/dev/null
  done | sort -u
}

# ---------------------------------------------------------------------------
# ws_list_installed_config_basenames package-name
#   Print config file basenames for package-name, one per line.
#   Prefers install tree; falls back to source tree (config/ and params/).
# ---------------------------------------------------------------------------
ws_list_installed_config_basenames() {
  local package_name="$1"
  local install_prefix="" share_dir="" dir
  local -a candidate_dirs=()

  install_prefix=$(ws_package_install_prefix "$package_name" 2>/dev/null || true)
  if [[ -n "$install_prefix" ]]; then
    share_dir="$install_prefix/share/$package_name"
    if [[ -d "$share_dir" ]]; then
      candidate_dirs=("$share_dir/config" "$share_dir/params")
      local _found=false
      local -a _cfg_basenames=()
      for dir in "${candidate_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
          _found=true
          while IFS= read -r _base; do
            [[ -n "$_base" ]] && _cfg_basenames+=("$_base")
          done < <(find "$dir" \( -type f -o -type l \) -printf '%f\n' 2>/dev/null)
        fi
      done
      if [[ "$_found" == true ]]; then
        printf '%s\n' "${_cfg_basenames[@]}" | sort -u
        return 0
      fi
    fi
  fi

  # Fallback: source tree config/ and params/.
  local source_dir=""
  source_dir=$(ws_package_source_dir_any "$package_name" 2>/dev/null || true)
  [[ -n "$source_dir" ]] || return 0
  for dir in "$source_dir/config" "$source_dir/params"; do
    [[ -d "$dir" ]] && find "$dir" \( -type f -o -type l \) -printf '%f\n' 2>/dev/null
  done | sort -u
}

# ---------------------------------------------------------------------------
# ws_resolve_package_paths package-name out-source-path out-install-path
#   Resolve source and install paths for a package.
#   Sets both out variables; values are "not-found" / "not-installed" on
#   failure.  Also sets symlink metadata globals:
#     WS_RESOLVE_SOURCE_IS_SYMLINK, WS_RESOLVE_SOURCE_SYMLINK_TARGET
#     WS_RESOLVE_INSTALL_IS_SYMLINK, WS_RESOLVE_INSTALL_SYMLINK_TARGET
# ---------------------------------------------------------------------------
ws_resolve_package_paths() {
  local package_name="$1"
  local out_source_name="$2"
  local out_install_name="$3"
  local -n _rpp_src_ref="$out_source_name"
  local -n _rpp_inst_ref="$out_install_name"

  _rpp_src_ref="not-found"
  _rpp_inst_ref="not-installed"
  # shellcheck disable=SC2034
  WS_RESOLVE_SOURCE_IS_SYMLINK="no"
  # shellcheck disable=SC2034
  WS_RESOLVE_SOURCE_SYMLINK_TARGET="n/a"
  # shellcheck disable=SC2034
  WS_RESOLVE_INSTALL_IS_SYMLINK="no"
  # shellcheck disable=SC2034
  WS_RESOLVE_INSTALL_SYMLINK_TARGET="n/a"

  if resolved_source=$(ws_package_source_dir_any "$package_name" 2>/dev/null); then
    _rpp_src_ref="$resolved_source"
    if [[ -L "$resolved_source" ]]; then
      # shellcheck disable=SC2034
      WS_RESOLVE_SOURCE_IS_SYMLINK="yes"
      # shellcheck disable=SC2034
      WS_RESOLVE_SOURCE_SYMLINK_TARGET=$(readlink -f "$resolved_source" 2>/dev/null \
        || readlink "$resolved_source" 2>/dev/null || echo "n/a")
    fi
  fi

  if resolved_install=$(ws_package_install_prefix "$package_name" 2>/dev/null); then
    _rpp_inst_ref="$resolved_install"
    if [[ -L "$resolved_install" ]]; then
      # shellcheck disable=SC2034
      WS_RESOLVE_INSTALL_IS_SYMLINK="yes"
      # shellcheck disable=SC2034
      WS_RESOLVE_INSTALL_SYMLINK_TARGET=$(readlink -f "$resolved_install" 2>/dev/null \
        || readlink "$resolved_install" 2>/dev/null || echo "n/a")
    fi
  fi
}

# ---------------------------------------------------------------------------
# ws_resolve_artifact package-name artifact-type artifact-name
#                       out-source-path out-install-path
#   Resolve source and install paths for an artifact of a package.
#   artifact-type: launch | exe | config
#   Caller must have already resolved package source (in $5) and install
#   (in $6) paths — pass them as the 5th and 6th arguments.
#   Usage:
#     ws_resolve_artifact PKG TYPE NAME SRC_PKG INST_PKG OUT_SRC OUT_INST
# ---------------------------------------------------------------------------
ws_resolve_artifact() {
  local package_name="$1"
  local artifact_type="$2"
  local artifact_name="$3"
  local source_path="$4"
  local install_path="$5"
  local out_src_name="$6"
  local out_inst_name="$7"
  local -n _ra_src_ref="$out_src_name"
  local -n _ra_inst_ref="$out_inst_name"

  _ra_src_ref="not-found"
  _ra_inst_ref="not-found"

  case "$artifact_type" in
    launch)
      if [[ "$source_path" != "not-found" ]]; then
        if src_launch_dir=$(ws_package_launch_dir_from_source "$source_path" 2>/dev/null); then
          if found=$(ws_find_launchfile "$src_launch_dir" "$artifact_name" 2>/dev/null); then
            _ra_src_ref="$found"
          fi
        fi
      fi
      if [[ "$install_path" != "not-installed" ]]; then
        if inst_launch_dir=$(ws_package_launch_dir_from_install "$install_path" "$package_name" 2>/dev/null); then
          if found=$(ws_find_launchfile "$inst_launch_dir" "$artifact_name" 2>/dev/null); then
            _ra_inst_ref="$found"
          fi
        fi
      fi
      ;;
    exe)
      if [[ "$source_path" != "not-found" ]]; then
        local _found_src=""
        if [[ -f "$source_path/scripts/$artifact_name" || -L "$source_path/scripts/$artifact_name" ]]; then
          _found_src="$source_path/scripts/$artifact_name"
        elif [[ -f "$source_path/bin/$artifact_name" || -L "$source_path/bin/$artifact_name" ]]; then
          _found_src="$source_path/bin/$artifact_name"
        else
          _found_src=$(find "$source_path" \
            \( -path "$source_path/scripts/*" -o -path "$source_path/bin/*" \) \
            \( -type f -o -type l \) -name "$artifact_name" -print -quit 2>/dev/null || true)
        fi
        [[ -n "$_found_src" ]] && _ra_src_ref="$_found_src"
      fi
      if [[ "$install_path" != "not-installed" ]]; then
        if inst_exe_dir=$(ws_package_executable_dir_from_install "$install_path" "$package_name" 2>/dev/null); then
          if found=$(ws_find_executable "$inst_exe_dir" "$artifact_name" 2>/dev/null); then
            _ra_inst_ref="$found"
          fi
        fi
      fi
      ;;
    config)
      if [[ "$source_path" != "not-found" ]]; then
        if found=$(ws_find_named_file_in_dirs "$artifact_name" \
            "$source_path/config" "$source_path/params" 2>/dev/null); then
          _ra_src_ref="$found"
        fi
      fi
      if [[ "$install_path" != "not-installed" ]]; then
        if found=$(ws_find_named_file_in_dirs "$artifact_name" \
            "$install_path/share/$package_name/config" \
            "$install_path/share/$package_name/params" 2>/dev/null); then
          _ra_inst_ref="$found"
        fi
      fi
      ;;
    *)
      echo "ws_resolve_artifact: unknown artifact type '$artifact_type'" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# ws_resolve_artifact_symlink_state install-path out-is-symlink out-target
#   Given an artifact install path, checks if it's a symlink and sets the
#   two output variables (is_symlink=yes/no/n/a, target).
# ---------------------------------------------------------------------------
ws_resolve_artifact_symlink_state() {
  local install_item_path="$1"
  local out_is_symlink_name="$2"
  local out_target_name="$3"
  local -n _rass_is_ref="$out_is_symlink_name"
  local -n _rass_tgt_ref="$out_target_name"

  if [[ "$install_item_path" == "not-found" || "$install_item_path" == "not-installed" ]]; then
    _rass_is_ref="n/a"
    _rass_tgt_ref="n/a"
    return 0
  fi

  if [[ -L "$install_item_path" ]]; then
    _rass_is_ref="yes"
    _rass_tgt_ref=$(readlink -f "$install_item_path" 2>/dev/null \
      || readlink "$install_item_path" 2>/dev/null || echo "n/a")
  else
    _rass_is_ref="no"
    _rass_tgt_ref="n/a"
  fi
}

# ---------------------------------------------------------------------------
# ws_artifact_points_to_source source-path install-path
#   Echoes "yes", "no", or "n/a" to stdout.
# ---------------------------------------------------------------------------
ws_artifact_points_to_source() {
  local source_item_path="$1"
  local install_item_path="$2"

  if [[ "$source_item_path" == "not-found" || "$install_item_path" == "not-found" ]]; then
    echo "n/a"
    return 0
  fi

  local rcmp_src rcmp_inst
  rcmp_src=$(readlink -f "$source_item_path" 2>/dev/null || echo "$source_item_path")
  rcmp_inst=$(readlink -f "$install_item_path" 2>/dev/null || echo "$install_item_path")
  if [[ "$rcmp_src" == "$rcmp_inst" ]]; then
    echo "yes"
  else
    echo "no"
  fi
}
