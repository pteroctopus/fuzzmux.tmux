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
  ARGS+=" --popup-width=$POPUP_WIDTH"
  ARGS+=" --popup-height=$POPUP_HEIGHT"
  ARGS+=" --popup-border=$POPUP_BORDER"
  ARGS+=" --popup-color=$POPUP_COLOR"
  ARGS+=" --color-palette=$COLOR_PALETTE"

  tmux display-popup -S \
    "fg=${POPUP_COLOR}" \
    -b "${POPUP_BORDER}" \
    -T "Find nvim buffer" \
    -w "${POPUP_WIDTH}" \
    -h "${POPUP_HEIGHT}" \
    -E "$0$ARGS --run"
  exit 0
fi

# Source scripts
# FUZZMUX_COLORS="#ff0000,#00ff00,#0000ff,#0ff0ac"
# FUZZMUX_COLORS="#eb6f92,#f6c177,#9ccfd8,#c4a7e7,#31748f,#ebbcba,#e0def4,#26233a,#403d52,#524f67,#3e8fb0,#c98bbf,#d7827e,#f0cdac,#e5b4c7,#b9c7d5,#7f849c,#524f67,#6e6a86,#908caa,#a4a1b6,#c5c3d0,#1f1d2e,#2a2837,#342f44,#4a475a,#5b567b,#6c6783,#7d7291,#8e7ca2,#a58bb0,#b89cc6,#cea9d8,#f0d9ff,#f7e2d2,#ffd9df,#ffced6,#ffc5cc,#e8b7c1,#dba6b0,#c3949e,#b28395,#a07289,#8e627c,#7c516e,#6b3f5f,#593051,#472243,#351535"
source "$(dirname "$0")/colors.sh" "$COLOR_PALETTE"
# source "$(dirname "$0")/colors.sh"

# Delimiter for parsing
DEL=$'\t'

# Get all FUZZMUX_OPEN_FILES_* variables
ENV_VARS=$(tmux show-environment -g 2>/dev/null | grep "^FUZZMUX_OPEN_FILES_" || true)

# Check if fuzzmux.nvim is providing data
if [[ -z "$ENV_VARS" ]]; then
  echo "fuzzmux.tmux: No nvim buffers found. Is fuzzmux.nvim installed and running?"
  sleep 2
  exit 0
fi

FILE_LIST=""
while IFS='=' read -r var_name files; do
  # Extract session, window, pane from variable name
  # Format: FUZZMUX_OPEN_FILES_session_window_pane
  parts="${var_name#FUZZMUX_OPEN_FILES_}"
  pane_id=$(echo "$parts" | cut -d= -f1)

  coords=$(tmux display-message -p -t "$pane_id" "#{session_name}${DEL}#{window_index}${DEL}#{pane_index}${DEL}#{pane_id}")

  session=$(echo "$coords" | cut -d"${DEL}" -f1)
  window=$(echo "$coords" | cut -d"${DEL}" -f2)
  pane=$(echo "$coords" | cut -d"${DEL}" -f3)
  pane_id=$(echo "$coords" | cut -d"${DEL}" -f4)

  # Split files by colon and create one line per file
  IFS=':' read -ra PATHS <<<"$files"
  for filepath in "${PATHS[@]}"; do
    if [[ -n "$filepath" ]]; then
      # Replace home directory with ~
      display_path="${filepath/#$HOME/\~}"
      if [[ "$USE_COLORS" == "true" ]]; then
        FILE_LIST+="$(pick_color "$session" "$window")@${session}${DEL}#${window}${DEL}%${pane}${DEL}i:${pane_id}${RESET}${DEL}${display_path}"$'\n'
      else
        FILE_LIST+="@${session}${DEL}#${window}${DEL}%${pane}${DEL}i:${pane_id}${DEL}${display_path}"$'\n'
      fi
    fi
  done
done <<<"$ENV_VARS"

if [[ -z "$FILE_LIST" ]]; then
  echo "No nvim files found in any pane"
  sleep 2
  exit 0
fi

# Format with columns
FORMATTED_LIST=$(echo "$FILE_LIST" | column -t -s "${DEL}")

fzf_with_options() {
  local use_colors="${1:-false}"
  local preview="${2:-false}"
  PROMPT="nvim buffer > "

  if [[ "$preview" == "true" ]]; then
    local preview_cmd='
          file=$(echo {} | awk "{print \$NF}");
          file="${file/#\~/$HOME}";
          if command -v bat >/dev/null 2>&1; then
              bat --style=numbers --color=always "$file" 2>/dev/null || cat "$file"
          else
              cat "$file"
          fi
      '

    if [[ "$use_colors" == "true" ]]; then
      fzf --ansi --exit-0 --prompt "$PROMPT" --with-nth=1,2,3,5 --preview "$preview_cmd" --preview-window=right:40%
    else
      fzf --exit-0 --prompt "$PROMPT" --with-nth=1,2,3,5 --preview "$preview_cmd" --preview-window=right:40%
    fi
  else
    if [[ "$use_colors" == "true" ]]; then
      fzf --ansi --exit-0 --prompt "$PROMPT" --with-nth=1,2,3,5
    else
      fzf --exit-0 --prompt "$PROMPT" --with-nth=1,2,3,5
    fi
  fi
}

# Let user select with fzf
if [[ "$USE_COLORS" == "true" ]]; then
  SELECTION=$(echo "$FORMATTED_LIST" | fzf_with_options "$USE_COLORS" "$PREVIEW") || exit 0
else
  SELECTION=$(echo "$FORMATTED_LIST" | fzf_with_options "$USE_COLORS" "$PREVIEW") || exit 0
fi

# Parse selection and switch to that pane
read -r session window pane pane_id filepath <<<"$SELECTION"
session="${session#@}"
window="${window#\#}"
pane="${pane#%}"
pane_id="${pane_id#i:}"

# Expand ~ back to home directory for nvim command
filepath="${filepath/#\~/$HOME}"

tmux switch-client -t "${session}:${window}"
tmux select-pane -t "${pane}"
if [[ "$ZOOM" == "true" ]]; then
  # Check if pane is already zoomed
  is_zoomed=$(tmux display-message -t "${session}:${window}.${pane}" -p '#{window_zoomed_flag}')
  if [[ "$is_zoomed" != "1" ]]; then
    tmux resize-pane -Z -t "${pane}"
  fi
fi

# Check if nvim is suspended (current command is shell instead of nvim)
# pane_pid=$(tmux display-message -t "${session}:${window}.${pane}" -p "#{pane_pid}")
# nvim_pid=$(pgrep -P "$pane_pid" -x nvim 2>/dev/null || true) || exit 0
# [[ -n "$nvim_pid" ]] && tmux send-keys -t "${session}:${window}.${pane}" "fg" Enter 2>/dev/null || true

# Send command to nvim to open the file
socket=$(tmux show-environment -g FUZZMUX_NVIM_SOCKET_${pane_id} 2>/dev/null | cut -d= -f2- || true)

if [[ -n "$socket" ]]; then
  socket=${socket#\'}
  socket=${socket%\'}

  nvim --clean --server \
    "$socket" \
    --remote-send ":buffer ${filepath}<cr><c-l>"
fi
