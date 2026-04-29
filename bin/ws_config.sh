#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=lib/ws_lib.sh
source "$SCRIPT_DIR/../lib/ws_lib.sh"

print_usage() {
  echo "Usage: ws config [command] [args]"
  echo ""
  echo "Commands:"
  echo "  show                      Show effective configuration values"
  echo "  path                      Print local config path"
  echo "  init                      Create local config file if missing"
  echo "  edit                      Open local config file in editor"
  echo "  set-editor <program> [args...]"
  echo "                            Set WS_EDITOR_PROGRAM and WS_EDITOR_ARGS"
  echo "  set-build-program <prog>  Set WS_BUILD_PROGRAM"
  echo "  set-build-subcommand <s>  Set WS_BUILD_SUBCOMMAND"
  echo "  set-build-args <args...>  Set WS_BUILD_DEFAULT_ARGS array"
  echo "  require-all <true|false>  Set WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD"
  echo ""
  echo "Examples:"
  echo "  ws config"
  echo "  ws config show"
  echo "  ws config edit"
  echo "  ws config set-editor code --reuse-window"
  echo "  ws config set-build-args --symlink-install --continue-on-error"
  echo "  ws config require-all true"
}

array_to_shell_list() {
  local out=""
  local item
  for item in "$@"; do
    out+=" $(printf '%q' "$item")"
  done
  printf '%s' "${out# }"
}

show_config() {
  ws_load_config
  echo "Config file: $(ws_config_file)"
  echo ""
  echo "WS_BUILD_PROGRAM=$WS_BUILD_PROGRAM"
  echo "WS_BUILD_SUBCOMMAND=$WS_BUILD_SUBCOMMAND"
  echo "WS_BUILD_DEFAULT_ARGS=( $(array_to_shell_list "${WS_BUILD_DEFAULT_ARGS[@]}") )"
  echo "WS_BUILD_PACKAGE_SELECT_FLAG=$WS_BUILD_PACKAGE_SELECT_FLAG"
  echo "WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD=$WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD"
  echo "WS_EDITOR_PROGRAM=$WS_EDITOR_PROGRAM"
  echo "WS_EDITOR_ARGS=( $(array_to_shell_list "${WS_EDITOR_ARGS[@]}") )"
}

if ws_is_help_token "${1:-}"; then
  print_usage
  exit 0
fi

cmd="${1:-show}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  show)
    show_config
    ;;
  path)
    ws_config_file
    ;;
  init)
    ws_init_config_file_if_missing
    echo "Config ready: $(ws_config_file)"
    ;;
  edit)
    ws_init_config_file_if_missing
    editor_cmd=()
    ws_editor_make_command editor_cmd "$(ws_config_file)"
    printf 'Executing:'
    printf ' %q' "${editor_cmd[@]}"
    printf '\n'
    "${editor_cmd[@]}"
    ;;
  set-editor)
    if [[ $# -lt 1 ]]; then
      echo "Error: set-editor requires <program> [args...]" >&2
      exit 1
    fi
    program="$1"
    shift
    ws_upsert_config_assignment "WS_EDITOR_PROGRAM" "WS_EDITOR_PROGRAM=$(printf '%q' "$program")"
    ws_upsert_config_assignment "WS_EDITOR_ARGS" "WS_EDITOR_ARGS=( $(array_to_shell_list "$@") )"
    echo "Updated editor in $(ws_config_file)"
    ;;
  set-build-program)
    if [[ $# -ne 1 ]]; then
      echo "Error: set-build-program requires <program>" >&2
      exit 1
    fi
    ws_upsert_config_assignment "WS_BUILD_PROGRAM" "WS_BUILD_PROGRAM=$(printf '%q' "$1")"
    echo "Updated build program in $(ws_config_file)"
    ;;
  set-build-subcommand)
    if [[ $# -ne 1 ]]; then
      echo "Error: set-build-subcommand requires <subcommand>" >&2
      exit 1
    fi
    ws_upsert_config_assignment "WS_BUILD_SUBCOMMAND" "WS_BUILD_SUBCOMMAND=$(printf '%q' "$1")"
    echo "Updated build subcommand in $(ws_config_file)"
    ;;
  set-build-args)
    if [[ $# -eq 0 ]]; then
      echo "Error: set-build-args requires at least one argument." >&2
      exit 1
    fi
    ws_upsert_config_assignment "WS_BUILD_DEFAULT_ARGS" "WS_BUILD_DEFAULT_ARGS=( $(array_to_shell_list "$@") )"
    echo "Updated build args in $(ws_config_file)"
    ;;
  require-all)
    if [[ $# -ne 1 ]]; then
      echo "Error: require-all requires true|false" >&2
      exit 1
    fi
    if [[ "$1" != "true" && "$1" != "false" ]]; then
      echo "Error: require-all expects true or false." >&2
      exit 1
    fi
    ws_upsert_config_assignment "WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD" "WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD=$1"
    echo "Updated require-all in $(ws_config_file)"
    ;;
  *)
    echo "Error: unknown ws config command '$cmd'" >&2
    print_usage >&2
    exit 1
    ;;
esac
