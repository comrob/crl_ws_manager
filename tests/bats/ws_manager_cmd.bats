#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
}

@test "ws cd --help exits successfully from manager wrapper" {
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

@test "ws --version prints version banner" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_manager.sh" --version
  [ "$status" -eq 0 ]
  [[ "$output" == ws_manager* ]]
}
