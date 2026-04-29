# Load shared workspace helpers (path normalisation, env detection, package lookup).
# ws_lib.sh lives at ../lib/ relative to this file (resolved through the symlink
# to its real location in the repo).
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" ]]; then
  _ws_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)"
else
  _ws_lib_dir="$HOME/.local/bin"
fi
if [[ -f "$_ws_lib_dir/ws_lib.sh" ]]; then
  # shellcheck source=../lib/ws_lib.sh
  source "$_ws_lib_dir/ws_lib.sh"
fi
unset _ws_lib_dir

# Internal ws cd implementation.
__ws_cd() {
  local resolve_cmd
  if command -v ws-cd-resolve >/dev/null 2>&1; then
    resolve_cmd="ws-cd-resolve"
  elif [[ -x "$HOME/.local/bin/ws-cd-resolve" ]]; then
    resolve_cmd="$HOME/.local/bin/ws-cd-resolve"
  else
    echo "Error: ws-cd-resolve not found on PATH. Run ./install.sh and source ~/.bashrc."
    return 1
  fi

  if [[ $# -eq 0 ]]; then
    "$resolve_cmd" --help
    return 0
  fi

  if ws_is_help_token "${1:-}"; then
    "$resolve_cmd" --help
    return $?
  fi

  local target_dir
  target_dir=$("$resolve_cmd" "$@") || return $?

  cd "$target_dir" || return 1
}

# Unified workspace manager wrapper
ws() {
  local cmd="${1:-}"
  if [[ -z "$cmd" ]]; then
    ws_print_main_help
    return 0
  fi

  if ws_is_help_token "$cmd"; then
    ws_print_main_help
    return 0
  fi

  shift
  case "$cmd" in
    cd)
      __ws_cd "$@"
      ;;
    build)
      "$HOME/.local/bin/ws" build "$@"
      ;;
    clean)
      "$HOME/.local/bin/ws" clean "$@"
      ;;
    list)
      "$HOME/.local/bin/ws" list "$@"
      ;;
    open)
      "$HOME/.local/bin/ws" open "$@"
      ;;
    config)
      "$HOME/.local/bin/ws" config "$@"
      ;;
    which)
      "$HOME/.local/bin/ws" which "$@"
      ;;
    update|version|--version|doctor)
      command ws "$cmd" "$@"
      ;;
    *)
      echo "Usage: ws [cd | build | clean | list | open | config | which] <args>"
      return 1
      ;;
  esac
}

# Compatibility alias.
roscd() {
  ws cd "$@"
}

__ws_collect_workspaces_from_words() {
  local out_name="$1"
  local -n out_ref="$out_name"
  local -a words=("${@:2}")
  local i=0

  out_ref=()
  while [[ $i -lt ${#words[@]} ]]; do
    case "${words[$i]}" in
      -w|--ws)
        if [[ $((i + 1)) -lt ${#words[@]} ]]; then
          out_ref+=("$(ws_normalize_path "${words[$((i + 1))]}")")
          i=$((i + 2))
          continue
        fi
        ;;
    esac
    i=$((i + 1))
  done

  if [[ ${#out_ref[@]} -eq 0 ]]; then
    # Delegate to the shared library helper (includes default fallbacks).
    ws_detect_from_env "$out_name"
  fi
}

# Kept for backwards compatibility; delegates to the shared library.
__ws_detect_workspaces_from_env() {
  ws_detect_from_env "$1"
}

# ---------------------------------------------------------------------------
# __ws_complete_workspace_arg  current-word
#   Smart workspace completion for the value after -w/--ws:
#   • Starts with ~ or /  →  path completion (supports any directory, even
#     workspaces that are not yet built / sourced).
#   • Otherwise           →  short basenames of detected workspaces so the
#     user can type "sw_ws" and ws_normalize_path will expand it at runtime.
# ---------------------------------------------------------------------------
__ws_complete_workspace_arg() {
  local cur="$1"

  if [[ "$cur" == "~/"* ]]; then
    # Expand ~ → $HOME, run directory completion, then re-prefix with ~/
    local expanded="${cur/#\~/$HOME}"
    local -a matches=()
    mapfile -t matches < <(compgen -d -- "$expanded")
    COMPREPLY=( "${matches[@]/#$HOME/\~}" )
  elif [[ "$cur" == /* ]]; then
    COMPREPLY=( $(compgen -d -- "$cur") )
  else
    # Offer short basenames of detected workspaces.
    local -a _detected=()
    ws_detect_from_env _detected
    local -a _names=()
    local _ws
    for _ws in "${_detected[@]}"; do
      _names+=("$(basename "$_ws")")
    done
    COMPREPLY=( $(compgen -W "${_names[*]}" -- "$cur") )
  fi
}

__ws_list_packages() {
  local include_system="false"
  if [[ "${1:-}" == "--include-system" ]]; then
    include_system="true"
    shift
  fi

  local -a workspaces=()
  __ws_collect_workspaces_from_words workspaces "$@"

  {
    local ws pkg_xml pkg_name
    for ws in "${workspaces[@]}"; do
      if [[ -d "$ws/src" ]]; then
        while IFS= read -r -d '' pkg_xml; do
          pkg_name=$(sed -n 's:.*<name>[[:space:]]*\([^<]*\)[[:space:]]*</name>.*:\1:p' "$pkg_xml" | head -n 1)
          if [[ -n "$pkg_name" ]]; then
            printf '%s\n' "$pkg_name"
          fi
        done < <(find -L "$ws/src" -type f -name package.xml -print0 2>/dev/null)
      fi
    done

    if [[ "$include_system" == "true" ]] && command -v ros2 >/dev/null 2>&1; then
      ros2 pkg list 2>/dev/null || true
    fi
  } | sort -u
}

__ws_complete() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "build clean cd list open config which update doctor version help --help -h" -- "$cur") )
    return 0
  fi

  if [[ "${COMP_WORDS[1]}" == "build" ]]; then
    if [[ "$prev" == "-w" || "$prev" == "--ws" ]]; then
      __ws_complete_workspace_arg "$cur"
      return 0
    fi

    if [[ "$prev" == "-p" || "$prev" == "--packages" ]]; then
      COMPREPLY=( $(compgen -W "$(__ws_list_packages "${COMP_WORDS[@]:1}")" -- "$cur") )
      return 0
    fi

    if [[ "$cur" == -* ]]; then
      COMPREPLY=( $(compgen -W "--all --clean -w --ws -p --packages -h --help" -- "$cur") )
      return 0
    fi

    COMPREPLY=( $(compgen -W "$(__ws_list_packages "${COMP_WORDS[@]:1}")" -- "$cur") )
    return 0
  fi

  if [[ "${COMP_WORDS[1]}" == "clean" ]]; then
    if [[ "$cur" == -* ]]; then
      COMPREPLY=( $(compgen -W "-w --ws -p --packages --clean-all -h --help" -- "$cur") )
      return 0
    fi

    if [[ "$prev" == "-w" || "$prev" == "--ws" ]]; then
      __ws_complete_workspace_arg "$cur"
      return 0
    fi

    if [[ "$prev" == "-p" || "$prev" == "--packages" ]]; then
      COMPREPLY=( $(compgen -W "$(__ws_list_packages "${COMP_WORDS[@]:1}")" -- "$cur") )
      return 0
    fi

    COMPREPLY=( $(compgen -W "$(__ws_list_packages "${COMP_WORDS[@]:1}")" -- "$cur") )
    return 0
  fi

  if [[ "${COMP_WORDS[1]}" == "cd" ]]; then
    if [[ "$prev" == "-w" || "$prev" == "--ws" ]]; then
      __ws_complete_workspace_arg "$cur"
      return 0
    fi

    if [[ "$cur" == -* ]]; then
      COMPREPLY=( $(compgen -W "--source --install --include-system -s -i -h --help" -- "$cur") )
      return 0
    fi

    if [[ "$prev" != "cd" && "$prev" != "--source" && "$prev" != "--install" && "$prev" != "--include-system" && "$prev" != "-s" && "$prev" != "-i" ]]; then
      return 0
    fi

    local include_system="false"
    local w
    for w in "${COMP_WORDS[@]:2}"; do
      if [[ "$w" == "-s" || "$w" == "--include-system" ]]; then
        include_system="true"
        break
      fi
    done

    if [[ "$include_system" == "true" ]]; then
      COMPREPLY=( $(compgen -W "$(__ws_list_packages --include-system cd)" -- "$cur") )
    else
      COMPREPLY=( $(compgen -W "$(__ws_list_packages cd)" -- "$cur") )
    fi
    return 0
  fi

  if [[ ${#COMP_WORDS[@]} -gt 0 && "${COMP_WORDS[0]}" == "ws-build" ]]; then
    if [[ "$prev" == "-w" || "$prev" == "--ws" ]]; then
      __ws_complete_workspace_arg "$cur"
      return 0
    fi

    if [[ "$prev" == "-p" || "$prev" == "--packages" ]]; then
      COMPREPLY=( $(compgen -W "$(__ws_list_packages "${COMP_WORDS[@]}")" -- "$cur") )
      return 0
    fi

    if [[ "$cur" == -* ]]; then
      COMPREPLY=( $(compgen -W "--all --clean -w --ws -p --packages -h --help" -- "$cur") )
      return 0
    fi

    COMPREPLY=( $(compgen -W "$(__ws_list_packages "${COMP_WORDS[@]}")" -- "$cur") )
    return 0
  fi

  if [[ ${#COMP_WORDS[@]} -gt 0 && "${COMP_WORDS[0]}" == "ws-cd-resolve" ]]; then
    if [[ "$cur" == -* ]]; then
      COMPREPLY=( $(compgen -W "--source --install --include-system -s -i -h --help" -- "$cur") )
      return 0
    fi

    local include_system="false"
    local w
    for w in "${COMP_WORDS[@]:1}"; do
      if [[ "$w" == "-s" || "$w" == "--include-system" ]]; then
        include_system="true"
        break
      fi
    done

    if [[ "$include_system" == "true" ]]; then
      COMPREPLY=( $(compgen -W "$(__ws_list_packages --include-system cd)" -- "$cur") )
    else
      COMPREPLY=( $(compgen -W "$(__ws_list_packages cd)" -- "$cur") )
    fi
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Completion for ws open.
# ---------------------------------------------------------------------------
__ws_complete_open() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Extract the package name from already-typed words.
  local package_name=""
  local i token
  for ((i=2; i<COMP_CWORD; i++)); do
    token="${COMP_WORDS[$i]}"
    case "$token" in
      --source|--install|-i|-l|--launch|-e|--exe|-c|--config)
        if [[ "$token" == -l || "$token" == --launch || \
              "$token" == -e || "$token" == --exe || \
              "$token" == -c || "$token" == --config ]]; then
          i=$((i + 1))   # skip value
        fi
        ;;
      -*)
        ;;
      *)
        if [[ -z "$package_name" ]]; then
          package_name="$token"
        fi
        ;;
    esac
  done

  if [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W "--source --install -i -l --launch -e --exe -c --config -h --help" -- "$cur") )
    return 0
  fi

  # Value completion for artifact flags.
  if [[ "$prev" == "-l" || "$prev" == "--launch" ]]; then
    if [[ -n "$package_name" ]]; then
      COMPREPLY=( $(compgen -W "$(ws_list_installed_launchfile_basenames "$package_name")" -- "$cur") )
    fi
    return 0
  fi
  if [[ "$prev" == "-e" || "$prev" == "--exe" ]]; then
    if [[ -n "$package_name" ]]; then
      COMPREPLY=( $(compgen -W "$(ws_list_installed_executable_basenames "$package_name")" -- "$cur") )
    fi
    return 0
  fi
  if [[ "$prev" == "-c" || "$prev" == "--config" ]]; then
    if [[ -n "$package_name" ]]; then
      COMPREPLY=( $(compgen -W "$(ws_list_installed_config_basenames "$package_name")" -- "$cur") )
    fi
    return 0
  fi

  # Package name completion when it hasn't been typed yet.
  if [[ -z "$package_name" || \
        "$prev" == "open" || "$prev" == "--source" || \
        "$prev" == "--install" || "$prev" == "-i" ]]; then
    COMPREPLY=( $(compgen -W "$(__ws_list_packages open)" -- "$cur") )
    return 0
  fi

  # Second positional argument: implicit launch file completion.
  COMPREPLY=( $(compgen -W "$(ws_list_installed_launchfile_basenames "$package_name")" -- "$cur") )
}

# ---------------------------------------------------------------------------
# Completion for ws config.
# ---------------------------------------------------------------------------
__ws_complete_config() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  if [[ $COMP_CWORD -eq 2 ]]; then
    COMPREPLY=( $(compgen -W "show path init edit set-editor set-build-program set-build-subcommand set-build-args require-all help -h --help" -- "$cur") )
    return 0
  fi

  if [[ "$prev" == "require-all" ]]; then
    COMPREPLY=( $(compgen -W "true false" -- "$cur") )
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Completion for ws which.
# ---------------------------------------------------------------------------
__ws_complete_which() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local package_name=""
  local i token
  for ((i=2; i<COMP_CWORD; i++)); do
    token="${COMP_WORDS[$i]}"
    case "$token" in
      -l|--launch|-e|--exe|-c|--config)
        i=$((i + 1))
        ;;
      -* )
        ;;
      *)
        if [[ -z "$package_name" ]]; then
          package_name="$token"
        fi
        ;;
    esac
  done

  if [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W "-l --launch -e --exe -c --config -m --machine -h --help" -- "$cur") )
    return 0
  fi

  # Complete launchfiles when requested explicitly.
  if [[ "$prev" == "-l" || "$prev" == "--launch" ]]; then
    if [[ -n "$package_name" ]]; then
      COMPREPLY=( $(compgen -W "$(ws_list_installed_launchfile_basenames "$package_name")" -- "$cur") )
    fi
    return 0
  fi

  # Complete executables when requested explicitly.
  if [[ "$prev" == "-e" || "$prev" == "--exe" ]]; then
    if [[ -n "$package_name" ]]; then
      COMPREPLY=( $(compgen -W "$(ws_list_installed_executable_basenames "$package_name")" -- "$cur") )
    fi
    return 0
  fi

  # Complete config files when requested explicitly.
  if [[ "$prev" == "-c" || "$prev" == "--config" ]]; then
    if [[ -n "$package_name" ]]; then
      COMPREPLY=( $(compgen -W "$(ws_list_installed_config_basenames "$package_name")" -- "$cur") )
    fi
    return 0
  fi

  # First positional argument is the package.
  if [[ -z "$package_name" ]]; then
    COMPREPLY=( $(compgen -W "$(__ws_list_packages which)" -- "$cur") )
    return 0
  fi

  # Second positional argument: launchfile completion for selected package.
  COMPREPLY=( $(compgen -W "$(ws_list_installed_launchfile_basenames "$package_name")" -- "$cur") )
}

# ---------------------------------------------------------------------------
# Completion for ws list.
# ---------------------------------------------------------------------------
__ws_complete_list() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Value after -w/--ws.
  if [[ "$prev" == "-w" || "$prev" == "--ws" ]]; then
    __ws_complete_workspace_arg "$cur"
    return 0
  fi

  if [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W "-p --packages -W --workspaces -w --ws --installed -q --quiet -h --help" -- "$cur") )
    return 0
  fi
}

# Completion dispatcher: route ws list to its own handler.
__ws_complete_dispatch() {
  if [[ "${COMP_WORDS[1]:-}" == "list" ]]; then
    __ws_complete_list
    return 0
  fi
  if [[ "${COMP_WORDS[1]:-}" == "open" ]]; then
    __ws_complete_open
    return 0
  fi
  if [[ "${COMP_WORDS[1]:-}" == "config" ]]; then
    __ws_complete_config
    return 0
  fi
  if [[ "${COMP_WORDS[1]:-}" == "which" ]]; then
    __ws_complete_which
    return 0
  fi
  __ws_complete "$@"
}

complete -F __ws_complete_dispatch ws
complete -F __ws_complete ws-build
complete -F __ws_complete ws-cd-resolve
complete -F __ws_complete_list ws-list
complete -F __ws_complete_open ws-open
complete -F __ws_complete_config ws-config
complete -F __ws_complete_which ws-which
