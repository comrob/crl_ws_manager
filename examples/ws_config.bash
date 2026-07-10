# ws_manager — example local configuration file.
#
# Copy to ~/.config/crl_ws_manager/ws_config.bash and adjust as needed.
# This file is sourced by Bash, so use valid Bash syntax.
# CLI arguments always take precedence over values set here.
#
# Run `ws config show` to see the active values after editing.

# ---------------------------------------------------------------------------
# Build settings
# ---------------------------------------------------------------------------

# The build tool and subcommand.
WS_BUILD_PROGRAM="colcon"
WS_BUILD_SUBCOMMAND="build"

# Flags passed to every build.  Override to taste.
WS_BUILD_DEFAULT_ARGS=(
  --symlink-install
  --continue-on-error
)

# Optional shell command run in an interactive Bash before each build.
# Useful for ROS environment helpers defined in ~/.bashrc, for example:
# WS_BUILD_ENV_COMMAND="jazzy_env"
WS_BUILD_ENV_COMMAND=""

# Flag used to select specific packages.
WS_BUILD_PACKAGE_SELECT_FLAG="--packages-select"

# When true, `ws build` with no arguments prints help instead of building.
# Set to false to build all detected workspaces implicitly.
WS_BUILD_REQUIRE_ALL_FOR_FULL_BUILD=true

# ---------------------------------------------------------------------------
# Workspace fallbacks
# ---------------------------------------------------------------------------

# These directories are checked as workspace candidates when no workspaces
# are detectable from ROS_PACKAGE_PATH / COLCON_PREFIX_PATH.
# Adjust to match your directory structure.
WS_DEFAULT_WORKSPACES=(
  "$HOME/ros2_ws"   # adjust to your workspace paths
  "$HOME/dev_ws"
)

# ---------------------------------------------------------------------------
# Editor settings  (used by: ws open <package>)
# ---------------------------------------------------------------------------

# Editor executable.  Common values: code, vim, emacs, xdg-open
WS_EDITOR_PROGRAM="code"

# Extra arguments passed to the editor.
WS_EDITOR_ARGS=(
  --reuse-window
)
