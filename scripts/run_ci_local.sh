#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$REPO_ROOT"

CI_TMP_ROOT="${WS_CI_TMP_ROOT:-/tmp/ws_manager_ci_local}"
export HOME="$CI_TMP_ROOT/home"
export ROS_DISTRO="${ROS_DISTRO:-jazzy}"

log() {
  printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
}

log "Validating required local dependencies"
require_cmd bash
require_cmd make
require_cmd python3
require_cmd bats

log "Preparing mock workspaces (matches CI)"
rm -rf "$CI_TMP_ROOT"
mkdir -p "$HOME"
mkdir -p "$HOME/ros2_ws/src"
mkdir -p "$HOME/dev_ws/src"
log "Fixture root: $CI_TMP_ROOT"
find "$CI_TMP_ROOT" -maxdepth 3 -type d | sort

log "Checking shell syntax"
bash -n bin/*.sh
bash -n lib/ws_lib.sh
bash -n completion/ws_manager.bash
bash -n install.sh

log "Installing ws_manager"
make install

log "Running smoke commands"
# shellcheck disable=SC1090
source "$HOME/.bashrc"
ws --version
ws build --help
ws-cd-resolve --help
ws doctor

log "Running bats tests"
bats tests/bats/*.bats

log "Running uninstall smoke"
make uninstall

log "Local CI run completed successfully"
