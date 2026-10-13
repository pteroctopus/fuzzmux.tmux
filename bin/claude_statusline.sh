#!/usr/bin/env bash
# fuzzmux.tmux - Claude Code status line wrapper.
#
# Claude Code runs the configured status line command with session JSON on
# stdin after every change (debounced). This wrapper records the context
# window usage from that JSON as a user option on the pane Claude runs in:
#
#   @fuzzmux-claude-context   percent of the context window used (integer)
#
# and then runs your real status line command with the same JSON, printing
# whatever it prints. Installed by `bin/claude_hooks_install.sh --statusline`,
# which wraps the command already in settings.json:
#
#   "statusLine": {"type": "command",
#                  "command": "\"<plugin>/bin/claude_statusline.sh\" 'npx -y ccstatusline@latest'"}
#
# Without an inner command it prints `ctx NN%` itself, so the status line row is
# never empty. Kept bash 3.2 compatible; every path exits quietly.

input=""
if [ ! -t 0 ]; then
  input="$(cat 2>/dev/null)"
fi

record() {
  [ -n "${TMUX:-}" ] || return 0
  command -v tmux >/dev/null 2>&1 || return 0

  local pct="" pane="${TMUX_PANE:-}" sid="" file=""
  if command -v jq >/dev/null 2>&1; then
    pct="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)"
    [ -n "$pane" ] || sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  else
    pct="$(printf '%s' "$input" | sed -n 's/.*"used_percentage":[[:space:]]*\([0-9.]*\).*/\1/p' | head -n 1)"
    [ -n "$pane" ] || sid="$(printf '%s' "$input" | sed -n 's/.*"session_id":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  fi
  pct="${pct%%.*}"
  case "$pct" in
  '' | *[!0-9]*) return 0 ;;
  esac

  # No $TMUX_PANE (started outside the pane's shell): find the pane through
  # Claude's own state file for this session.
  if [ -z "$pane" ] && [ -n "$sid" ]; then
    file="$(grep -l -- "\"sessionId\":\"$sid\"" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/"*.json 2>/dev/null | head -n 1)"
    [ -n "$file" ] && pane="$(sed -n 's/.*"tmux":"[^"]*\.\(%[0-9]*\)".*/\1/p' "$file" | head -n 1)"
  fi
  case "$pane" in
  %[0-9]*) tmux set-option -p -t "$pane" @fuzzmux-claude-context "$pct" 2>/dev/null ;;
  esac
  LAST_PCT="$pct"
}

LAST_PCT=""
record

if [ -n "${1:-}" ]; then
  printf '%s' "$input" | bash -c "$1"
  exit $?
fi
[ -n "$LAST_PCT" ] && printf 'ctx %s%%\n' "$LAST_PCT"
exit 0
