#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
}

@test "ws list -q shows package install state and symlink target" {
  local ws="$TEST_HOME/ws_list"
  local external="$TEST_HOME/external/symlinked_pkg"
  mkdir -p "$ws/src"
  make_pkg_at "$external" "symlinked_pkg"
  ln -s "$external" "$ws/src/symlinked_pkg"

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" bash "$REPO_ROOT/bin/ws_list.sh" -q
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ws symlinked_pkg not-installed symlink=$external"* ]]
}

@test "ws list --installed filters out non-built packages" {
  local ws="$TEST_HOME/ws_list_inst"
  make_pkg "$ws" "built_pkg"
  make_pkg "$ws" "src_only_pkg"
  mkdir -p "$ws/install/built_pkg"

  run env HOME="$TEST_HOME" ROS_PACKAGE_PATH="$ws/src" bash "$REPO_ROOT/bin/ws_list.sh" --installed -q
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ws built_pkg installed"* ]]
  [[ "$output" != *"src_only_pkg"* ]]
}
