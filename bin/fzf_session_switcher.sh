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
PREVIEW_WINDOW="right:30%"
POPUP_WIDTH="90%"
POPUP_HEIGHT="90%"
POPUP_BORDER="rounded"
POPUP_COLOR="white"
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
  --preview-window=*)
    PREVIEW_WINDOW="${1#*=}"
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
  ARGS+=" --preview-window=$PREVIEW_WINDOW --popup-width=$POPUP_WIDTH --popup-height=$POPUP_HEIGHT --popup-border=$POPUP_BORDER --popup-color=$POPUP_COLOR"
  ARGS+=" --color-palette=$COLOR_PALETTE"
  tmux display-popup -S "fg=${POPUP_COLOR}" -b "${POPUP_BORDER}" -T "Find tmux session" -w "${POPUP_WIDTH}" -h "${POPUP_HEIGHT}" -E "$0$ARGS --run"
  exit 0
fi

# Source scripts
source "$PLUGIN_DIR/scripts/colors.sh" "$COLOR_PALETTE"

# Delimiter for parsing
DEL=$'\t'

FORMAT="#{session_name}${DEL}#{session_windows}${DEL}#{session_attached}${DEL}#{session_created}"

SESSION_LIST=$(tmux list-sessions -F "$FORMAT")

# Get all window names at once
declare -A WINDOW_NAMES_MAP
while IFS=: read -r session window_name; do
  if [[ -n "${WINDOW_NAMES_MAP[$session]:-}" ]]; then
    WINDOW_NAMES_MAP[$session]+=",${window_name}"
  else
    WINDOW_NAMES_MAP[$session]="$window_name"
  fi
done < <(tmux list-windows -a -F "#{session_name}:#{window_name}")

# Cache colors
declare -A COLOR_CACHE

FORMATTED_SESSION_LIST=""
while IFS="${DEL}" read -r session windows attached created; do
  attached_marker=""
  if [[ "$attached" == "0" ]] then
    attached_marker=" "
  else
    attached_marker="*"
  fi

  # Fast lookup from map
  window_names="${WINDOW_NAMES_MAP[$session]:-}"

  printf -v created_date '%(%Y-%m-%d %H:%M)T' "$created"

  if [[ "$USE_COLORS" == "true" ]]; then
    # Use cached color
    if [[ -z "${COLOR_CACHE[$session]:-}" ]]; then
      COLOR_CACHE[$session]=$(pick_color "$session")
    fi
    # Attach marker directly to session name: @fuzzmux*
    FORMATTED_SESSION_LIST+="${attached_marker}${DEL}${COLOR_CACHE[$session]}@${session}${RESET}${DEL}windows:${windows}${DEL}${created_date}${DEL}${window_names}"$'\n'
  else
    # Attach marker directly to session name: @fuzzmux*
    FORMATTED_SESSION_LIST+="${attached_marker}${DEL}@${session}${DEL}windows:${windows}${DEL}${created_date}${DEL}${window_names}"$'\n'
  fi
done <<<"$SESSION_LIST"

FORMATTED_SESSION_LIST=$(echo "$FORMATTED_SESSION_LIST" | column -t -s "${DEL}")

PROMPT="session > "
if [[ "$PREVIEW" == "true" ]]; then
  SELECTION=$(
    echo "$FORMATTED_SESSION_LIST" | fzf --ansi --exit-0 --prompt "$PROMPT" \
      --preview '
            # Handle optional marker in first column
            read -r first second _rest <<< {}
            if [[ "$first" == "*" ]]; then
              sess="${second#@}"
            else
              sess="${first#@}"
            fi
            tmux list-windows -t "${sess}" -F "#{window_index}: #{window_name} (#{window_panes} panes) #{window_active}" | \
            while IFS= read -r line; do
                # Remove the trailing " 1" or " 0" but keep the rest
                info="${line% *}"
                active="${line##* }"
                if [[ "$active" == "1" ]]; then
                    echo "→ $info"
                else
                    echo "  $info"
                fi
            done
        ' \
      --preview-window="${PREVIEW_WINDOW}"
  ) || exit 0
else
  SELECTION=$(echo "$FORMATTED_SESSION_LIST" | fzf --ansi --exit-0 --prompt "$PROMPT") || exit 0
fi

while IFS=" " read -r first second _rest; do
  # Handle marker: if first column is *, session is in second column
  if [[ "$first" == "*" ]]; then
    session="${second#@}"
  else
    session="${first#@}"
  fi
  tmux switch-client -t "${session}"
  if [[ "$ZOOM" == "true" ]]; then
    # Zoom the active pane in the active window of the session
    is_zoomed=$(tmux display-message -t "${session}" -p '#{window_zoomed_flag}')
    if [[ "$is_zoomed" != "1" ]]; then
      tmux resize-pane -Z
    fi
  fi
done <<<"$SELECTION"
