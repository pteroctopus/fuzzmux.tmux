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

ZOOM=false
USE_COLORS=false
PREVIEW=false
POPUP_WIDTH="90%"
POPUP_HEIGHT="90%"
POPUP_BORDER="rounded"
POPUP_COLOR="green"
COLOR_PALETTE=""

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
  tmux display-popup -S "fg=${POPUP_COLOR}" -b "${POPUP_BORDER}" -T "Find tmux window" -w "${POPUP_WIDTH}" -h "${POPUP_HEIGHT}" -E "$0$ARGS --run"
  exit 0
fi

# Source scripts
source "$(dirname "$0")/colors.sh" "$COLOR_PALETTE"

# Delimiter for parsing
DEL=$'\t'

FORMAT="#{session_name}${DEL}#{window_index}${DEL}#{window_name}${DEL}#{window_panes}${DEL}#{window_active}${DEL}#{session_attached}"

WINDOW_LIST=$(tmux list-windows -a -F "$FORMAT")

# Get current session and window to mark the truly active window
CURRENT_INFO=$(tmux display-message -p "#{session_name}${DEL}#{window_index}")
CURRENT_SESSION=$(echo "$CURRENT_INFO" | cut -d"${DEL}" -f1)
CURRENT_WINDOW=$(echo "$CURRENT_INFO" | cut -d"${DEL}" -f2)

FORMATED_WINDOW_LIST=""
while IFS="${DEL}" read -r session window name panes active attached; do
  active_marker=""
  # Only mark as active if it's the active window in the currently attached session
  if [[ "$active" == "1" && "$attached" != "0" && "$session" == "$CURRENT_SESSION" && "$window" == "$CURRENT_WINDOW" ]]; then
    active_marker="*"
  fi

  # Get all pane commands for this window, comma-delimited
  pane_commands=$(tmux list-panes -t "${session}:${window}" -F "#{pane_current_command}" | paste -sd "," -)

  if [[ "$USE_COLORS" == "true" ]]; then
    FORMATED_WINDOW_LIST+="$(pick_color "$session")@${session}${DEL}#${window}${RESET}${DEL}${name}${DEL}panes:${panes}${DEL}${pane_commands}${DEL}${active_marker}"$'\n'
  else
    FORMATED_WINDOW_LIST+="@${session}${DEL}#${window}${DEL}${name}${DEL}panes:${panes}${DEL}${pane_commands}${DEL}${active_marker}"$'\n'
  fi
done <<<"$WINDOW_LIST"

FORMATED_WINDOW_LIST=$(echo "$FORMATED_WINDOW_LIST" | column -t -s "${DEL}")

PROMPT="window > "

if [[ "$PREVIEW" == "true" ]]; then
  SELECTION=$(
    echo "$FORMATED_WINDOW_LIST" | fzf --ansi --exit-0 --prompt "$PROMPT" \
      --preview '
            sess=$(echo {} | awk "{print \$1}" | sed "s/^@//")
            win=$(echo {} | awk "{print \$2}" | sed "s/^#//")
            pane=$(tmux list-panes -t "${sess}:${win}" -F "#{pane_index} #{pane_active}" | grep " 1$" | cut -d" " -f1)
            tmux capture-pane -pt "${sess}:${win}.${pane}" -e | tail -n 50
        ' \
      --preview-window=top:50%
  ) || exit 0
else
  SELECTION=$(echo "$FORMATED_WINDOW_LIST" | fzf --ansi --exit-0 --prompt "$PROMPT") || exit 0
fi

while IFS=" " read -r session window _rest; do
  session="${session#@}"
  window="${window#\#}"
  tmux switch-client -t "${session}:${window}"
  if [[ "$ZOOM" == "true" ]]; then
    # Check if window is already zoomed
    is_zoomed=$(tmux display-message -t "${session}:${window}" -p '#{window_zoomed_flag}')
    if [[ "$is_zoomed" != "1" ]]; then
      tmux resize-pane -Z
    fi
  fi
done <<<"$SELECTION"
