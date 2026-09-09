#!/usr/bin/env bash
# fuzzmux.tmux - Claude Code hook receiver.
#
# Registered in Claude Code's hook settings (see bin/claude_hooks_install.sh) as
#   "<plugin>/bin/claude_hook.sh <event>"
# Claude Code runs it with the hook payload on stdin and the environment of the
# Claude process, which includes $TMUX and $TMUX_PANE when Claude was started
# inside a tmux pane. The script records the agent's state as user options on
# that pane and shows a tmux status-line message when the agent needs the user.
#
# Pane options written:
#   @fuzzmux-claude-state   permission | question | waiting | working | idle
#   @fuzzmux-claude-since   epoch seconds when the state was entered
#   @fuzzmux-claude-detail  e.g. the tool awaiting permission
#   @fuzzmux-claude-mode    Claude's permission mode (default, acceptEdits, plan,
#                           auto, dontAsk, bypassPermissions), refreshed on
#                           every event so mode switches show up
#
# "waiting" means a finished turn nobody has looked at yet; bin/claude_focus.sh
# (tmux focus hooks) drops it to "idle" when the pane gains focus, and a turn
# that finishes while its pane is focused goes to "idle" directly.
#
# Global options read (all optional):
#   @fuzzmux-claude-notify              1 (default) | 0   status-line message on/off
#   @fuzzmux-claude-notify-focused      0 (default) | 1   also notify for the pane in view
#   @fuzzmux-claude-notify-duration     milliseconds the message stays (default 5000)
#   @fuzzmux-claude-notify-bell         0 (default) | 1   also ring the pane's bell
#   @fuzzmux-claude-notify-desktop      0 (default) | 1   also send a desktop notification
#                                       (macOS: terminal-notifier, click jumps to the
#                                       pane; osascript fallback; Linux: notify-send)
#   @fuzzmux-claude-notify-desktop-app  bundle id to activate on click (default: the
#                                       terminal tmux was started from)
#   @fuzzmux-claude-focus-check         terminal (default) | pane   what "looking at the
#                                       pane" means: the active pane of a client whose
#                                       terminal window has OS focus (tmux focus events),
#                                       or merely the active pane of an attached client
#
# Kept bash 3.2 compatible and fast: it must never slow down or break Claude
# Code, so every path exits 0.

# Drain stdin so Claude never sees a broken pipe, but never block on a TTY.
input=""
if [ ! -t 0 ]; then
  input="$(cat 2>/dev/null)"
fi

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

event="${1:-}"
pane="$TMUX_PANE"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Field separator for tmux output: not whitespace, so empty fields survive `read`.
US="$(printf '\037')"

# Minimal JSON extraction for flat string fields ("key": "value").
json_field() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  if [[ "$input" =~ $re ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# Read a global tmux option, falling back to a default when unset/empty.
opt() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  printf '%s' "${value:-$2}"
}

current="$(tmux show-option -pqv -t "$pane" @fuzzmux-claude-state 2>/dev/null)"

# True when the user is looking at the agent's pane right now: it is the active
# pane of the current window, and (default "terminal" check) a client showing
# that session has OS focus, which tmux learns from the terminal's focus events.
# With Alt-Tab to another app the client loses "focused" and the agent is
# treated as unwatched. Memoised: at most one evaluation per hook run.
FOCUSED=""
pane_focused() {
  if [ -z "$FOCUSED" ]; then
    FOCUSED=0
    if [ "$(tmux display-message -p -t "$pane" '#{pane_active}#{window_active}' 2>/dev/null)" = 11 ]; then
      case "$(opt @fuzzmux-claude-focus-check terminal)" in
      pane)
        [ "$(tmux display-message -p -t "$pane" '#{?session_attached,1,0}' 2>/dev/null)" = 1 ] && FOCUSED=1
        ;;
      *)
        tmux list-clients -t "$pane" -F '#{client_flags}' 2>/dev/null | grep -q 'focused' && FOCUSED=1
        ;;
      esac
    fi
  fi
  [ "$FOCUSED" = 1 ]
}

state=""
detail=""
verb=""
notify=0

case "$event" in
session-start)
  # A compaction happens mid-turn: leave the state alone. Every other start
  # (startup, clear, resume, fork) sits at the prompt with nothing unread.
  [ "$(json_field source)" = compact ] && exit 0
  state=idle
  ;;
prompt)
  state=working
  ;;
permission)
  # PermissionRequest: a tool call waits for approval.
  state=permission
  detail="$(json_field tool_name)"
  verb="needs permission${detail:+ for $detail}"
  notify=1
  ;;
notify-permission)
  # Notification(permission_prompt) follows PermissionRequest a few seconds
  # later; only speak once.
  [ "$current" = permission ] && exit 0
  state=permission
  verb="needs permission"
  notify=1
  ;;
question)
  # PreToolUse(AskUserQuestion): Claude is about to ask the user.
  state=question
  verb="asks a question"
  notify=1
  ;;
tool-done)
  # PostToolUse / PostToolUseFailure: approval or answer given, Claude goes on.
  state=working
  ;;
stop)
  if pane_focused; then
    # You watched it finish: nothing unread. Message only if asked for.
    state=idle
    verb="finished"
    [ "$(opt @fuzzmux-claude-notify-focused 0)" = 1 ] && notify=1
  else
    state=waiting
    verb="finished, waiting for input"
    notify=1
  fi
  ;;
notify-idle)
  # Notification(idle_prompt): about a minute without input after Claude went
  # idle. Remind about an unread turn; never touch a pending prompt; a "working"
  # agent that is idle now was interrupted (no Stop fires for Esc), so it holds
  # nothing unread.
  case "$current" in
  permission | question) exit 0 ;;
  waiting)
    state=waiting
    verb="still waiting for input"
    notify=1
    ;;
  working) state=idle ;;
  *) exit 0 ;;
  esac
  ;;
session-end)
  tmux set-option -pu -t "$pane" @fuzzmux-claude-state \; \
    set-option -pu -t "$pane" @fuzzmux-claude-since \; \
    set-option -pu -t "$pane" @fuzzmux-claude-detail \; \
    set-option -pu -t "$pane" @fuzzmux-claude-mode 2>/dev/null
  exit 0
  ;;
*)
  exit 0
  ;;
esac

# Record the state in one tmux call; keep @fuzzmux-claude-since when the state
# did not change. The permission mode rides along whenever the payload has it.
mode="$(json_field permission_mode)"
if [ "$current" != "$state" ]; then
  tmux set-option -p -t "$pane" @fuzzmux-claude-state "$state" \; \
    set-option -p -t "$pane" @fuzzmux-claude-since "$(date +%s)" \; \
    set-option -p -t "$pane" @fuzzmux-claude-detail "$detail" \; \
    set-option -p -t "$pane" @fuzzmux-claude-mode "${mode:-$(tmux show-option -pqv -t "$pane" @fuzzmux-claude-mode 2>/dev/null)}" 2>/dev/null
elif [ -n "$detail" ] || [ -n "$mode" ]; then
  tmux set-option -p -t "$pane" @fuzzmux-claude-detail "${detail:-$(tmux show-option -pqv -t "$pane" @fuzzmux-claude-detail 2>/dev/null)}" \; \
    set-option -p -t "$pane" @fuzzmux-claude-mode "${mode:-$(tmux show-option -pqv -t "$pane" @fuzzmux-claude-mode 2>/dev/null)}" 2>/dev/null
fi

[ "$notify" = 1 ] || exit 0

# The user is looking at this pane already: stay quiet unless asked otherwise.
if pane_focused && [ "$(opt @fuzzmux-claude-notify-focused 0)" != 1 ]; then
  exit 0
fi

info="$(tmux display-message -p -t "$pane" \
  "#{session_name}${US}#{window_index}${US}#{pane_index}${US}#{pane_title}${US}#{pane_tty}" 2>/dev/null)" || exit 0
IFS="$US" read -r session window index title tty <<EOF_INFO
$info
EOF_INFO

# Strip the glyph (U+2733) Claude Code prepends to the pane title.
glyph="$(printf '\342\234\263')"
title="${title#"${glyph}" }"
title="${title#"${glyph}"}"
where="@${session} #${window}.%${index}"

# Channel 1: tmux status-line message on every client. The status line is
# refreshed either way so the summary counts follow the state change.
show_message=0
[ "$(opt @fuzzmux-claude-notify 1)" = 1 ] && show_message=1
message="Claude ${verb}: ${where}${title:+ (${title})}"
message="${message//#/##}" # literal '#' in a tmux format
duration="$(opt @fuzzmux-claude-notify-duration 5000)"
for client in $(tmux list-clients -F '#{client_name}' 2>/dev/null); do
  [ "$show_message" = 1 ] && tmux display-message -c "$client" -d "$duration" "$message" 2>/dev/null
  tmux refresh-client -S -t "$client" 2>/dev/null
done

# Channel 2: bell in the pane, so tmux's monitor-bell flags the window (tmux
# alert scope: only visible within the agent's own session).
if [ "$(opt @fuzzmux-claude-notify-bell 0)" = 1 ] && [ -n "$tty" ] && [ -w "$tty" ]; then
  printf '\a' >"$tty" 2>/dev/null
fi

# Channel 3: desktop notification, for when you are in another application.
# Sent in the background so a slow notifier never delays Claude Code.
desktop_notify() {
  local subtitle="$1" body="$2" group="$3" app goto sock tmux_bin
  case "$(uname -s 2>/dev/null)" in
  Darwin)
    if command -v terminal-notifier >/dev/null 2>&1; then
      # -group replaces the previous notification of the same agent; -execute
      # jumps to the pane on click and -activate brings the terminal forward.
      app="$(opt @fuzzmux-claude-notify-desktop-app "${__CFBundleIdentifier:-}")"
      goto="$CURRENT_DIR/claude_goto.sh"
      sock="${TMUX%%,*}"
      tmux_bin="$(command -v tmux)"
      set -- terminal-notifier -title "Claude Code" -subtitle "$subtitle" -message "$body" \
        -group "$group" -execute "'$goto' '$sock' '$pane' '$tmux_bin'"
      [ -n "$app" ] && set -- "$@" -activate "$app"
      ("$@" >/dev/null 2>&1 &)
    elif command -v osascript >/dev/null 2>&1; then
      # Text goes in as script arguments, so no AppleScript escaping is needed.
      (osascript -e 'on run argv' \
        -e 'display notification (item 1 of argv) with title "Claude Code" subtitle (item 2 of argv)' \
        -e 'end run' "$body" "$subtitle" >/dev/null 2>&1 &)
    fi
    ;;
  *)
    if command -v notify-send >/dev/null 2>&1; then
      (notify-send --app-name="Claude Code" "Claude Code ${subtitle}" "$body" >/dev/null 2>&1 &)
    fi
    ;;
  esac
}

if [ "$(opt @fuzzmux-claude-notify-desktop 0)" = 1 ]; then
  desktop_notify "$where" "${verb}${title:+: ${title}}" "fuzzmux-claude-${pane}"
fi

exit 0
