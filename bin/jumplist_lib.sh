#!/usr/bin/env bash
# Shared helpers for the fuzzmux pane jumplist.
# Sourced by jumplist_record.sh and jumplist_nav.sh - not executed directly.

# Resolve the per-server history file, creating a private parent directory.
# Path: <base>/fuzzmux/jumplist-<server_pid>.list
#   base = $XDG_RUNTIME_DIR (Linux) || $TMPDIR (macOS) || /tmp
# Keyed by the tmux server pid so multiple servers never clobber each other and
# the file is naturally abandoned when the server dies.
jumplist_history_file() {
  local base dir server_pid
  base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
  dir="${base%/}/fuzzmux"
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  server_pid="$(tmux display-message -p '#{pid}')"
  printf '%s/jumplist-%s.list' "$dir" "$server_pid"
}

# Read a global tmux option, falling back to a default when unset/empty.
jumplist_option() {
  local value
  value="$(tmux show-option -gqv "$1")"
  echo "${value:-$2}"
}

# Load the history file into the named array (nameref). Empty if file absent.
jumplist_load() {
  local file=$1
  # shellcheck disable=SC2178  # _jl_arr is a nameref to an array
  local -n _jl_arr=$2
  _jl_arr=()
  [[ -f "$file" ]] && mapfile -t _jl_arr <"$file"
  return 0
}

# Write the named array (nameref) to the history file, one entry per line.
jumplist_save() {
  local file=$1
  # shellcheck disable=SC2178  # _jl_arr is a nameref to an array
  local -n _jl_arr=$2
  if ((${#_jl_arr[@]})); then
    printf '%s\n' "${_jl_arr[@]}" >"$file"
  else
    : >"$file"
  fi
}
