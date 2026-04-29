#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=lib/ws_lib.sh
source "$SCRIPT_DIR/../lib/ws_lib.sh"

print_usage() {
  echo "Usage: ws cd [--source|--install] [-s|--include-system] <package_name>"
  echo "  --source   Resolve package source directory when available (default)"
  echo "  --install  Resolve package install prefix/share directory"
  echo "  -s, --include-system  Include system packages in autocomplete suggestions"
}

if ws_is_help_token "${1:-}"; then
  print_usage
  exit 0
fi

mode="source"
pkg_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    help|-h|--help)
      print_usage
      exit 0
      ;;
    -s|--include-system)
      # Autocomplete control flag. Resolution already supports both local and
      # system packages through ros2 pkg prefix.
      ;;
    --source)
      mode="source"
      ;;
    -i|--install)
      mode="install"
      ;;
    *)
      if [[ -z "$pkg_name" ]]; then
        pkg_name="$1"
      else
        echo "Error: Unexpected argument '$1'" >&2
        print_usage >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "$pkg_name" ]]; then
  print_usage
  exit 0
fi

# ── Resolve via shared workspace detection (same backend as ws which / ws open)
source_path="not-found"
install_path="not-installed"
ws_resolve_package_paths "$pkg_name" source_path install_path

if [[ "$mode" == "install" ]]; then
  if [[ "$install_path" != "not-installed" ]]; then
    echo "$install_path"
    exit 0
  fi
  # Fall back: try system package via ros2 pkg prefix.
  pkg_prefix=$(ros2 pkg prefix "$pkg_name" 2>/dev/null || true)
  if [[ -n "$pkg_prefix" ]]; then
    target="$pkg_prefix/share/$pkg_name"
    [[ -d "$target" ]] && { echo "$target"; exit 0; }
    [[ -d "$pkg_prefix" ]] && { echo "$pkg_prefix"; exit 0; }
  fi
  echo "Error: install path not found for '$pkg_name'." >&2
  exit 1
fi

# Source mode (default).
if [[ "$source_path" != "not-found" ]]; then
  # Follow symlinks to the real repo directory.
  if [[ -L "$source_path" ]]; then
    resolved=$(readlink -f "$source_path" 2>/dev/null || echo "")
    echo "${resolved:-$source_path}"
  else
    echo "$source_path"
  fi
  exit 0
fi

# No source in workspaces — try system package share dir as last resort.
pkg_prefix=$(ros2 pkg prefix "$pkg_name" 2>/dev/null || true)
if [[ -n "$pkg_prefix" ]]; then
  target="$pkg_prefix/share/$pkg_name"
  [[ -d "$target" ]] && { echo "$target"; exit 0; }
fi

echo "Error: Cannot find package '$pkg_name' in any detected workspace." >&2
exit 1
