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

@test "ws list imports environment from ws env file" {
  local ws="$TEST_HOME/ws_list_cfg_env"
  make_pkg "$ws" "cfg_pkg"
  mkdir -p "$TEST_HOME/.config/crl_ws_manager"
  cat > "$TEST_HOME/.config/crl_ws_manager/ws_env.bash" <<EOF
export ROS_PACKAGE_PATH="$ws/src"
export COLCON_PREFIX_PATH="$ws/install"
EOF

  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_list.sh" -q
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ws sourced"* ]]
  [[ "$output" == *"$ws cfg_pkg not-installed"* ]]
}

@test "ws list loads environment from bashrc" {
  local ws="$TEST_HOME/ws_list_bashrc_env"
  make_pkg "$ws" "bashrc_pkg"
  cat > "$TEST_HOME/.bashrc" <<EOF
export ROS_PACKAGE_PATH="$ws/src"
export COLCON_PREFIX_PATH="$ws/install"
EOF

  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_list.sh" -q
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ws sourced"* ]]
  [[ "$output" == *"$ws bashrc_pkg not-installed"* ]]
}
