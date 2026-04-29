# ws_manager

[![CI](https://github.com/comrob/crl_ws_manager/actions/workflows/ci.yml/badge.svg)](https://github.com/comrob/crl_ws_manager/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/comrob/crl_ws_manager)](https://github.com/comrob/crl_ws_manager/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> A `ws` command for ROS 2 colcon workspaces. Build, clean, navigate, and inspect packages — without typing long paths or remembering colcon flags. Works with unsourced and uninstalled packages. No dependencies, pure bash.

---

## Table of Contents

- [TL;DR](#tldr)
- [Installation](#installation)
- [Commands](#commands)
  - [ws build](#ws-build)
  - [ws cd](#ws-cd)
  - [ws list](#ws-list)
  - [ws open](#ws-open)
  - [ws which](#ws-which)
  - [ws clean](#ws-clean)
  - [ws config](#ws-config)
  - [ws doctor](#ws-doctor)
  - [ws update](#ws-update)
  - [ws version](#ws-version)
  - [ws-cd-resolve (scripting)](#ws-cd-resolve-scripting)
- [Bash Completion](#bash-completion)
- [Developer Section](#developer-section)
  - [Running Tests](#running-tests)
  - [Local CI Run](#local-ci-run)
  - [ROS Distro Compatibility](#ros-distro-compatibility)
- [Citing This Work](#citing-this-work)
- [License](#license)

---

## TL;DR

```bash
ws build --all                    # build every detected workspace
ws build -w dev_ws -p my_pkg      # build one package in a specific workspace
ws cd my_package                  # jump to a package's source directory
ws cd --install my_package        # jump to its install prefix instead
ws clean -w dev_ws -p my_pkg      # wipe build/install/log for a package
ws list -p                        # list all workspaces + packages + install status
ws open my_pkg                    # open package in VS Code (configurable)
ws which my_pkg my_launch.py      # show source & install paths for a launch file
ws config set-build-args --symlink-install --continue-on-error
ws doctor                         # diagnose PATH, ROS env, colcon, config
ws update                         # git pull + reinstall in one command
```

Workspaces are **auto-detected** from `ROS_PACKAGE_PATH` / `COLCON_PREFIX_PATH`. Fallback paths are configurable via `WS_DEFAULT_WORKSPACES` in `ws_config.bash`. Tab completion works everywhere.

---

## Installation

```bash
git clone https://github.com/comrob/crl_ws_manager.git
cd crl_ws_manager
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

To uninstall, run `./install.sh --uninstall`.

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
ws build -w ros2_ws
ws build -w ros2_ws -p my_package
ws build -w ~/ros2_ws -p pkg_a -p pkg_b
```

Build flags are configured in `~/.config/crl_ws_manager/ws_config.bash`.

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

### `ws clean`

```
ws clean [--clean-all] [-w|--ws <workspace>]... [-p|--packages <pkg>]... [<pkg>...]
```

Removes `build/`, `install/`, and `log/` artifacts for selected packages or entire workspaces.

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

### `ws update`

```bash
ws update
```

Runs `git pull` in the repository root and re-runs `install.sh`.  
Requires the tool to have been installed from a git clone.

---

### `ws version`

```bash
ws --version
ws version
```

Prints the installed version string from the `VERSION` file.

---

### `ws-cd-resolve` (scripting)

Lower-level executable used by the `ws cd` shell function. Prints the resolved path to stdout — useful in scripts.

```bash
ws-cd-resolve my_package          # prints source dir
ws-cd-resolve --install my_pkg    # prints install prefix
```

---

## Bash Completion

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

Workspaces are detected dynamically — no paths are hardcoded. Completion does **not** require the workspace or package to be sourced or installed.

---

## Developer Section

### Running Tests

To run the full Bats test suite:

```bash
make test
```

The Bats suite is split into one file per command under `tests/bats/`:

| File | Command | What it covers |
|------|---------|----------------|
| `ws_manager_cmd.bats` | `ws` main dispatcher | `--version`, `cd --help`, shell wrapper delegation |
| `ws_build_cmd.bats` | `ws build` | help output, duplicate package → both workspaces built |
| `ws_clean_cmd.bats` | `ws clean` | help output, duplicate package → both workspaces cleaned |
| `ws_cd_resolve_cmd.bats` | `ws cd` / `ws-cd-resolve` | source/install resolution, symlink source, duplicate package order |
| `ws_list_cmd.bats` | `ws list` | quiet-mode symlink metadata, `--installed` filter |
| `ws_open_cmd.bats` | `ws open` | symlink source path, not-installed error, launch artifact |
| `ws_config_cmd.bats` | `ws config` | idempotent set-build-program, set-editor with args |
| `ws_which_cmd.bats` | `ws which` | machine-mode symlink metadata, launch completion fallback |

A shared helper (`tests/bats/test_helper.bash`) provides `make_pkg`, `make_pkg_at`, and `set_test_editor_echo` used across suites.

### Local CI Run

For quick local validation (same flow as CI):

```bash
make ci-local
```

`ci-local` runs in an isolated fixture root under `/tmp/ws_manager_ci_local` and uses a temporary `HOME` inside that root. You can override this root with:

```bash
WS_CI_TMP_ROOT=/tmp/my_ws_ci_fixture make ci-local
```

This runs:
- shell syntax checks
- install smoke
- command smoke (`ws --version`, `ws build --help`, `ws-cd-resolve --help`, `ws doctor`)
- Bats tests
- uninstall smoke

### ROS Distro Compatibility

Works with any installed ROS 2 distro (**Humble**, **Iron**, **Jazzy**, **Kilted**, **Rolling**, etc.).
The tool reads `$ROS_DISTRO` at runtime — no distro-specific configuration is required or assumed.
`ws build` sources `/opt/ros/$ROS_DISTRO/setup.bash` when that file exists and `ROS_DISTRO` is set;
all other commands (`ws cd`, `ws list`, `ws which`, `ws open`, `ws config`) work without any ROS
environment sourced.

---

## Citing This Work

If you use `ws_manager` in your research, please cite it:

```bibtex
@software{ws_manager,
  author  = {Hulchuk, Vsevolod},
  title   = {ws\_manager: A workspace manager for ROS 2 colcon workspaces},
  year    = {2026},
  url     = {https://github.com/comrob/crl_ws_manager},
  license = {MIT}
}
```

A `CITATION.cff` file is also provided for automatic citation tools (GitHub "Cite this repository" button, Zenodo, etc.).

---

## License

[MIT](LICENSE) © 2026 Computational Robotics Lab (CRL), Czech Technical University in Prague

