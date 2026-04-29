#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=ws_lib.sh
source "$SCRIPT_DIR/ws_lib.sh"

BUILD_SCRIPT=""
if [[ -x "$SCRIPT_DIR/ws-build" ]]; then
  BUILD_SCRIPT="$SCRIPT_DIR/ws-build"
elif [[ -x "$SCRIPT_DIR/ws_build.sh" ]]; then
  BUILD_SCRIPT="$SCRIPT_DIR/ws_build.sh"
fi

CLEAN_SCRIPT=""
if [[ -x "$SCRIPT_DIR/ws-clean" ]]; then
  CLEAN_SCRIPT="$SCRIPT_DIR/ws-clean"
elif [[ -x "$SCRIPT_DIR/ws_clean.sh" ]]; then
  CLEAN_SCRIPT="$SCRIPT_DIR/ws_clean.sh"
fi

LIST_SCRIPT=""
if [[ -x "$SCRIPT_DIR/ws-list" ]]; then
  LIST_SCRIPT="$SCRIPT_DIR/ws-list"
elif [[ -x "$SCRIPT_DIR/ws_list.sh" ]]; then
  LIST_SCRIPT="$SCRIPT_DIR/ws_list.sh"
fi

OPEN_SCRIPT=""
if [[ -x "$SCRIPT_DIR/ws-open" ]]; then
  OPEN_SCRIPT="$SCRIPT_DIR/ws-open"
elif [[ -x "$SCRIPT_DIR/ws_open.sh" ]]; then
  OPEN_SCRIPT="$SCRIPT_DIR/ws_open.sh"
fi

CONFIG_SCRIPT=""
if [[ -x "$SCRIPT_DIR/ws-config" ]]; then
  CONFIG_SCRIPT="$SCRIPT_DIR/ws-config"
elif [[ -x "$SCRIPT_DIR/ws_config.sh" ]]; then
  CONFIG_SCRIPT="$SCRIPT_DIR/ws_config.sh"
fi

WHICH_SCRIPT=""
if [[ -x "$SCRIPT_DIR/ws-which" ]]; then
  WHICH_SCRIPT="$SCRIPT_DIR/ws-which"
elif [[ -x "$SCRIPT_DIR/ws_which.sh" ]]; then
  WHICH_SCRIPT="$SCRIPT_DIR/ws_which.sh"
fi

print_usage() {
  ws_print_main_help
}

if [[ -z "${1:-}" ]]; then
  print_usage
  exit 0
elif [[ "${1:-}" == "cd" ]]; then
  echo "Error: 'ws cd' must run as a shell function from ~/.bashrc to change your current directory."
  echo "Run ./link_tools.sh, then source ~/.bashrc and use: ws cd <package_name>"
  exit 2
elif ws_is_help_token "${1:-}"; then
  print_usage
  exit 0
elif [[ "${1:-}" == "clean" ]]; then
  shift
  if [[ -z "$CLEAN_SCRIPT" ]]; then
    echo "Error: could not find executable clean helper next to ws." >&2
    echo "Checked: $SCRIPT_DIR/ws-clean and $SCRIPT_DIR/ws_clean.sh" >&2
    exit 1
  fi
  exec "$CLEAN_SCRIPT" "$@"
elif [[ "${1:-}" == "list" ]]; then
  shift
  if [[ -z "$LIST_SCRIPT" ]]; then
    echo "Error: could not find executable list helper next to ws." >&2
    echo "Checked: $SCRIPT_DIR/ws-list and $SCRIPT_DIR/ws_list.sh" >&2
    exit 1
  fi
  exec "$LIST_SCRIPT" "$@"
elif [[ "${1:-}" == "open" ]]; then
  shift
  if [[ -z "$OPEN_SCRIPT" ]]; then
    echo "Error: could not find executable open helper next to ws." >&2
    echo "Checked: $SCRIPT_DIR/ws-open and $SCRIPT_DIR/ws_open.sh" >&2
    exit 1
  fi
  exec "$OPEN_SCRIPT" "$@"
elif [[ "${1:-}" == "config" ]]; then
  shift
  if [[ -z "$CONFIG_SCRIPT" ]]; then
    echo "Error: could not find executable config helper next to ws." >&2
    echo "Checked: $SCRIPT_DIR/ws-config and $SCRIPT_DIR/ws_config.sh" >&2
    exit 1
  fi
  exec "$CONFIG_SCRIPT" "$@"
elif [[ "${1:-}" == "which" ]]; then
  shift
  if [[ -z "$WHICH_SCRIPT" ]]; then
    echo "Error: could not find executable which helper next to ws." >&2
    echo "Checked: $SCRIPT_DIR/ws-which and $SCRIPT_DIR/ws_which.sh" >&2
    exit 1
  fi
  exec "$WHICH_SCRIPT" "$@"
fi

if [[ -z "$BUILD_SCRIPT" ]]; then
  echo "Error: could not find executable build helper next to ws." >&2
  echo "Checked: $SCRIPT_DIR/ws-build and $SCRIPT_DIR/ws_build.sh" >&2
  exit 1
fi

if [[ "${1:-}" == "build" ]]; then
  shift
fi

exec "$BUILD_SCRIPT" "$@"
