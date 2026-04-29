#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
}

@test "ws build with no args prints usage when require-all is true" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_build.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ws build"* ]]
}

@test "ws build for duplicate package builds both matching workspaces" {
  local ws_a="$TEST_HOME/ws_a"
  local ws_b="$TEST_HOME/ws_b"
  make_pkg "$ws_a" "dup_pkg"
  make_pkg "$ws_b" "dup_pkg"

  run env \
    HOME="$TEST_HOME" \
    ROS_PACKAGE_PATH="$ws_a/src:$ws_b/src" \
    ROS_DISTRO="__test_no_ros_setup__" \
    WS_BUILD_PROGRAM="echo" \
    WS_BUILD_SUBCOMMAND="" \
    bash "$REPO_ROOT/bin/ws_build.sh" dup_pkg

  [ "$status" -eq 0 ]
  [[ "$output" == *"Workspace: $ws_a"* ]]
  [[ "$output" == *"Workspace: $ws_b"* ]]
  [[ "$output" == *"dup_pkg"* ]]
}
