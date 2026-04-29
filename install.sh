#!/usr/bin/env bash
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=ws_lib.sh
source "$TOOL_DIR/ws_lib.sh"

TOOLS_TARGET_DIR="${HOME}/.local/bin"
BASHRC_PATH="${HOME}/.bashrc"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_ROOT="$TOOLS_TARGET_DIR/crl_ws_manager_backup/$BACKUP_STAMP"

declare -A COMMANDS=(
  ["ws"]="$TOOL_DIR/ws_manager.sh"
  ["ws-build"]="$TOOL_DIR/ws_build.sh"
  ["ws-clean"]="$TOOL_DIR/ws_clean.sh"
  ["ws-cd-resolve"]="$TOOL_DIR/ws_cd_resolve.sh"
  ["ws-list"]="$TOOL_DIR/ws_list.sh"
  ["ws-open"]="$TOOL_DIR/ws_open.sh"
  ["ws-config"]="$TOOL_DIR/ws_config.sh"
  ["ws-which"]="$TOOL_DIR/ws_which.sh"
)
FUNCTIONS_FILE_DIR="$(ws_config_dir)"
FUNCTIONS_SOURCE="$TOOL_DIR/ws_manager.bash"
FUNCTIONS_TARGET="$(ws_functions_file)"
WS_LIB_TARGET="$FUNCTIONS_FILE_DIR/ws_lib.sh"
WS_CONFIG_TARGET="$(ws_config_file)"
LEGACY_WS_CONFIG_TARGET="$(ws_legacy_config_file)"

for cmd_name in "${!COMMANDS[@]}"; do
  if [[ ! -f "${COMMANDS[$cmd_name]}" ]]; then
    echo "[ERROR] Missing tool executable: ${COMMANDS[$cmd_name]}" >&2
    exit 1
  fi
done

mkdir -p "$TOOLS_TARGET_DIR"
mkdir -p "$FUNCTIONS_FILE_DIR"
touch "$BASHRC_PATH"

if [[ ! -d "$BACKUP_ROOT" ]]; then
  mkdir -p "$BACKUP_ROOT"
fi

# ws_lib.sh is a non-executable helper sourced by ws_build.sh, ws_clean.sh,
# ws_list.sh (via SCRIPT_DIR) and by ws_manager.bash (via its own lookup).
# Link it to the two locations where those scripts look for it.
WS_LIB_SOURCE="$TOOL_DIR/ws_lib.sh"
if [[ ! -f "$WS_LIB_SOURCE" ]]; then
  echo "[ERROR] Missing library file: $WS_LIB_SOURCE" >&2
  exit 1
fi
for _lib_dest in "$TOOLS_TARGET_DIR/ws_lib.sh" "$WS_LIB_TARGET"; do
  [[ -L "$_lib_dest" ]] && unlink "$_lib_dest"
  [[ -f "$_lib_dest" ]] && mv "$_lib_dest" "$BACKUP_ROOT/$(basename "$_lib_dest")"
  ln -s "$WS_LIB_SOURCE" "$_lib_dest"
  echo "  Linked $WS_LIB_SOURCE -> $_lib_dest"
done
unset _lib_dest WS_LIB_SOURCE

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

# Editor command used by: ws open <package>
WS_EDITOR_PROGRAM="code"
WS_EDITOR_ARGS=()
EOF
  echo "  Created local config template: $WS_CONFIG_TARGET"
fi

# Ensure ~/.local/bin is in PATH for future shells.
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
PATH_COMMENT='# Added by CRL ws_manager install.sh'
OLD_PATH_COMMENT='# Added by crl_husky_deployment/tools/ws_manager/install.sh'
if grep -qF "$OLD_PATH_COMMENT" "$BASHRC_PATH" 2>/dev/null; then
  tmp_file="$(mktemp)"
  awk -v old="$OLD_PATH_COMMENT" -v new="$PATH_COMMENT" '
    { if ($0 == old) print new; else print }
  ' "$BASHRC_PATH" > "$tmp_file"
  mv "$tmp_file" "$BASHRC_PATH"
fi
if ! grep -qF "$PATH_LINE" "$BASHRC_PATH" 2>/dev/null; then
  echo "" >> "$BASHRC_PATH"
  echo "$PATH_COMMENT" >> "$BASHRC_PATH"
  echo "$PATH_LINE" >> "$BASHRC_PATH"
fi

if [[ -L "$FUNCTIONS_TARGET" ]]; then
  unlink "$FUNCTIONS_TARGET"
elif [[ -f "$FUNCTIONS_TARGET" ]]; then
  backup_dir="$BACKUP_ROOT"
  mkdir -p "$backup_dir"
  mv "$FUNCTIONS_TARGET" "$backup_dir/ws_manager.bash"
  echo "  Backed up existing functions file to $backup_dir/ws_manager.bash"
fi

ln -s "$FUNCTIONS_SOURCE" "$FUNCTIONS_TARGET"

echo "  Linked functions file: $FUNCTIONS_SOURCE -> $FUNCTIONS_TARGET"

# Remove old inline/source managed blocks if present.
remove_block() {
  local begin_marker="$1"
  local end_marker="$2"
  if grep -qF "$begin_marker" "$BASHRC_PATH" && grep -qF "$end_marker" "$BASHRC_PATH"; then
    local tmp_file="$(mktemp)"
    awk -v begin="$begin_marker" -v end="$end_marker" '
      BEGIN { skip = 0 }
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      skip == 0 { print }
    ' "$BASHRC_PATH" > "$tmp_file"
    mv "$tmp_file" "$BASHRC_PATH"
  fi
}

remove_block "# >>> crl_husky ws manager >>>" "# <<< crl_husky ws manager <<<"
remove_block "# >>> crl ws manager >>>" "# <<< crl ws manager <<<"
remove_block "# >>> crl_husky ws manager source >>>" "# <<< crl_husky ws manager source <<<"
remove_block "# >>> crl ws manager source >>>" "# <<< crl ws manager source <<<"

# Keep only a short source block in ~/.bashrc.
SOURCE_BEGIN="# >>> crl ws manager source >>>"
SOURCE_END="# <<< crl ws manager source <<<"
SOURCE_BLOCK=$(cat <<'EOF'
# >>> crl ws manager source >>>
if [[ -f "$HOME/.config/crl_ws_manager/ws_manager.bash" ]]; then
  source "$HOME/.config/crl_ws_manager/ws_manager.bash"
fi
# <<< crl ws manager source <<<
EOF
)

if grep -qF "$SOURCE_BEGIN" "$BASHRC_PATH" && grep -qF "$SOURCE_END" "$BASHRC_PATH"; then
  tmp_file="$(mktemp)"
  awk -v begin="$SOURCE_BEGIN" -v end="$SOURCE_END" -v block="$SOURCE_BLOCK" '
    BEGIN { skip = 0 }
    $0 == begin { print block; skip = 1; next }
    $0 == end { skip = 0; next }
    skip == 0 { print }
  ' "$BASHRC_PATH" > "$tmp_file"
  mv "$tmp_file" "$BASHRC_PATH"
else
  echo "" >> "$BASHRC_PATH"
  echo "$SOURCE_BLOCK" >> "$BASHRC_PATH"
fi

for cmd_name in "${!COMMANDS[@]}"; do
  cmd_source="${COMMANDS[$cmd_name]}"
  dest="$TOOLS_TARGET_DIR/$cmd_name"

  if [[ -L "$dest" ]]; then
    unlink "$dest"
  elif [[ -f "$dest" ]]; then
    backup_dir="$BACKUP_ROOT"
    mkdir -p "$backup_dir"
    mv "$dest" "$backup_dir/$cmd_name"
    echo "  Backed up existing regular file to $backup_dir/$cmd_name"
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
