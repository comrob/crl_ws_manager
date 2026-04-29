#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
}

@test "ws-cd-resolve resolves source and install paths" {
  local ws="$TEST_HOME/ws_a"
  make_pkg "$ws" "demo_pkg"
  mkdir -p "$ws/install/demo_pkg/share/demo_pkg"

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" bash "$REPO_ROOT/bin/ws_cd_resolve.sh" demo_pkg
  [ "$status" -eq 0 ]
  [ "$output" = "$ws/src/demo_pkg" ]

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" bash "$REPO_ROOT/bin/ws_cd_resolve.sh" --install demo_pkg
  [ "$status" -eq 0 ]
  [ "$output" = "$ws/install/demo_pkg" ]
}

@test "ws-cd-resolve follows source symlink to real path" {
  local ws="$TEST_HOME/ws_symlink"
  local external="$TEST_HOME/external/symlinked_pkg"
  mkdir -p "$ws/src"
  make_pkg_at "$external" "symlinked_pkg"
  ln -s "$external" "$ws/src/symlinked_pkg"

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" bash "$REPO_ROOT/bin/ws_cd_resolve.sh" symlinked_pkg
  [ "$status" -eq 0 ]
  [ "$output" = "$external" ]
}

@test "ws-cd-resolve duplicate package prefers first workspace in env order" {
  local ws_a="$TEST_HOME/ws_a"
  local ws_b="$TEST_HOME/ws_b"
  make_pkg "$ws_a" "dup_pkg"
  make_pkg "$ws_b" "dup_pkg"

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws_b/src:$ws_a/src" bash "$REPO_ROOT/bin/ws_cd_resolve.sh" dup_pkg
  [ "$status" -eq 0 ]
  [ "$output" = "$ws_b/src/dup_pkg" ]
}
