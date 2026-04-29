setup_test_env() {
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

make_pkg_at() {
  local pkg_dir="$1"
  local pkg="$2"
  mkdir -p "$pkg_dir"
  cat > "$pkg_dir/package.xml" <<EOF
<package format="3">
  <name>$pkg</name>
  <version>0.0.1</version>
  <description>test package</description>
  <maintainer email="test@example.com">test</maintainer>
  <license>MIT</license>
</package>
EOF
}

set_test_editor_echo() {
  export WS_EDITOR_PROGRAM="echo"
  unset WS_EDITOR_ARGS
}
