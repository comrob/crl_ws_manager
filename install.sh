#!/usr/bin/env bash
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=lib/ws_lib.sh
source "$TOOL_DIR/lib/ws_lib.sh"

TOOLS_TARGET_DIR="${HOME}/.local/bin"
BASHRC_PATH="${HOME}/.bashrc"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_ROOT="${HOME}/.local/share/crl_ws_manager/backups/${BACKUP_STAMP}"

declare -a COMMAND_NAMES=(
  ws
  ws-build
  ws-clean
  ws-cd-resolve
  ws-list
  ws-open
  ws-config
  ws-which
)
declare -A COMMANDS=(
  ["ws"]="$TOOL_DIR/bin/ws_manager.sh"
  ["ws-build"]="$TOOL_DIR/bin/ws_build.sh"
  ["ws-clean"]="$TOOL_DIR/bin/ws_clean.sh"
  ["ws-cd-resolve"]="$TOOL_DIR/bin/ws_cd_resolve.sh"
  ["ws-list"]="$TOOL_DIR/bin/ws_list.sh"
  ["ws-open"]="$TOOL_DIR/bin/ws_open.sh"
  ["ws-config"]="$TOOL_DIR/bin/ws_config.sh"
  ["ws-which"]="$TOOL_DIR/bin/ws_which.sh"
)
FUNCTIONS_FILE_DIR="$(ws_config_dir)"
FUNCTIONS_SOURCE="$TOOL_DIR/completion/ws_manager.bash"
FUNCTIONS_TARGET="$(ws_functions_file)"
WS_LIB_TARGET="$FUNCTIONS_FILE_DIR/ws_lib.sh"
WS_CONFIG_TARGET="$(ws_config_file)"
LEGACY_WS_CONFIG_TARGET="$(ws_legacy_config_file)"

# ---------------------------------------------------------------------------
# _backup_to <path>
#   Move <path> into BACKUP_ROOT, creating the directory on first use.
# ---------------------------------------------------------------------------
_backup_to() {
  local src="$1"
  mkdir -p "$BACKUP_ROOT"
  mv "$src" "$BACKUP_ROOT/$(basename "$src")"
  echo "  Backed up $src -> $BACKUP_ROOT/$(basename "$src")"
}

for cmd_name in "${COMMAND_NAMES[@]}"; do
  if [[ ! -f "${COMMANDS[$cmd_name]}" ]]; then
    echo "[ERROR] Missing tool executable: ${COMMANDS[$cmd_name]}" >&2
    exit 1
  fi
done

mkdir -p "$TOOLS_TARGET_DIR"
mkdir -p "$FUNCTIONS_FILE_DIR"
if [[ ! -f "$BASHRC_PATH" ]]; then
  touch "$BASHRC_PATH"
  echo "  Created $BASHRC_PATH"
fi

# ws_lib.sh is sourced by bin/ scripts via SCRIPT_DIR/../lib (resolved through
# readlink -f at runtime) and by completion/ws_manager.bash. No copy into
# ~/.local/bin is needed; only link it into the config dir for ws_manager.bash.
WS_LIB_SOURCE="$TOOL_DIR/lib/ws_lib.sh"
if [[ ! -f "$WS_LIB_SOURCE" ]]; then
  echo "[ERROR] Missing library file: $WS_LIB_SOURCE" >&2
  exit 1
fi
[[ -L "$WS_LIB_TARGET" ]] && unlink "$WS_LIB_TARGET"
if [[ -f "$WS_LIB_TARGET" ]]; then
  _backup_to "$WS_LIB_TARGET"
fi
ln -s "$WS_LIB_SOURCE" "$WS_LIB_TARGET"
echo "  Linked $WS_LIB_SOURCE -> $WS_LIB_TARGET"
unset WS_LIB_SOURCE

if [[ ! -f "$FUNCTIONS_SOURCE" ]]; then
  echo "[ERROR] Missing functions file: $FUNCTIONS_SOURCE" >&2
  exit 1
fi


# Migrate an existing local config from the legacy directory.
if [[ ! -f "$WS_CONFIG_TARGET" && -f "$LEGACY_WS_CONFIG_TARGET" ]]; then
  cp "$LEGACY_WS_CONFIG_TARGET" "$WS_CONFIG_TARGET"
  echo "  Copied legacy local config to $WS_CONFIG_TARGET"
fi

# Create a sample local config if none exists yet.
if [[ ! -f "$WS_CONFIG_TARGET" ]]; then
  cat > "$WS_CONFIG_TARGET" <<'EOF'
# Local configuration for the CRL ROS workspace manager.
#
# This file is sourced by ws_* scripts, so use valid Bash syntax.
# CLI arguments still take precedence over these defaults.

WS_BUILD_PROGRAM="colcon"
WS_BUILD_SUBCOMMAND="build"
WS_BUILD_DEFAULT_ARGS=(
  --symlink-install
  --continue-on-error
)
WS_BUILD_PACKAGE_SELECT_FLAG="--packages-select"
WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD=true

# Fallback workspace roots used when none are detectable from the ROS
# environment (ROS_PACKAGE_PATH / COLCON_PREFIX_PATH).  Add or remove paths
# to match your setup.
WS_DEFAULT_WORKSPACES=(
  "$HOME/sw_ws"
  "$HOME/drv_ws"
)

# Editor command used by: ws open <package>
WS_EDITOR_PROGRAM="code"
WS_EDITOR_ARGS=()
EOF
  echo "  Created local config template: $WS_CONFIG_TARGET"
fi

# ---------------------------------------------------------------------------
# _install_into_rcfile <rcfile>
#   Ensure ~/.local/bin is on PATH and add the ws_manager source block to the
#   given shell rc file.  Safe to call multiple times (idempotent).
# ---------------------------------------------------------------------------
_install_into_rcfile() {
  local rc="$1"
  [[ -f "$rc" ]] || { touch "$rc"; echo "  Created $rc"; }

  # Migrate a stale PATH comment from previous installs.
  local OLD_PATH_COMMENT='# Added by crl_husky_deployment/tools/ws_manager/install.sh'
  local PATH_COMMENT='# Added by CRL ws_manager install.sh'
  local PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
  if grep -qF "$OLD_PATH_COMMENT" "$rc" 2>/dev/null; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -v old="$OLD_PATH_COMMENT" -v new="$PATH_COMMENT" \
      '{ if ($0 == old) print new; else print }' "$rc" > "$tmp_file"
    mv "$tmp_file" "$rc"
  fi
  if ! grep -qF "$PATH_LINE" "$rc" 2>/dev/null; then
    echo "" >> "$rc"
    echo "$PATH_COMMENT" >> "$rc"
    echo "$PATH_LINE" >> "$rc"
    echo "  Added PATH entry to $rc"
  fi

  # Remove legacy source blocks.
  _remove_block_from_file "$rc" "# >>> crl_husky ws manager >>>"      "# <<< crl_husky ws manager <<<"
  _remove_block_from_file "$rc" "# >>> crl ws manager >>>"            "# <<< crl ws manager <<<"
  _remove_block_from_file "$rc" "# >>> crl_husky ws manager source >>>" "# <<< crl_husky ws manager source <<<"
  _remove_block_from_file "$rc" "# >>> crl ws manager source >>>"     "# <<< crl ws manager source <<<"

  local SOURCE_BEGIN="# >>> crl ws manager source >>>"
  local SOURCE_END="# <<< crl ws manager source <<<"
  local SOURCE_BLOCK
  SOURCE_BLOCK=$(cat <<'SRCEOF'
# >>> crl ws manager source >>>
if [[ -f "$HOME/.config/crl_ws_manager/ws_manager.bash" ]]; then
  source "$HOME/.config/crl_ws_manager/ws_manager.bash"
fi
# <<< crl ws manager source <<<
SRCEOF
)
  if grep -qF "$SOURCE_BEGIN" "$rc" && grep -qF "$SOURCE_END" "$rc"; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -v begin="$SOURCE_BEGIN" -v end="$SOURCE_END" -v block="$SOURCE_BLOCK" '
      BEGIN { skip = 0 }
      $0 == begin { print block; skip = 1; next }
      $0 == end { skip = 0; next }
      skip == 0 { print }
    ' "$rc" > "$tmp_file"
    mv "$tmp_file" "$rc"
  else
    echo "" >> "$rc"
    echo "$SOURCE_BLOCK" >> "$rc"
    echo "  Added source block to $rc"
  fi
}

# Ensure ~/.local/bin is in PATH and ws_manager is sourced for the login shell.

if [[ -L "$FUNCTIONS_TARGET" ]]; then
  unlink "$FUNCTIONS_TARGET"
elif [[ -f "$FUNCTIONS_TARGET" ]]; then
  _backup_to "$FUNCTIONS_TARGET"
fi

ln -s "$FUNCTIONS_SOURCE" "$FUNCTIONS_TARGET"

echo "  Linked functions file: $FUNCTIONS_SOURCE -> $FUNCTIONS_TARGET"

# ---------------------------------------------------------------------------
# _remove_block_from_file <file> <begin-marker> <end-marker>
#   Strip a delimited block from a file if it is present (split local/assign
#   to ensure set -e catches mktemp failures).
# ---------------------------------------------------------------------------
_remove_block_from_file() {
  local file="$1" begin_marker="$2" end_marker="$3"
  if grep -qF "$begin_marker" "$file" && grep -qF "$end_marker" "$file"; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -v begin="$begin_marker" -v end="$end_marker" '
    BEGIN { skip = 0 }
      $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip == 0 { print }
    ' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
  fi
}

# Configure the user's shell rc file(s).
_install_into_rcfile "$BASHRC_PATH"
if [[ "${SHELL:-}" == */zsh ]]; then
  ZSHRC_PATH="${HOME}/.zshrc"
  _install_into_rcfile "$ZSHRC_PATH"
  echo "  zsh detected — also configured $ZSHRC_PATH"
fi

for cmd_name in "${COMMAND_NAMES[@]}"; do
  cmd_source="${COMMANDS[$cmd_name]}"
  dest="$TOOLS_TARGET_DIR/$cmd_name"

  if [[ -L "$dest" ]]; then
    unlink "$dest"
  elif [[ -f "$dest" ]]; then
    _backup_to "$dest"
  elif [[ -e "$dest" ]]; then
    echo "  [SKIP] $dest exists and is not a regular file or symlink"
    echo "  Please resolve it manually and re-run install."
    exit 1
  fi

  ln -s "$cmd_source" "$dest"
  echo "  Linked $cmd_source -> $dest"
done

# Remove deprecated executable from older installs.
if [[ -L "$TOOLS_TARGET_DIR/ws-code" || -f "$TOOLS_TARGET_DIR/ws-code" ]]; then
  rm -f "$TOOLS_TARGET_DIR/ws-code"
fi

echo "  NOTE: Run 'source ~/.bashrc' to activate ws functions in this terminal."
if [[ ":$PATH:" != *":$TOOLS_TARGET_DIR:"* ]]; then
  echo "  NOTE: $TOOLS_TARGET_DIR is not on your current PATH."
  echo "        Run: source ~/.bashrc"
fi
