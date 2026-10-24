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
  echo "  env-path                  Print local environment file path"
  echo "  init                      Create local config file if missing"
  echo "  env-init                  Create local environment file if missing"
  echo "  edit                      Open local config file in editor"
  echo "  env-edit                  Open local environment file in editor"
  echo "  set-editor <program> [args...]"
  echo "                            Set WS_EDITOR_PROGRAM and WS_EDITOR_ARGS"
  echo "  set-build-program <prog>  Set WS_BUILD_PROGRAM"
  echo "  set-build-subcommand <s>  Set WS_BUILD_SUBCOMMAND"
  echo "  set-build-args <args...>  Set WS_BUILD_DEFAULT_ARGS array"
  echo "  set-build-env-command <cmd...>"
  echo "                            Set WS_BUILD_ENV_COMMAND"
  echo "  require-all <true|false>  Set WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD"
  echo "  distcc <command>          Compile through distcc (ws config distcc help)"
  echo ""
  echo "Examples:"
  echo "  ws config"
  echo "  ws config show"
  echo "  ws config edit"
  echo "  ws config env-edit"
  echo "  ws config set-editor code --reuse-window"
  echo "  ws config set-build-env-command jazzy_env"
  echo "  ws config set-build-args --symlink-install --continue-on-error"
  echo "  ws config require-all true"
  echo "  ws config distcc hosts 10.0.0.2/30,lzo"
}

print_distcc_usage() {
  echo "Usage: ws config distcc <command>"
  echo ""
  echo "ws build compiles CMake packages through distcc when it is on: the"
  echo "compiler launcher is distcc, and the job count is the total slots of"
  echo "the hosts that answer. Without an answering host it compiles locally."
  echo ""
  echo "Commands:"
  echo "  on | off                  Set WS_DISTCC"
  echo "  hosts <host>...           Set WS_DISTCC_HOSTS and turn distcc on."
  echo "                            Host syntax: host[:port][/slots][,lzo]"
  echo "                            (,lzo compresses the traffic)"
  echo "  jobs <N|auto>             Set WS_DISTCC_JOBS (auto: total slots)"
  echo "  check                     Check that each host answers and runs the"
  echo "                            same compiler version as this machine"
  echo ""
  echo "One build without distcc: ws build --local <pkg>"
  echo "Turning distcc on or off reconfigures CMake packages and recompiles"
  echo "them; ws build --local and unreachable hosts do not."
}

# Compile a test file locally and on each host; compare the compiler
# identification that GCC and Clang write into the object (.comment).
distcc_check() (
  ws_load_config
  if [[ -z "$WS_DISTCC_HOSTS" ]]; then
    echo "Error: WS_DISTCC_HOSTS is empty (ws config distcc hosts <host>...)." >&2
    return 1
  fi
  local tool
  for tool in distcc readelf; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Error: $tool not found." >&2
      return 1
    fi
  done

  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  printf 'int ws_distcc_check() { return 0; }\n' > "$tmp/check.cpp"
  local compiler="${CXX:-c++}"
  if ! "$compiler" -c "$tmp/check.cpp" -o "$tmp/local.o"; then
    echo "Error: $compiler cannot compile locally." >&2
    return 1
  fi
  local local_id
  local_id="$(readelf -p .comment "$tmp/local.o" | sed -n 's/^ *\[ *[0-9]*\] *//p')"
  echo "WS_DISTCC=$WS_DISTCC"
  echo "Local compiler: $local_id"

  local failed=false entry addr remote_id
  for entry in $WS_DISTCC_HOSTS; do
    if ! addr="$(ws_distcc_host_address "$entry")"; then
      echo "  [SKIP] $entry (not a TCP host)"
      continue
    fi
    # shellcheck disable=SC2086
    if ! ws_distcc_host_reachable $addr; then
      echo "  [FAIL] $entry does not answer (VPN down, firewall, or distccd not running)"
      failed=true
      continue
    fi
    rm -f "$tmp/remote.o"
    if ! DISTCC_HOSTS="$entry" DISTCC_FALLBACK=0 DISTCC_LOG="$tmp/distcc.log" \
        distcc "$compiler" -c "$tmp/check.cpp" -o "$tmp/remote.o" 2>/dev/null; then
      echo "  [FAIL] $entry answers, but did not compile (is this machine in its ALLOWEDNETS?)"
      failed=true
      continue
    fi
    remote_id="$(readelf -p .comment "$tmp/remote.o" | sed -n 's/^ *\[ *[0-9]*\] *//p')"
    if [[ "$remote_id" == "$local_id" ]]; then
      echo "  [OK]   $entry"
    else
      echo "  [FAIL] $entry runs a different compiler: $remote_id"
      failed=true
    fi
  done
  [[ "$failed" == false ]]
)

distcc_command() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    on|off)
      local value=true
      [[ "$sub" == off ]] && value=false
      ws_upsert_config_assignment "WS_DISTCC" "WS_DISTCC=$value"
      echo "distcc $sub in $(ws_config_file)"
      ;;
    hosts)
      if [[ $# -eq 0 ]]; then
        echo "Error: distcc hosts requires at least one host." >&2
        return 1
      fi
      if ! [[ "$*" =~ ^[][A-Za-z0-9.:/,@_+\ -]+$ ]]; then
        echo "Error: unexpected characters in distcc hosts '$*'." >&2
        return 1
      fi
      ws_upsert_config_assignment "WS_DISTCC_HOSTS" "WS_DISTCC_HOSTS=\"$*\""
      ws_upsert_config_assignment "WS_DISTCC" "WS_DISTCC=true"
      echo "distcc on with hosts \"$*\" in $(ws_config_file)"
      ;;
    jobs)
      if [[ $# -ne 1 ]] || ! [[ "$1" =~ ^([0-9]+|auto)$ ]]; then
        echo "Error: distcc jobs requires a number or auto." >&2
        return 1
      fi
      ws_upsert_config_assignment "WS_DISTCC_JOBS" "WS_DISTCC_JOBS=$1"
      echo "Updated distcc jobs in $(ws_config_file)"
      ;;
    check)
      distcc_check
      ;;
    help|-h|--help)
      print_distcc_usage
      ;;
    *)
      echo "Error: unknown ws config distcc command '$sub'" >&2
      print_distcc_usage >&2
      return 1
      ;;
  esac
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
  echo "Env file: $(ws_env_file)"
  echo ""
  echo "Workspace config:"
  echo "  WS_BUILD_PROGRAM=$WS_BUILD_PROGRAM"
  echo "  WS_BUILD_SUBCOMMAND=$WS_BUILD_SUBCOMMAND"
  echo "  WS_BUILD_DEFAULT_ARGS=( $(array_to_shell_list "${WS_BUILD_DEFAULT_ARGS[@]}") )"
  echo "  WS_BUILD_ENV_COMMAND=$(printf '%q' "$WS_BUILD_ENV_COMMAND")"
  echo "  WS_BUILD_PACKAGE_SELECT_FLAG=$WS_BUILD_PACKAGE_SELECT_FLAG"
  echo "  WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD=$WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD"
  echo "  WS_EDITOR_PROGRAM=$WS_EDITOR_PROGRAM"
  echo "  WS_EDITOR_ARGS=( $(array_to_shell_list "${WS_EDITOR_ARGS[@]}") )"
  echo "  WS_DISTCC=$WS_DISTCC"
  echo "  WS_DISTCC_HOSTS=$WS_DISTCC_HOSTS"
  echo "  WS_DISTCC_JOBS=$WS_DISTCC_JOBS"
  echo ""
  echo "Environment file contents:"
  if [[ -f "$(ws_env_file)" ]]; then
    sed 's/^/  /' "$(ws_env_file)"
  else
    echo "  <missing>"
  fi
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
  env-path)
    ws_env_file
    ;;
  init)
    ws_init_config_file_if_missing
    echo "Config ready: $(ws_config_file)"
    ;;
  env-init)
    ws_init_env_file_if_missing
    echo "Env ready: $(ws_env_file)"
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
  env-edit)
    ws_init_env_file_if_missing
    editor_cmd=()
    ws_editor_make_command editor_cmd "$(ws_env_file)"
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
  set-build-env-command)
    if [[ $# -eq 0 ]]; then
      echo "Error: set-build-env-command requires at least one command token." >&2
      exit 1
    fi
    ws_upsert_config_assignment "WS_BUILD_ENV_COMMAND" "WS_BUILD_ENV_COMMAND=$(printf '%q' "$*")"
    echo "Updated build env command in $(ws_config_file)"
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
  distcc)
    distcc_command "$@"
    ;;
  *)
    echo "Error: unknown ws config command '$cmd'" >&2
    print_usage >&2
    exit 1
    ;;
esac
