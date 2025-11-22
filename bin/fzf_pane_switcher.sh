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
  ARGS+=" --popup-width=$POPUP_WIDTH"
  ARGS+=" --popup-height=$POPUP_HEIGHT"
  ARGS+=" --popup-border=$POPUP_BORDER"
  ARGS+=" --popup-color=$POPUP_COLOR"
  ARGS+=" --color-palette=$COLOR_PALETTE"
  ARGS+=" --fzf-bind=$FZF_BIND_KEY"

  tmux display-popup -S "fg=${POPUP_COLOR}" \
    -b "${POPUP_BORDER}" \
    -T "Find tmux pane" \
    -w "${POPUP_WIDTH}" \
    -h "${POPUP_HEIGHT}" \
    -E "$0$ARGS --run"
  exit 0
fi

# Source scripts
source "$PLUGIN_DIR/scripts/colors.sh" "$COLOR_PALETTE"

# Delimiter for parsing
DEL=$'\t'

# Get current pane info for marking active pane
CURRENT_INFO=$(tmux display-message -p "#{session_name}${DEL}#{window_index}${DEL}#{pane_index}")
IFS="${DEL}" read -r CURRENT_SESSION CURRENT_WINDOW CURRENT_PANE <<< "$CURRENT_INFO"

# List all panes with relevant info by format
FORMAT="#{session_name}${DEL}"
FORMAT+="#{window_index}${DEL}"
FORMAT+="#{pane_index}${DEL}"
FORMAT+="#{pane_id}${DEL}"
FORMAT+="#{pane_current_command}${DEL}"
FORMAT+="#{pane_title}${DEL}"
FORMAT+="#{pane_active}${DEL}"
FORMAT+="#{window_active}${DEL}"
FORMAT+="#{session_attached}${DEL}"
FORMAT+="#{s|$HOME|~|:pane_current_path}"
PANE_LIST=$(tmux list-panes -a -F "$FORMAT")

# Get all FUZZMUX environment variables once
declare -A NVIM_FILES
while IFS='=' read -r var_name value; do
  pane_id="${var_name#FUZZMUX_CURRENT_FILE_}"
  # Remove quotes
  value=${value#\'}
  value=${value%\'}
  NVIM_FILES["$pane_id"]="$value"
done < <(tmux show-environment -g 2>/dev/null | grep "^FUZZMUX_CURRENT_FILE_")

# Cache colors to avoid recalculating for same session/window
declare -A COLOR_CACHE

# Format pane list for fzf and add nvim current file if available
FORMATED_PANE_LIST=""
while IFS="${DEL}" read -r session window pane pane_id command title pane_active window_active session_attached path; do
  # Determine if this is the active pane (only mark if it's in current attached session)
  active_marker=" "
  if [[ "$pane_active" == "1" && "$window_active" == "1" && "$session_attached" != "0" && "$session" == "$CURRENT_SESSION" && "$window" == "$CURRENT_WINDOW" && "$pane" == "$CURRENT_PANE" ]]; then
    active_marker="*"
  fi

  # Fast lookup from associative array instead of calling tmux show-environment
  nvim_file="${NVIM_FILES[$pane_id]:-}"
  nvim_file="${nvim_file/#$HOME/\~}"

  if [[ "$USE_COLORS" == "true" ]]; then
    # Use cached color
    cache_key="${session}_${window}"
    if [[ -z "${COLOR_CACHE[$cache_key]:-}" ]]; then
      COLOR_CACHE[$cache_key]=$(pick_color "$session" "$window")
    fi
    color="${COLOR_CACHE[$cache_key]}"
    
    # Attach marker directly to pane designation: %1*
    FORMATED_PANE_LIST+="${active_marker}${DEL}${color}@${session}${DEL}"
    FORMATED_PANE_LIST+="#${window}${DEL}"
    FORMATED_PANE_LIST+="%${pane}${RESET}${DEL}"
    FORMATED_PANE_LIST+="${command}${DEL}"
    FORMATED_PANE_LIST+="${title}${DEL}"
    FORMATED_PANE_LIST+="${path}"
    FORMATED_PANE_LIST+="${color}${nvim_file:+ → ${nvim_file#$path/}}${RESET}"$'\n'
  else
    # Attach marker directly to pane designation: %1*
    FORMATED_PANE_LIST+="${active_marker}${DEL}@${session}${DEL}"
    FORMATED_PANE_LIST+="#${window}${DEL}"
    FORMATED_PANE_LIST+="%${pane}${DEL}"
    FORMATED_PANE_LIST+="${command}${DEL}"
    FORMATED_PANE_LIST+="${title}${DEL}"
    FORMATED_PANE_LIST+="${path}"
    FORMATED_PANE_LIST+="${nvim_file:+ → ${nvim_file#$path/}}"$'\n'
  fi
done <<<"$PANE_LIST"

FORMATED_PANE_LIST=$(echo "$FORMATED_PANE_LIST" | column -t -s "${DEL}")

# Start fzf selection
PROMPT="pane > "
# Progressive filtering: one key cycles through filters (session -> window -> clear)
BIND_FILTER="${FZF_BIND_KEY}:transform:([[ \$FZF_QUERY == *'#$CURRENT_WINDOW'* ]] && echo \"change-query()\") || ([[ \$FZF_QUERY == *'@$CURRENT_SESSION'* ]] && echo \"change-query('@$CURRENT_SESSION' '#$CURRENT_WINDOW' )\") || echo \"change-query('@$CURRENT_SESSION' )\""
BINDS="$BIND_FILTER"

if [[ "$PREVIEW" == "true" ]]; then
  SELECTION=$(
    echo "$FORMATED_PANE_LIST" | fzf --ansi --exit-0 --prompt "$PROMPT" --bind="$BINDS" \
      --preview '
            # Handle optional marker in first column
            read -r col1 col2 col3 col4 col5 _rest <<< {}
            if [[ "$col1" == "*" ]]; then
              sess="${col2#@}"
              win="${col3#\#}"
              pane="${col4#%}"
              command="$col5"
            else
              sess="${col1#@}"
              win="${col2#\#}"
              pane="${col3#%}"
              command="$col4"
            fi
            if [[ "$command" == "zsh" ]]; then
              tmux capture-pane -pt "${sess}:${win}.${pane}" -e | sed "/./!d" | tail -n "$FZF_PREVIEW_LINES"
            else
              tmux capture-pane -pt "${sess}:${win}.${pane}" -e | head -n "$FZF_PREVIEW_LINES"
            fi
        ' \
      --preview-window=top:40%
  ) || exit 0
else
  SELECTION=$(echo "$FORMATED_PANE_LIST" | fzf --ansi --exit-0 --prompt "$PROMPT" --bind="$BINDS") || exit 0
fi

# Switch to selected pane
while IFS=" " read -r first second third fourth _rest; do
  # Handle marker: if first column is *, session/window/pane are in second/third/fourth columns
  if [[ "$first" == "*" ]]; then
    session="${second#@}"
    window="${third#\#}"
    pane="${fourth#%}"
  else
    session="${first#@}"
    window="${second#\#}"
    pane="${third#%}"
  fi
  tmux switch-client -t "${session}:${window}"
  tmux select-pane -t "${pane}"
  if [[ "$ZOOM" == "true" ]]; then
    # Check if pane is already zoomed
    is_zoomed=$(tmux display-message -t "${session}:${window}.${pane}" -p '#{window_zoomed_flag}')
    if [[ "$is_zoomed" != "1" ]]; then
      tmux resize-pane -Z -t "${pane}"
    fi
  fi
done <<<"$SELECTION"
