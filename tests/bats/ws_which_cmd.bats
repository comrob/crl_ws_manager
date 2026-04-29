#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
}

@test "ws which -m reports source symlink metadata" {
  local ws="$TEST_HOME/ws_which"
  local external="$TEST_HOME/external/which_pkg"
  mkdir -p "$ws/src"
  make_pkg_at "$external" "which_pkg"
  ln -s "$external" "$ws/src/which_pkg"

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" bash "$REPO_ROOT/bin/ws_which.sh" -m which_pkg
  [ "$status" -eq 0 ]
  [[ "$output" == *"package.source_is_symlink: yes"* ]]
  [[ "$output" == *"package.source_symlink_target: $external"* ]]
  [[ "$output" == *"package.install: not-installed"* ]]
}

@test "ws which --complete-launch falls back to source tree for non-installed package" {
  local ws="$TEST_HOME/ws_which_launch"
  make_pkg "$ws" "demo_pkg"
  mkdir -p "$ws/src/demo_pkg/launch"
  touch "$ws/src/demo_pkg/launch/example.launch.py"

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" bash "$REPO_ROOT/bin/ws_which.sh" --complete-launch demo_pkg
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.launch.py"* ]]
}
