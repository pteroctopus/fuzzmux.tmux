#!/usr/bin/env bash
set -euo pipefail

# Pane jumplist recorder. Invoked (backgrounded) by tmux focus hooks. Appends the
# newly-focused pane to the global history and maintains the cursor. Standard
# jumplist semantics: a new focus drops the forward tail.

if [[ -z "${TMUX:-}" ]]; then
  exit 0
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jumplist_lib.sh
source "${CURRENT_DIR}/jumplist_lib.sh"

# Respect the master toggle.
[[ "$(jumplist_option '@fuzzmux-jumplist-enabled' '1')" == "1" ]] || exit 0

# Resolve the incoming pane id. The hook passes #{pane_id}; validate it and fall
# back to the active pane if it is missing or unexpanded.
incoming="${1:-}"
if [[ ! "$incoming" =~ ^%[0-9]+$ ]]; then
  incoming="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
fi
[[ "$incoming" =~ ^%[0-9]+$ ]] || exit 0

file="$(jumplist_history_file)"
declare -a hist
jumplist_load "$file" hist
cursor="$(jumplist_option '@fuzzmux-jump-cursor' '-1')"
[[ "$cursor" =~ ^-?[0-9]+$ ]] || cursor=-1

# Idempotent guard: if we already sit on this pane, do nothing. This dedupes the
# multi-hook double-fire AND absorbs our own back/forward jumps (the navigator
# sets the cursor to the target BEFORE switching, so the resulting focus is a
# no-op here).
if ((cursor >= 0 && cursor < ${#hist[@]})) && [[ "${hist[cursor]}" == "$incoming" ]]; then
  exit 0
fi

# Normal new focus: drop the forward tail (entries after the cursor), append.
keep=$((cursor + 1))
((keep < 0)) && keep=0
hist=("${hist[@]:0:keep}")
hist+=("$incoming")

# Cap history length, dropping oldest entries.
max="$(jumplist_option '@fuzzmux-jumplist-max' '100')"
[[ "$max" =~ ^[0-9]+$ ]] || max=100
if ((max > 0 && ${#hist[@]} > max)); then
  hist=("${hist[@]: -max}")
fi

cursor=$((${#hist[@]} - 1))
jumplist_save "$file" hist
tmux set-option -g '@fuzzmux-jump-cursor' "$cursor"
