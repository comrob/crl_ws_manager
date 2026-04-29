# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [0.2.0] - 2026-04-29

### Added
- `LICENSE` (MIT) — required for legal use and redistribution.
- `CITATION.cff` for automatic citation via GitHub and Zenodo.
- Citation section and license note in README.
- `[WARN]` tier in `ws doctor`: `colcon`, `ROS_DISTRO`, and workspace
  detection are now warnings (non-zero exit only on broken install),
  allowing the tool to be used on machines without ROS sourced.

### Changed
- `WS_DEFAULT_WORKSPACES` default changed from lab-internal `~/sw_ws ~/drv_ws`
  to community-neutral `~/ros2_ws ~/dev_ws` in `lib/ws_lib.sh`,
  `ws_init_config_file_if_missing`, and `examples/ws_config.bash`.
- `ws build` no longer assumes `jazzy` as a fallback distro — the ROS
  underlay is sourced only when `$ROS_DISTRO` is set and the file exists.
- `README`: license badge added; TL;DR and command examples use neutral
  workspace names; ROS distro compatibility note updated.
- CI: colcon installed system-wide (`sudo pip`) to prevent PATH mismatch
  when `HOME` is overridden to the fixture directory.
- Local runner: colcon resolved before `HOME` override so `require_cmd`
  works correctly; colcon symlinked into fixture `HOME/.local/bin` for
  `ws doctor`.

### Fixed
- Bats test edge cases: per-command split, symlink source, not-installed
  package, and duplicate package across workspaces.
- `ws_resolve_workspaces`: associative array key was literal `ws` instead
  of the workspace path variable, breaking multi-workspace package builds/cleans.
- `ws list` quiet-mode `printf` wrapped in `if` to prevent unintended
  exit under `set -e`.

## [0.1.0] - 2026-04-29

### Added
- Standard repository layout with `bin/`, `lib/`, `completion/`, and `examples/`.
- `Makefile` with `install`, `uninstall`, and `purge` targets.
- `VERSION` file and `ws --version` / `ws version` support.
- `ws doctor` diagnostics for PATH, config, ROS environment, `colcon`, and workspace detection.
- `ws update` to pull from git and reinstall.
- `CONTRIBUTING.md` and `examples/ws_config.bash`.
- GitHub Actions CI workflow for shell syntax and install smoke tests.

### Changed
- Install flow now supports both bash and zsh rc files.
- Workspace fallback paths are configurable via `WS_DEFAULT_WORKSPACES`.
- User-facing naming was made more community-neutral.
- Command dispatch in `ws_manager.sh` was deduplicated.
- All executable scripts in `bin/` now use `set -euo pipefail`.

### Fixed
- Symlink resolution for installed commands now follows real file paths.
- Removed stale `link_tools.sh` references.
- Removed obsolete fallback reliance on `~/.local/bin/ws_lib.sh`.
- Hardened installer backup handling and rc-file updates.
