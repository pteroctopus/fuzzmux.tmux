#!/usr/bin/env bash
# fuzzmux.tmux - jump to a Claude Code agent's pane from outside tmux.
#
# Usage: claude_goto.sh <tmux-socket-path> <pane-id> [tmux-binary]
#
# Run when a desktop notification is clicked (see claude_hook.sh). Selects the
# pane and switches the most recently active tmux client to it; the focus hooks
# then mark the agent as seen. Silent no-op when the server, the pane or every
# client is gone. Kept bash 3.2 compatible: it runs with whatever bash the
# notification tool finds.
#
# Notification Center relaunches the notifier with a bare PATH, so the hook
# passes the tmux binary it used itself; failing that, look in the usual
# Homebrew locations as well.

sock="${1:-}"
pane="${2:-}"
tmux_bin="${3:-}"
[ -n "$sock" ] && [ -n "$pane" ] || exit 0
if [ -z "$tmux_bin" ] || [ ! -x "$tmux_bin" ]; then
  PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
  tmux_bin="$(command -v tmux 2>/dev/null)" || exit 0
fi

t() { "$tmux_bin" -S "$sock" "$@"; }

t display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1 || exit 0

client="$(t list-clients -F '#{client_activity} #{client_name}' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)"
[ -n "$client" ] || exit 0

# Query session/window separately to tolerate session names containing spaces.
session="$(t display-message -p -t "$pane" '#{session_name}' 2>/dev/null)" || exit 0
window="$(t display-message -p -t "$pane" '#{window_index}' 2>/dev/null)" || exit 0

# Select the pane before switching the client so focus hooks see the right pane.
t select-pane -t "$pane" 2>/dev/null
t switch-client -c "$client" -t "${session}:${window}" 2>/dev/null
exit 0
