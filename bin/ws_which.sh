#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=lib/ws_lib.sh
source "$SCRIPT_DIR/../lib/ws_lib.sh"

if [[ -t 1 ]]; then
  _C_BLUE=$'\033[0;34m'
  _C_RESET=$'\033[0m'
else
  _C_BLUE=''
  _C_RESET=''
fi

print_usage() {
  echo "Usage: ws which <package_name> [launchfile]"
  echo "       ws which <package_name> --launch <launchfile>"
  echo "       ws which <package_name> --exe <executable>"
  echo "       ws which <package_name> --config <config-file>"
  echo ""
  echo "Show source/install package paths and optional artifact file paths."
  echo ""
  echo "Options:"
  echo "  -l, --launch <file>   Resolve this launch file in source/install trees"
  echo "  -e, --exe <name>      Resolve this executable in source/install trees"
  echo "  -c, --config <file>   Resolve this config file in source/install trees"
  echo "  -m, --machine         Machine-friendly key=value-like output"
  echo "  -h, --help, help      Show this help"
  echo ""
  echo "Examples:"
  echo "  ws which my_pkg"
  echo "  ws which my_pkg my_launch.launch.py"
  echo "  ws which my_pkg --launch my_launch.launch.py"
  echo "  ws which my_pkg --exe my_node"
  echo "  ws which my_pkg --config params.yaml"
}

if ws_is_help_token "${1:-}"; then
  print_usage
  exit 0
fi

# Internal completion helper for ws_manager.bash.
if [[ "${1:-}" == "--complete-launch" ]]; then
  if [[ -n "${2:-}" ]]; then
    ws_list_installed_launchfile_basenames "$2"
  fi
  exit 0
fi

if [[ "${1:-}" == "--complete-exe" ]]; then
  if [[ -n "${2:-}" ]]; then
    ws_list_installed_executable_basenames "$2"
  fi
  exit 0
fi

if [[ "${1:-}" == "--complete-config" ]]; then
  if [[ -n "${2:-}" ]]; then
    ws_list_installed_config_basenames "$2"
  fi
  exit 0
fi

package_name=""
launch_name=""
exe_name=""
config_name=""
machine_mode=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    help|-h|--help)
      print_usage
      exit 0
      ;;
    -l|--launch)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a launch file name." >&2
        exit 1
      fi
      launch_name="$2"
      shift 2
      ;;
    -e|--exe)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires an executable name." >&2
        exit 1
      fi
      exe_name="$2"
      shift 2
      ;;
    -c|--config)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a config file name." >&2
        exit 1
      fi
      config_name="$2"
      shift 2
      ;;
    -m|--machine)
      machine_mode=true
      shift
      ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      print_usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$package_name" ]]; then
        package_name="$1"
      elif [[ -z "$launch_name" ]]; then
        launch_name="$1"
      else
        echo "Error: unexpected argument '$1'" >&2
        print_usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$package_name" ]]; then
  print_usage
  exit 0
fi

# ── Resolve package paths ──────────────────────────────────────────────────
source_path="not-found"
install_path="not-installed"
ws_resolve_package_paths "$package_name" source_path install_path

_print_artifact_section() {
  # args: label type-key request src inst is_symlink symlink_target points_to_src
  local label="$1" type_key="$2" request="$3"
  local src="$4" inst="$5"
  local is_symlink="$6" symlink_target="$7" points_to_src="$8"

  if [[ "$machine_mode" == true ]]; then
    echo "${type_key}.request: $request"
    echo "${type_key}.source: $src"
    echo "${type_key}.install: $inst"
    echo "${type_key}.install_is_symlink: $is_symlink"
    echo "${type_key}.install_symlink_target: $symlink_target"
    echo "${type_key}.install_points_to_source: $points_to_src"
  else
    echo ""
    echo "$label: $request"
    echo "  Source:  $src"
    if [[ "$inst" == "not-found" ]]; then
      echo "  Install: $inst"
    elif [[ "$is_symlink" == "yes" ]]; then
      echo "  Install: (symlink) $inst ${_C_BLUE}-> $symlink_target${_C_RESET}"
    else
      echo "  Install: $inst"
    fi
    if [[ "$points_to_src" != "n/a" ]]; then
      echo "  Install points to source: $points_to_src"
    fi
  fi
}

if [[ "$machine_mode" == true ]]; then
  echo "package: $package_name"
  echo "package.source: $source_path"
  echo "package.install: $install_path"
  echo "package.source_is_symlink: $WS_RESOLVE_SOURCE_IS_SYMLINK"
  echo "package.source_symlink_target: $WS_RESOLVE_SOURCE_SYMLINK_TARGET"
  echo "package.install_is_symlink: $WS_RESOLVE_INSTALL_IS_SYMLINK"
  echo "package.install_symlink_target: $WS_RESOLVE_INSTALL_SYMLINK_TARGET"
else
  echo "Package: $package_name"
  if [[ "$WS_RESOLVE_SOURCE_IS_SYMLINK" == "yes" ]]; then
    echo "  Source:  (symlink) $source_path ${_C_BLUE}-> $WS_RESOLVE_SOURCE_SYMLINK_TARGET${_C_RESET}"
  else
    echo "  Source:  $source_path"
  fi
  if [[ "$WS_RESOLVE_INSTALL_IS_SYMLINK" == "yes" ]]; then
    echo "  Install: (symlink) $install_path ${_C_BLUE}-> $WS_RESOLVE_INSTALL_SYMLINK_TARGET${_C_RESET}"
  else
    echo "  Install: $install_path"
  fi
fi

[[ -z "$launch_name" && -z "$exe_name" && -z "$config_name" ]] && exit 0

# ── Resolve artifact sections ──────────────────────────────────────────────
for _artifact_spec in \
    "launch:Launch file:$launch_name" \
    "exe:Executable:$exe_name" \
    "config:Config file:$config_name"; do
  _atype="${_artifact_spec%%:*}"
  _rest="${_artifact_spec#*:}"
  _alabel="${_rest%%:*}"
  _aname="${_rest#*:}"

  [[ -z "$_aname" ]] && continue

  _asrc="not-found"
  _ainst="not-found"
  ws_resolve_artifact "$package_name" "$_atype" "$_aname" \
    "$source_path" "$install_path" _asrc _ainst

  _ais_symlink="n/a"
  _asymlink_target="n/a"
  ws_resolve_artifact_symlink_state "$_ainst" _ais_symlink _asymlink_target

  _apoints=$(ws_artifact_points_to_source "$_asrc" "$_ainst")

  _print_artifact_section "$_alabel" "$_atype" "$_aname" \
    "$_asrc" "$_ainst" "$_ais_symlink" "$_asymlink_target" "$_apoints"
done
