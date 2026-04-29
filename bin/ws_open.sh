#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=../lib/ws_lib.sh
source "$SCRIPT_DIR/../lib/ws_lib.sh"

print_usage() {
  echo "Usage: ws open [--source|--install] <package_name>"
  echo "       ws open <package_name> [<launchfile>]"
  echo "       ws open <package_name> --launch <file>"
  echo "       ws open <package_name> --exe <name>"
  echo "       ws open <package_name> --config <file>"
  echo ""
  echo "Open the resolved package or artifact source path in the configured editor."
  echo "Artifact flags always resolve the source file (install path is used only"
  echo "as a fallback when the source is not found, following any install symlinks)."
  echo ""
  echo "Options:"
  echo "  --source            Open package source directory (default)"
  echo "  --install, -i       Open package install prefix/share directory"
  echo "  -l, --launch <f>    Resolve and open launch file from source"
  echo "  -e, --exe <name>    Resolve and open executable from source"
  echo "  -c, --config <f>    Resolve and open config file from source"
  echo "  -h, --help, help    Show this help"
  echo ""
  echo "Config keys: WS_EDITOR_PROGRAM, WS_EDITOR_ARGS"
  echo "Local config: $(ws_config_file)"
}

if ws_is_help_token "${1:-}"; then
  print_usage
  exit 0
fi

pkg_mode="source"   # source | install  (used when no artifact flag given)
pkg_name=""
artifact_type=""
artifact_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    help|-h|--help)
      print_usage
      exit 0
      ;;
    --source)
      pkg_mode="source"
      shift
      ;;
    --install|-i)
      pkg_mode="install"
      shift
      ;;
    -l|--launch)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a launch file name." >&2
        exit 1
      fi
      artifact_type="launch"
      artifact_name="$2"
      shift 2
      ;;
    -e|--exe)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires an executable name." >&2
        exit 1
      fi
      artifact_type="exe"
      artifact_name="$2"
      shift 2
      ;;
    -c|--config)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a config file name." >&2
        exit 1
      fi
      artifact_type="config"
      artifact_name="$2"
      shift 2
      ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      print_usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$pkg_name" ]]; then
        pkg_name="$1"
      elif [[ -z "$artifact_type" && -z "$artifact_name" ]]; then
        # Second positional argument is implicitly a launch file.
        artifact_type="launch"
        artifact_name="$1"
      else
        echo "Error: unexpected argument '$1'" >&2
        print_usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$pkg_name" ]]; then
  print_usage
  exit 0
fi

# ── Resolve target path ────────────────────────────────────────────────────
target_path=""

if [[ -n "$artifact_type" ]]; then
  # Artifact mode: resolve source (falling back to install symlink target).
  source_path="not-found"
  install_path="not-installed"
  ws_resolve_package_paths "$pkg_name" source_path install_path

  artifact_source="not-found"
  artifact_install="not-found"
  ws_resolve_artifact "$pkg_name" "$artifact_type" "$artifact_name" \
    "$source_path" "$install_path" artifact_source artifact_install

  if [[ "$artifact_source" != "not-found" ]]; then
    target_path="$artifact_source"
  elif [[ "$artifact_install" != "not-found" ]]; then
    # Follow a symlink to its source file; otherwise use install path.
    if [[ -L "$artifact_install" ]]; then
      resolved=$(readlink -f "$artifact_install" 2>/dev/null || echo "")
      target_path="${resolved:-$artifact_install}"
    else
      target_path="$artifact_install"
    fi
    echo "Note: source not found; opening install path: $target_path" >&2
  else
    echo "Error: '$artifact_name' ($artifact_type) not found for package '$pkg_name'." >&2
    exit 1
  fi
else
  # Package-directory mode: use the same shared resolver as ws_which.
  source_path="not-found"
  install_path="not-installed"
  ws_resolve_package_paths "$pkg_name" source_path install_path

  if [[ "$pkg_mode" == "install" ]]; then
    if [[ "$install_path" == "not-installed" ]]; then
      echo "Error: package '$pkg_name' is not installed." >&2
      exit 1
    fi
    target_path="$install_path"
  else
    if [[ "$source_path" != "not-found" ]]; then
      # If the source dir is a symlink, follow to the real repo.
      if [[ -L "$source_path" ]]; then
        resolved=$(readlink -f "$source_path" 2>/dev/null || echo "")
        target_path="${resolved:-$source_path}"
      else
        target_path="$source_path"
      fi
    elif [[ "$install_path" != "not-installed" ]]; then
      echo "Note: source not found; opening install path." >&2
      target_path="$install_path"
    else
      echo "Error: package '$pkg_name' not found in any detected workspace." >&2
      exit 1
    fi
  fi
fi

# ── Open in editor ─────────────────────────────────────────────────────────
editor_cmd=()
ws_editor_make_command editor_cmd "$target_path"

echo "Opening: $target_path"
printf 'Executing:'
printf ' %q' "${editor_cmd[@]}"
printf '\n'

"${editor_cmd[@]}"