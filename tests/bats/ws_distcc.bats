#!/usr/bin/env bats

load './test_helper.bash'

setup() {
  setup_test_env
  make_pkg "$TEST_HOME/ws" "pkg"
  # Fake build program: prints what ws build hands to colcon.
  mkdir -p "$TEST_HOME/bin"
  cat > "$TEST_HOME/bin/fake_build" <<'SH'
#!/usr/bin/env bash
echo "DISTCC_HOSTS=${DISTCC_HOSTS:-} MAKEFLAGS=${MAKEFLAGS:-} PARALLEL=${CMAKE_BUILD_PARALLEL_LEVEL:-}"
echo "ARGS: $*"
SH
  printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/bin/distcc"
  chmod +x "$TEST_HOME/bin/fake_build" "$TEST_HOME/bin/distcc"
}

run_build() {
  run env \
    HOME="$TEST_HOME" \
    PATH="$TEST_HOME/bin:$PATH" \
    ROS_DISTRO="__test_no_ros_setup__" \
    WS_BUILD_PROGRAM="fake_build" \
    WS_BUILD_SUBCOMMAND="" \
    "$@" \
    bash "$REPO_ROOT/bin/ws_build.sh" -w "$TEST_HOME/ws" pkg
}

start_listener() {
  command -v python3 >/dev/null || skip "python3 not available"
  python3 -c '
import socket, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(8)
print(s.getsockname()[1], flush=True)
while True:
    s.accept()[0].close()
' > "$TEST_HOME/port" &
  LISTENER_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$TEST_HOME/port" ]] && break
    sleep 0.2
  done
  PORT="$(cat "$TEST_HOME/port")"
}

teardown() {
  if [[ -n "${LISTENER_PID:-}" ]]; then
    kill "$LISTENER_PID" 2>/dev/null || true
  fi
}

@test "distcc off leaves the build command unchanged" {
  run_build WS_DISTCC=false DISTCC_HOSTS=
  [ "$status" -eq 0 ]
  [[ "$output" != *"COMPILER_LAUNCHER"* ]]
  [[ "$output" == *"DISTCC_HOSTS=localhost/"* ]]
  [[ "$output" == *"MAKEFLAGS= "* ]]
}

@test "distcc on uses the answering hosts and their slots" {
  start_listener
  run_build WS_DISTCC=true WS_DISTCC_HOSTS="127.0.0.1:$PORT/12,lzo 127.0.0.1:$PORT/3"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISTCC_HOSTS=127.0.0.1:$PORT/12,lzo 127.0.0.1:$PORT/3 MAKEFLAGS=-j15 PARALLEL=15"* ]]
  [[ "$output" == *"--cmake-args -DCMAKE_C_COMPILER_LAUNCHER=distcc -DCMAKE_CXX_COMPILER_LAUNCHER=distcc -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON"* ]]
}

@test "distcc args go before the user's own --cmake-args" {
  start_listener
  run_build WS_DISTCC=true WS_DISTCC_HOSTS="127.0.0.1:$PORT/4" WS_DISTCC_JOBS=7
  [ "$status" -eq 0 ]
  [[ "$output" == *"MAKEFLAGS=-j7"* ]]

  mkdir -p "$TEST_HOME/.config/crl_ws_manager"
  echo 'WS_BUILD_DEFAULT_ARGS=(--symlink-install --cmake-args -DFOO=1)' > "$TEST_HOME/.config/crl_ws_manager/ws_config.bash"
  run_build WS_DISTCC=true WS_DISTCC_HOSTS="127.0.0.1:$PORT/4"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--symlink-install --cmake-args -DCMAKE_C_COMPILER_LAUNCHER=distcc -DCMAKE_CXX_COMPILER_LAUNCHER=distcc -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON -DFOO=1 --packages-select pkg"* ]]
  [ "$(grep '^ARGS:' <<< "$output" | grep -o -- '--cmake-args' | wc -l)" -eq 1 ]
}

@test "distcc without an answering host, or with --local, compiles locally with the same args" {
  run_build WS_DISTCC=true WS_DISTCC_HOSTS="127.0.0.1:1/8"
  [ "$status" -eq 0 ]
  [[ "$output" == *"does not answer"* ]]
  [[ "$output" == *"DISTCC_HOSTS=localhost/"*"MAKEFLAGS= "* ]]
  [[ "$output" == *"-DCMAKE_CXX_COMPILER_LAUNCHER=distcc"* ]]

  start_listener
  run env HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$PATH" ROS_DISTRO="__test_no_ros_setup__" \
    WS_BUILD_PROGRAM="fake_build" WS_BUILD_SUBCOMMAND="" \
    WS_DISTCC=true WS_DISTCC_HOSTS="127.0.0.1:$PORT/8" \
    bash "$REPO_ROOT/bin/ws_build.sh" --local -w "$TEST_HOME/ws" pkg
  [ "$status" -eq 0 ]
  [[ "$output" == *"compiling locally"* ]]
  [[ "$output" == *"-DCMAKE_CXX_COMPILER_LAUNCHER=distcc"* ]]
}

@test "ws config distcc stores hosts, switch and jobs" {
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" distcc hosts 10.0.0.1/30,lzo 10.0.0.2
  [ "$status" -eq 0 ]
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" distcc jobs 40
  [ "$status" -eq 0 ]
  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" show
  [[ "$output" == *"WS_DISTCC=true"* ]]
  [[ "$output" == *"WS_DISTCC_HOSTS=10.0.0.1/30,lzo 10.0.0.2"* ]]
  [[ "$output" == *"WS_DISTCC_JOBS=40"* ]]

  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" distcc off
  [ "$status" -eq 0 ]
  cfg="$TEST_HOME/.config/crl_ws_manager/ws_config.bash"
  [ "$(grep -c '^WS_DISTCC=' "$cfg")" -eq 1 ]
  grep -q '^WS_DISTCC=false$' "$cfg"

  run env HOME="$TEST_HOME" bash "$REPO_ROOT/bin/ws_config.sh" distcc hosts 'a;b'
  [ "$status" -ne 0 ]
}
