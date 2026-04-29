# Contributing

## Reporting issues

Open a GitHub issue. Please include:

- Output of `ws doctor`
- Output of `ws --version`
- OS and ROS distro (`echo $ROS_DISTRO`)
- The exact command you ran and the full output

## Making changes

1. Fork the repository and create a branch.
2. Make your changes — see the [repository layout](README.md#repository-layout) for where things live.
3. Validate your changes:
   ```bash
   make install
   source ~/.bashrc
   ws doctor
   ws build --help
   ws cd --help
   ```
4. Open a pull request with a description of what changed and why.

## Code style

- All scripts: `#!/usr/bin/env bash` + `set -euo pipefail`.
- Shared helpers go in `lib/ws_lib.sh` (sourced, not executed — no `set -euo pipefail` at top level).
- New subcommands: add a script in `bin/`, register it in `install.sh` (`COMMAND_NAMES` / `COMMANDS`), and add a dispatch case in `bin/ws_manager.sh`.
- Completion: update `__ws_complete_dispatch` in `completion/ws_manager.bash`.
- Keep user-visible strings consistent with existing messages (lowercase, no trailing period on errors).

## Release process

1. Update `VERSION`.
2. Tag: `git tag -a v$(cat VERSION) -m "Release $(cat VERSION)"`.
3. Push tag.
