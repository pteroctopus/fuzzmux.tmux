#!/usr/bin/env bash
set -euo pipefail

# Check if running inside tmux
if [[ -z "${TMUX:-}" ]]; then
  echo "Error: Must be run from inside tmux"
  exit 1
fi

# Check if fzf is installed
if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "fuzzmux.tmux: ERROR - fzf is not installed"
  exit 1
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$CURRENT_DIR")"

ZOOM=false
USE_COLORS=false
PREVIEW=false
POPUP_WIDTH="90%"
POPUP_HEIGHT="90%"
POPUP_BORDER="rounded"
POPUP_COLOR="white"
COLOR_PALETTE=""
FZF_BIND_KEY="ctrl-f"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --zoom)
    ZOOM=true
    shift
    ;;
  --colors)
    USE_COLORS=true
    shift
    ;;
  --preview)
    PREVIEW=true
    shift
    ;;
  --popup-width=*)
    POPUP_WIDTH="${1#*=}"
    shift
    ;;
  --popup-height=*)
    POPUP_HEIGHT="${1#*=}"
    shift
    ;;
  --popup-border=*)
    POPUP_BORDER="${1#*=}"
    shift
    ;;
  --popup-color=*)
    POPUP_COLOR="${1#*=}"
    shift
    ;;
  --color-palette=*)
    COLOR_PALETTE="${1#*=}"
    shift
    ;;
  --fzf-bind=*)
    FZF_BIND_KEY="${1#*=}"
    shift
    ;;
  --run)
    break
    ;;
  *)
    shift
    ;;
  esac
done

if [[ "${1:-}" != "--run" ]]; then
  ARGS=""
  [[ "$ZOOM" == "true" ]] && ARGS+=" --zoom"
  [[ "$USE_COLORS" == "true" ]] && ARGS+=" --colors"
  [[ "$PREVIEW" == "true" ]] && ARGS+=" --preview"
  ARGS+=" --popup-width=$POPUP_WIDTH --popup-height=$POPUP_HEIGHT --popup-border=$POPUP_BORDER --popup-color=$POPUP_COLOR"
  ARGS+=" --color-palette=$COLOR_PALETTE"
  ARGS+=" --fzf-bind=$FZF_BIND_KEY"
  tmux display-popup -S "fg=${POPUP_COLOR}" -b "${POPUP_BORDER}" -T "Find tmux window" -w "${POPUP_WIDTH}" -h "${POPUP_HEIGHT}" -E "$0$ARGS --run"
  exit 0
fi

# Source scripts
source "$PLUGIN_DIR/scripts/colors.sh" "$COLOR_PALETTE"

# Delimiter for parsing
DEL=$'\t'

FORMAT="#{session_name}${DEL}#{window_index}${DEL}#{window_name}${DEL}#{window_panes}${DEL}#{window_active}${DEL}#{session_attached}"

WINDOW_LIST=$(tmux list-windows -a -F "$FORMAT")

# Get current session and window to mark the truly active window
CURRENT_INFO=$(tmux display-message -p "#{session_name}${DEL}#{window_index}")
CURRENT_SESSION=$(echo "$CURRENT_INFO" | cut -d"${DEL}" -f1)
CURRENT_WINDOW=$(echo "$CURRENT_INFO" | cut -d"${DEL}" -f2)

# Get all pane commands at once
declare -A PANE_COMMANDS_MAP
while IFS=: read -r session window command; do
  key="${session}:${window}"
  if [[ -n "${PANE_COMMANDS_MAP[$key]:-}" ]]; then
    PANE_COMMANDS_MAP[$key]+=",${command}"
  else
    PANE_COMMANDS_MAP[$key]="$command"
  fi
done < <(tmux list-panes -a -F "#{session_name}:#{window_index}:#{pane_current_command}")

# Cache colors
declare -A COLOR_CACHE

FORMATED_WINDOW_LIST=""
while IFS="${DEL}" read -r session window name panes active attached; do
  active_marker=""
  # Only mark as active if it's the active window in the currently attached session
  if [[ "$active" == "1" && "$attached" != "0" && "$session" == "$CURRENT_SESSION" && "$window" == "$CURRENT_WINDOW" ]]; then
    active_marker="*"
  else
    active_marker=" "
  fi

  # Fast lookup from map
  pane_commands="${PANE_COMMANDS_MAP[${session}:${window}]:-}"

  if [[ "$USE_COLORS" == "true" ]]; then
    # Use cached color
    if [[ -z "${COLOR_CACHE[$session]:-}" ]]; then
      COLOR_CACHE[$session]=$(pick_color "$session")
    fi
    # Attach marker directly to window designation: #1*
    FORMATED_WINDOW_LIST+="${active_marker}${DEL}${COLOR_CACHE[$session]}@${session}${DEL}#${window}${RESET}${DEL}${name}${DEL}panes:${panes}${DEL}${pane_commands}"$'\n'
  else
    # Attach marker directly to window designation: #1*
    FORMATED_WINDOW_LIST+="${active_marker}${DEL}@${session}${DEL}#${window}${DEL}${name}${DEL}panes:${panes}${DEL}${pane_commands}"$'\n'
  fi
done <<<"$WINDOW_LIST"

FORMATED_WINDOW_LIST=$(echo "$FORMATED_WINDOW_LIST" | column -t -s "${DEL}")

PROMPT="window > "
# Toggle filtering: press once to filter by session, press again to clear filter
BIND="${FZF_BIND_KEY}:transform:[[ \$FZF_QUERY == *'@$CURRENT_SESSION'* ]] && echo \"change-query()\" || echo \"change-query('@$CURRENT_SESSION' )\""

if [[ "$PREVIEW" == "true" ]]; then
  SELECTION=$(
    echo "$FORMATED_WINDOW_LIST" | fzf --ansi --exit-0 --prompt "$PROMPT" --bind="$BIND" \
      --preview '
            # Handle optional marker in first column
            read -r col1 col2 col3 _rest <<< {}
            if [[ "$col1" == "*" ]]; then
              sess="${col2#@}"
              win="${col3#\#}"
            else
              sess="${col1#@}"
              win="${col2#\#}"
            fi
            pane=$(tmux list-panes -t "${sess}:${win}" -F "#{pane_index} #{pane_active}" | grep " 1$" | cut -d" " -f1)
            tmux capture-pane -pt "${sess}:${win}.${pane}" -e | tail -n 50
        ' \
      --preview-window=top:40%
  ) || exit 0
else
  SELECTION=$(echo "$FORMATED_WINDOW_LIST" | fzf --ansi --exit-0 --prompt "$PROMPT" --bind "$BIND") || exit 0
fi

while IFS=" " read -r first second third _rest; do
  # Handle marker: if first column is *, session/window are in second/third columns
  if [[ "$first" == "*" ]]; then
    session="${second#@}"
    window="${third#\#}"
  else
    session="${first#@}"
    window="${second#\#}"
  fi
  tmux switch-client -t "${session}:${window}"
  if [[ "$ZOOM" == "true" ]]; then
    # Check if window is already zoomed
    is_zoomed=$(tmux display-message -t "${session}:${window}" -p '#{window_zoomed_flag}')
    if [[ "$is_zoomed" != "1" ]]; then
      tmux resize-pane -Z
    fi
  fi
done <<<"$SELECTION"
