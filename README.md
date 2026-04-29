# ws_manager

[![CI](https://github.com/comrob/crl_ws_manager/actions/workflows/ci.yml/badge.svg)](https://github.com/comrob/crl_ws_manager/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/comrob/crl_ws_manager)](https://github.com/comrob/crl_ws_manager/releases)

> **TL;DR** — A `ws` command for ROS 2 colcon workspaces. Build, clean, navigate, and inspect packages without typing long paths or remembering colcon flags.

```bash
ws build --all                   # build every detected workspace
ws build -w drv_ws -p my_pkg     # build one package in a specific workspace
ws cd liorf_slam_crl             # jump to a package's source directory
ws cd --install liorf_slam_crl   # jump to its install prefix instead
ws clean -w drv_ws -p my_pkg     # wipe build/install/log for a package
ws list -p                       # list all workspaces + packages + install status
ws open my_pkg                   # open package in VS Code (configurable)
ws which my_pkg my_launch.py     # show source & install paths for a launch file
ws config set-build-args --symlink-install --continue-on-error
ws doctor                        # diagnose PATH, ROS env, colcon, config
ws update                        # git pull + reinstall in one command
```

Workspaces are **auto-detected** from `ROS_PACKAGE_PATH` / `COLCON_PREFIX_PATH`. Fallback paths are configurable via `WS_DEFAULT_WORKSPACES` in `ws_config.bash`. Tab completion works everywhere.

---

## Repository layout

```
bin/               # installed executables (symlinked to ~/.local/bin)
  ws_manager.sh    # dispatches ws subcommands
  ws_build.sh      # wraps colcon build
  ws_clean.sh      # removes build/install/log artifacts
  ws_cd_resolve.sh # resolves package → directory (used by ws cd)
  ws_list.sh       # lists workspaces and package status
  ws_open.sh       # opens a package path in the configured editor
  ws_config.sh     # manages local configuration
  ws_which.sh      # resolves source/install/launch file paths
lib/
  ws_lib.sh        # shared helpers (sourced, not executed)
completion/
  ws_manager.bash  # shell functions, roscd alias, and bash completion
examples/
  ws_config.bash   # annotated configuration template
VERSION            # current version string
install.sh         # installer
```

---

## Installation

```bash
./install.sh
source ~/.bashrc
```

`install.sh`:

- Symlinks all `bin/` scripts into `~/.local/bin/` as `ws`, `ws-build`, etc.
- Symlinks `completion/ws_manager.bash` into `~/.config/crl_ws_manager/`
- Symlinks `lib/ws_lib.sh` into `~/.config/crl_ws_manager/` for the sourced shell functions
- Creates `~/.config/crl_ws_manager/ws_config.bash` with defaults (if absent)
- Adds `~/.local/bin` to `PATH` in `~/.bashrc` if missing
- Adds a source block to `~/.bashrc` to load shell functions on login
- Also configures `~/.zshrc` if your login shell is zsh

### Local test/CI run

For quick local validation (same flow as CI):

```bash
make ci-local
```

This runs:
- shell syntax checks
- install smoke
- command smoke (`ws --version`, `ws build --help`, `ws-cd-resolve --help`, `ws doctor`)
- Bats tests
- uninstall smoke

To run only the Bats tests:

```bash
make test
```

### ROS distro compatibility

Tested on ROS 2 **Jazzy**, **Humble**, **Iron**, and **Rolling**. The tool reads `$ROS_DISTRO` at runtime — no distro-specific configuration is required. The only place a default (`jazzy`) is used is as a fallback when sourcing the ROS underlay inside `ws build`; set `ROS_DISTRO` in your shell to override.

---

## Commands

### `ws build`

```
ws build [--all] [-w|--ws <workspace>]... [-p|--packages <pkg>]...
```

| Flag | Description |
|------|-------------|
| `-w / --ws` | Workspace root (name relative to `$HOME`, or absolute path); repeatable |
| `-p / --packages` | Package name passed to `--packages-select`; repeatable |
| `--all` | Build all detected workspaces |
| `--clean` | Wipe package artifacts before building |

```bash
ws build --all
ws build -w drv_ws
ws build -w drv_ws -p my_package
ws build -w ~/sw_ws -p pkg_a -p pkg_b
```

Build flags are configured in `~/.config/crl_ws_manager/ws_config.bash`.

---

### `ws version`

```bash
ws --version
ws version
```

Prints the installed version string from the `VERSION` file.

---

### `ws update`

```bash
ws update
```

Runs `git pull` in the repository root and re-runs `install.sh`.  
Requires the tool to have been installed from a git clone.

---

### `ws doctor`

```bash
ws doctor
```

Checks all prerequisites and reports any problems:
- `ws` and all subcommand binaries on `PATH`
- Config file present
- Shell functions file present
- `ROS_DISTRO` set
- `colcon` available
- At least one workspace detected

---

### `ws cd`

Changes directory to a package's source tree or install prefix.

```
ws cd [--source|--install] [-s|--include-system] <package_name>
```

| Flag | Description |
|------|-------------|
| `--source` | Navigate to source directory in workspace `src/` (default) |
| `--install / -i` | Navigate to the install prefix |
| `-s / --include-system` | Completion also includes system packages from `ros2 pkg list` |

`roscd` is an alias for `ws cd`.

```bash
ws cd liorf_slam_crl
ws cd --install liorf_slam_crl
ws cd -s <TAB>      # completes with local + system packages
```

---

### `ws clean`

```
ws clean [--clean-all] [-w|--ws <workspace>]... [-p|--packages <pkg>]... [<pkg>...]
```

Removes `build/`, `install/`, and `log/` artifacts for selected packages or entire workspaces.

---

### `ws list`

```
ws list [-p|--packages] [-w|--ws <workspace>] [--installed] [-q|--quiet]
```

Lists detected workspaces; with `-p` also shows packages and install status.

---

### `ws open`

```
ws open [--source|--install] <package_name>
```

Opens the package path in the configured editor. Configure via:

```bash
ws config set-editor code --reuse-window
```

Config keys: `WS_EDITOR_PROGRAM` (default `code`), `WS_EDITOR_ARGS` (default empty).

---

### `ws which`

```
ws which <package_name> [launchfile]
ws which <package_name> --launch <launchfile>
```

Shows source path, install prefix, and (optionally) launch file paths — including whether the installed launch file is a symlink and whether it resolves to the same file as the source.

---

### `ws config`

```
ws config [show|path|init|edit|set-editor|set-build-program|set-build-subcommand|set-build-args|require-all]
```

```bash
ws config show
ws config edit
ws config set-editor code --reuse-window
ws config set-build-args --symlink-install --continue-on-error
ws config require-all true
```

To configure fallback workspaces:

```bash
# In ~/.config/crl_ws_manager/ws_config.bash:
WS_DEFAULT_WORKSPACES=(
  "$HOME/ros2_ws"
  "$HOME/dev_ws"
)
```

See `examples/ws_config.bash` for a fully annotated template.

---

### `ws-cd-resolve` (scripting)

Lower-level executable used by the `ws cd` shell function. Prints the resolved path to stdout — useful in scripts.

```bash
ws-cd-resolve my_package          # prints source dir
ws-cd-resolve --install my_pkg    # prints install prefix
```

---

## Bash completion

Registered automatically when `~/.config/crl_ws_manager/ws_manager.bash` is sourced.

| Context | Completes |
|---------|-----------|
| `ws <TAB>` | `build`, `clean`, `cd`, `list`, `open`, `config`, `help` |
| `ws build -p <TAB>` | Package names from active workspace `src/` directories |
| `ws build -w <TAB>` | Detected workspace names or path completion |
| `ws cd <TAB>` | Package names from active workspace `src/` directories |
| `ws cd -s <TAB>` | Package names including system packages (`ros2 pkg list`) |
| `ws open <TAB>` | Package names from active workspace `src/` directories |
| `ws which <TAB>` | Package names from active workspace `src/` directories |
| `ws which <pkg> <TAB>` | Installed launch files for `<pkg>` |

Workspaces are detected dynamically — no paths are hardcoded.
