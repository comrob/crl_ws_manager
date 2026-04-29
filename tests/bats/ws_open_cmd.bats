#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
}

@test "ws open follows source symlink path in package mode" {
  local ws="$TEST_HOME/ws_open"
  local external="$TEST_HOME/external/open_pkg"
  mkdir -p "$ws/src"
  make_pkg_at "$external" "open_pkg"
  ln -s "$external" "$ws/src/open_pkg"
  set_test_editor_echo

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" WS_EDITOR_PROGRAM="$WS_EDITOR_PROGRAM" bash "$REPO_ROOT/bin/ws_open.sh" open_pkg
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opening: $external"* ]]
}

@test "ws open --install fails for package that is not installed" {
  local ws="$TEST_HOME/ws_open_noinst"
  make_pkg "$ws" "demo_pkg"
  set_test_editor_echo

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" WS_EDITOR_PROGRAM="$WS_EDITOR_PROGRAM" bash "$REPO_ROOT/bin/ws_open.sh" --install demo_pkg
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: package 'demo_pkg' is not installed."* ]]
}

@test "ws open launch artifact works for source-only package" {
  local ws="$TEST_HOME/ws_open_src"
  make_pkg "$ws" "demo_pkg"
  mkdir -p "$ws/src/demo_pkg/launch"
  touch "$ws/src/demo_pkg/launch/demo.launch.py"
  set_test_editor_echo

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" WS_EDITOR_PROGRAM="$WS_EDITOR_PROGRAM" bash "$REPO_ROOT/bin/ws_open.sh" demo_pkg --launch demo.launch.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opening: $ws/src/demo_pkg/launch/demo.launch.py"* ]]
}
