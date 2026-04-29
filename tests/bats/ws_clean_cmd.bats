#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
}

@test "ws clean with no args prints usage and exits 0" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_clean.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ws clean"* ]]
}

@test "ws clean for duplicate package cleans both workspaces" {
  local ws_a="$TEST_HOME/ws_a"
  local ws_b="$TEST_HOME/ws_b"
  make_pkg "$ws_a" "dup_pkg"
  make_pkg "$ws_b" "dup_pkg"
  mkdir -p "$ws_a/build/dup_pkg" "$ws_b/build/dup_pkg"

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws_a/src:$ws_b/src" bash "$REPO_ROOT/bin/ws_clean.sh" dup_pkg
  [ "$status" -eq 0 ]
  [ ! -d "$ws_a/build/dup_pkg" ]
  [ ! -d "$ws_b/build/dup_pkg" ]
}
