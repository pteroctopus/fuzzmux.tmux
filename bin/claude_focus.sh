#!/usr/bin/env bash
# fuzzmux.tmux - marks a Claude Code agent as seen.
#
# Invoked (backgrounded) by the tmux focus hooks that scripts/init.sh installs,
# with the newly focused #{pane_id}. When that pane holds an agent in the
# "waiting" state (a finished turn nobody has looked at yet), the state drops to
# "idle": you are looking at it now. "permission" and "question" stay, because
# they are pending whether you looked or not.

[[ -n "${TMUX:-}" ]] || exit 0

pane="${1:-}"
if [[ ! "$pane" =~ ^%[0-9]+$ ]]; then
  pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
fi
[[ "$pane" =~ ^%[0-9]+$ ]] || exit 0

state="$(tmux show-option -pqv -t "$pane" @fuzzmux-claude-state 2>/dev/null || true)"
[[ "$state" == "waiting" ]] || exit 0

tmux set-option -p -t "$pane" @fuzzmux-claude-state idle \; \
  set-option -p -t "$pane" @fuzzmux-claude-since "$(date +%s)" 2>/dev/null || true

# Status-line counts changed: redraw every client.
for client in $(tmux list-clients -F '#{client_name}' 2>/dev/null); do
  tmux refresh-client -S -t "$client" 2>/dev/null || true
done
exit 0
