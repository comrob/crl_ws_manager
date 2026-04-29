# ws_manager

Workspace management tool for ROS 2 colcon workspaces. Provides `ws build` and `ws cd` commands with bash completion.

## Files

| File | Purpose |
|------|---------|
| `install.sh` | Installs the tool (run via `link_tools.sh`) |
| `ws_manager.sh` | Installed as `ws` — dispatches subcommands |
| `ws_build.sh` | Installed as `ws-build` — wraps `colcon build` |
| `ws_clean.sh` | Installed as `ws-clean` — cleans build/install/log artifacts |
| `ws_list.sh` | Installed as `ws-list` — lists workspaces and package status |
| `ws_cd_resolve.sh` | Installed as `ws-cd-resolve` — resolves package → directory path |
| `ws_open.sh` | Installed as `ws-open` — opens package path in editor |
| `ws_config.sh` | Installed as `ws-config` — manages local configuration |
| `ws_which.sh` | Installed as `ws-which` — resolves source/install/launch paths |
| `ws_manager.bash` | Sourced into the user's shell — provides `ws()`, `roscd()`, and bash completion |

## Installation

```bash
./link_tools.sh
source ~/.bashrc
```

`install.sh` does the following:

- Symlinks `ws`, `ws-build`, `ws-clean`, `ws-list`, `ws-cd-resolve`, `ws-open`, `ws-config`, and `ws-which` into `~/.local/bin/`
- Symlinks `ws_manager.bash` into `~/.config/crl_ws_manager/ws_manager.bash`
- Creates `~/.config/crl_ws_manager/ws_config.bash` if no local config exists yet
- Adds `~/.local/bin` to `PATH` in `~/.bashrc` if missing
- Adds a source block to `~/.bashrc` to load the shell functions

## Commands

### `ws build`

Builds one or more colcon workspaces.

```
Usage: ws build [--all] [-w|--ws <workspace>]... [-p|--packages <pkg>]...
```

- `-w / --ws` — workspace root (name relative to `$HOME`, or absolute path); repeatable
- `-p / --packages` — package name to pass to `--packages-select`; repeatable
- `--all` — build all detected workspaces
- Build flags are configurable locally in `~/.config/crl_ws_manager/ws_config.bash`

**Examples:**

```bash
ws build --all
ws build -w drv_ws
ws build -w drv_ws -p my_package
ws build -w ~/sw_ws -p pkg_a -p pkg_b
```

### `ws cd`

Changes directory to a package's source tree (or install prefix).

```
Usage: ws cd [--source|--install] [-s|--include-system] <package_name>
```

- `--source` (default) — navigate to the package source directory found in the workspace `src/`
- `--install / -i` — navigate to the install prefix instead
- `-s / --include-system` — hint for bash completion to also include system packages from `ros2 pkg list`

**Examples:**

```bash
ws cd liorf_slam_crl
ws cd --install liorf_slam_crl
ws cd -s <TAB>           # completes with local + system packages
```

`roscd` is an alias for `ws cd`.

### `ws clean`

Clean workspace artifacts (`build`, `install`, `log`) for selected packages or whole workspaces.

```
Usage: ws clean [--clean-all] [-w|--ws <workspace>]... [-p|--packages <pkg>]... [<pkg>...]
```

### `ws list`

List detected workspaces and optionally packages with install status.

```
Usage: ws list [-p|--packages] [-w|--ws <workspace>] [--installed] [-q|--quiet]
```

### `ws open`

Open a package path in the configured editor.

```
Usage: ws open [--source|--install] <package_name>
```

Editor config keys in `~/.config/crl_ws_manager/ws_config.bash`:

- `WS_EDITOR_PROGRAM` (default `code`)
- `WS_EDITOR_ARGS` (default empty array)

### `ws config`

Manage local ws behavior configuration.

```
Usage: ws config [show|path|init|edit|set-editor|set-build-program|set-build-subcommand|set-build-args|require-all]
```

Examples:

```bash
ws config show
ws config edit
ws config set-editor code --reuse-window
ws config set-build-args --symlink-install --continue-on-error
ws config require-all true
```

### `ws which`

Resolve package source/install paths and optionally launch file paths.

```
Usage: ws which <package_name> [launchfile]
	ws which <package_name> --launch <launchfile>
```

When a launch file is requested, output includes:

- source launch file path
- installed launch file path
- whether the installed launch file is a symlink
- symlink target path (if symlinked)
- whether installed launch points to the same file as source

### `ws-cd-resolve`

Lower-level executable called by the `ws cd` shell function. Outputs the resolved path to stdout. Useful for scripting.

```bash
ws-cd-resolve my_package          # prints source dir
ws-cd-resolve --install my_pkg    # prints install prefix
```

## Bash Completion

Completion is registered automatically when `~/.config/crl_ws_manager/ws_manager.bash` is sourced.

| Context | Completion |
|---------|-----------|
| `ws <TAB>` | `build`, `clean`, `cd`, `list`, `open`, `config`, `help` |
| `ws build -p <TAB>` | Package names from active workspace `src/` directories |
| `ws build -w <TAB>` | Smart workspace completion (detected names or path completion) |
| `ws cd <TAB>` | Package names from active workspace `src/` directories |
| `ws cd -s <TAB>` | Package names including system packages (`ros2 pkg list`) |
| `ws open <TAB>` | Package names from active workspace `src/` directories |
| `ws which <TAB>` | Package names from active workspace `src/` directories |
| `ws which <pkg> <TAB>` | Installed launch files for `<pkg>` |

Workspaces are detected dynamically from `ROS_PACKAGE_PATH` and `COLCON_PREFIX_PATH`. No paths are hardcoded.
