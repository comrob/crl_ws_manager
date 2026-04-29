# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

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
