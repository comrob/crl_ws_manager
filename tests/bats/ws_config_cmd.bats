#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
}

@test "ws config setters replace existing keys without duplicates" {
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

@test "ws config setters create missing config files" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" set-build-program colcon
  [ "$status" -eq 0 ]

  cfg="$TEST_HOME/.config/crl_ws_manager/ws_config.bash"
  [ -f "$cfg" ]
  run bash -lc "grep '^WS_BUILD_PROGRAM=' '$cfg'"
  [ "$status" -eq 0 ]
  [[ "$output" == "WS_BUILD_PROGRAM=colcon" ]]
}

@test "ws config env-init creates missing env file" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" env-init
  [ "$status" -eq 0 ]

  env_file="$TEST_HOME/.config/crl_ws_manager/ws_env.bash"
  [ -f "$env_file" ]
  run bash -lc "grep -F 'Local environment for ws_manager.' '$env_file'"
  [ "$status" -eq 0 ]
}

@test "ws config setters replace multiline assignments cleanly" {
  cfg="$TEST_HOME/.config/crl_ws_manager/ws_config.bash"
  mkdir -p "$(dirname "$cfg")"
  cat > "$cfg" <<'EOF'
WS_BUILD_PROGRAM="colcon"
WS_BUILD_DEFAULT_ARGS=(
  --symlink-install
  --continue-on-error
)
WS_EDITOR_PROGRAM="code"
EOF

  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" set-build-args --merge-install
  [ "$status" -eq 0 ]

  run bash -lc "grep -c '^WS_BUILD_DEFAULT_ARGS=' '$cfg'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep -F -- '--symlink-install' '$cfg'"
  [ "$status" -ne 0 ]

  run bash -lc "grep -E '^[[:space:]]*\\)[[:space:]]*$' '$cfg'"
  [ "$status" -ne 0 ]

  run bash -lc "grep -Fx 'WS_BUILD_DEFAULT_ARGS=( --merge-install )' '$cfg'"
  [ "$status" -eq 0 ]
}

@test "ws config set-editor stores program and args" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" set-editor nvim --headless
  [ "$status" -eq 0 ]

  cfg="$TEST_HOME/.config/crl_ws_manager/ws_config.bash"
  run bash -lc "grep '^WS_EDITOR_PROGRAM=' '$cfg'"
  [ "$status" -eq 0 ]
  [[ "$output" == "WS_EDITOR_PROGRAM=nvim" ]]

  run bash -lc "grep '^WS_EDITOR_ARGS=' '$cfg'"
  [ "$status" -eq 0 ]
  [[ "$output" == "WS_EDITOR_ARGS=( --headless )" ]]
}

@test "ws config set-build-env-command stores shell command" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" set-build-env-command jazzy_env --overlay dev
  [ "$status" -eq 0 ]

  cfg="$TEST_HOME/.config/crl_ws_manager/ws_config.bash"
  run bash -lc "grep '^WS_BUILD_ENV_COMMAND=' '$cfg'"
  [ "$status" -eq 0 ]
  [[ "$output" == 'WS_BUILD_ENV_COMMAND=jazzy_env\ --overlay\ dev' ]]
}
