#!/usr/bin/env bash
set -euo pipefail

# Pane jumplist navigator. Walks back/forward through focused-pane history and
# switches focus directly (no popup).
# Usage: jumplist_nav.sh --back | --forward

if [[ -z "${TMUX:-}" ]]; then
  exit 0
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jumplist_lib.sh
source "${CURRENT_DIR}/jumplist_lib.sh"

direction=""
case "${1:-}" in
--back) direction="back" ;;
--forward) direction="forward" ;;
*)
  tmux display-message "fuzzmux jumplist: usage: $(basename "$0") --back|--forward"
  exit 1
  ;;
esac

file="$(jumplist_history_file)"
declare -a hist
jumplist_load "$file" hist
cursor="$(jumplist_option '@fuzzmux-jump-cursor' '-1')"
[[ "$cursor" =~ ^-?[0-9]+$ ]] || cursor=-1

# Prune dead panes, rebuilding the list and remapping the cursor to the nearest
# surviving entry at or before its old position so indices stay consistent.
declare -A alive
while IFS= read -r pid; do
  [[ -n "$pid" ]] && alive["$pid"]=1
done < <(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)

declare -a pruned
new_cursor=-1
idx=0
for pid in "${hist[@]+"${hist[@]}"}"; do
  if [[ -n "${alive[$pid]:-}" ]]; then
    pruned+=("$pid")
    ((idx <= cursor)) && new_cursor=$((${#pruned[@]} - 1))
  fi
  ((idx++)) || true
done
hist=("${pruned[@]+"${pruned[@]}"}")
cursor=$new_cursor

# Compute the target index in the requested direction.
step=-1
[[ "$direction" == "forward" ]] && step=1
target_idx=$((cursor + step))

if ((target_idx < 0 || target_idx >= ${#hist[@]})); then
  jumplist_save "$file" hist
  if [[ "$direction" == "back" ]]; then
    tmux display-message "fuzzmux jumplist: no previous pane"
  else
    tmux display-message "fuzzmux jumplist: no next pane"
  fi
  exit 0
fi

target="${hist[target_idx]}"

# Persist the pruned history and arm the idempotent guard BEFORE switching: the
# focus hooks our switch triggers will see history[cursor] == target and no-op,
# so the jump itself does not create a spurious new history entry.
jumplist_save "$file" hist
tmux set-option -g '@fuzzmux-jump-cursor' "$target_idx"

# Query session/window separately to tolerate session names containing spaces.
sess="$(tmux display-message -p -t "$target" '#{session_name}')"
win="$(tmux display-message -p -t "$target" '#{window_index}')"
# Select the target pane BEFORE switching the client. switch-client fires focus
# hooks immediately; if the target were not already the active pane of its
# window, those hooks would record the stale active pane and defeat the
# idempotent guard (causing forward-tail loss and back/forward ping-pong).
tmux select-pane -t "$target"
tmux switch-client -t "${sess}:${win}"
