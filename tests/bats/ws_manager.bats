#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME"
}

make_pkg() {
  local ws_root="$1"
  local pkg="$2"
  mkdir -p "$ws_root/src/$pkg"
  cat > "$ws_root/src/$pkg/package.xml" <<EOF
<package format="3">
  <name>$pkg</name>
  <version>0.0.1</version>
  <description>test package</description>
  <maintainer email="test@example.com">test</maintainer>
  <license>MIT</license>
</package>
EOF
}

@test "ws cd --help exits successfully from binary wrapper" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_manager.sh" cd --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ws cd"* ]]
}

@test "ws shell wrapper delegates build via PATH-resolved ws executable" {
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  cat > "$BATS_TEST_TMPDIR/fakebin/ws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
  chmod +x "$BATS_TEST_TMPDIR/fakebin/ws"

  run env HOME="$TEST_HOME" PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" bash -lc '
    source "$0/completion/ws_manager.bash"
    ws build demo_pkg
  ' "$REPO_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"build demo_pkg"* ]]
}

@test "ws config setters replace existing keys (no duplicates)" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" set-build-program colcon
  [ "$status" -eq 0 ]

  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" set-build-program my_colcon
  [ "$status" -eq 0 ]

  cfg="$TEST_HOME/.config/crl_ws_manager/ws_config.bash"
  [ -f "$cfg" ]

  run bash -lc "grep -c '^WS_BUILD_PROGRAM=' '$cfg'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep '^WS_BUILD_PROGRAM=' '$cfg'"
  [ "$status" -eq 0 ]
  [[ "$output" == "WS_BUILD_PROGRAM=my_colcon" ]]
}

@test "ws_detect_from_env includes configured default workspaces" {
  run env HOME="$TEST_HOME" bash -lc '
    source "$1/lib/ws_lib.sh"
    WS_DEFAULT_WORKSPACES=("$HOME/ros2_ws" "$HOME/dev_ws")
    mkdir -p "$HOME/ros2_ws/src" "$HOME/dev_ws/src"
    ws_detect_from_env out
    printf "%s\n" "${out[@]}"
  ' _ "$REPO_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_HOME/ros2_ws"* ]]
  [[ "$output" == *"$TEST_HOME/dev_ws"* ]]
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

@test "ws clean with no args prints usage and exits 0" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_clean.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ws clean"* ]]
}

@test "ws build with no args prints usage when require-all is true" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_build.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ws build"* ]]
}
