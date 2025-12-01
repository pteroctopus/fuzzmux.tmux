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
  ARGS+=" --preview-window=$PREVIEW_WINDOW"
  ARGS+=" --popup-width=$POPUP_WIDTH"
  ARGS+=" --popup-height=$POPUP_HEIGHT"
  ARGS+=" --popup-border=$POPUP_BORDER"
  ARGS+=" --popup-color=$POPUP_COLOR"
  ARGS+=" --color-palette=$COLOR_PALETTE"
  ARGS+=" --fzf-bind=$FZF_BIND_KEY"

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
source "$PLUGIN_DIR/scripts/colors.sh" "$COLOR_PALETTE"

# Delimiter for parsing
DEL=$'\t'

# Get current context for fzf bindings
CURRENT_INFO=$(tmux display-message -p "#{session_name}${DEL}#{window_index}${DEL}#{pane_index}")
IFS="${DEL}" read -r CURRENT_SESSION CURRENT_WINDOW CURRENT_PANE <<< "$CURRENT_INFO"

# Get all FUZZMUX_OPEN_FILES_* variables
ENV_VARS=$(tmux show-environment -g 2>/dev/null | grep "^FUZZMUX_OPEN_FILES_" || true)

# Check if fuzzmux.nvim is providing data
if [[ -z "$ENV_VARS" ]]; then
  echo "fuzzmux.tmux: No nvim buffers found. Is fuzzmux.nvim installed and running?"
  sleep 2
  exit 0
fi

# Get all pane coordinates at once
declare -A PANE_COORDS_MAP
while IFS="${DEL}" read -r pane_id session window pane; do
  PANE_COORDS_MAP["$pane_id"]="${session}${DEL}${window}${DEL}${pane}"
done < <(tmux list-panes -a -F "#{pane_id}${DEL}#{session_name}${DEL}#{window_index}${DEL}#{pane_index}")

# Cache colors
declare -A COLOR_CACHE

FILE_LIST=""
while IFS='=' read -r var_name files; do
  # Extract pane_id from variable name
  pane_id="${var_name#FUZZMUX_OPEN_FILES_}"

  # Fast lookup from map
  coords="${PANE_COORDS_MAP[$pane_id]:-}"
  if [[ -z "$coords" ]]; then
    continue  # Pane no longer exists
  fi

  IFS="${DEL}" read -r session window pane <<< "$coords"

  # Split files by colon and create one line per file
  IFS=':' read -ra PATHS <<<"$files"
  for filepath in "${PATHS[@]}"; do
    if [[ -n "$filepath" ]]; then
      # Replace home directory with ~
      display_path="${filepath/#$HOME/\~}"
      if [[ "$USE_COLORS" == "true" ]]; then
        # Use cached color
        cache_key="${session}_${window}"
        if [[ -z "${COLOR_CACHE[$cache_key]:-}" ]]; then
          COLOR_CACHE[$cache_key]=$(pick_color "$session")
        fi
        FILE_LIST+="${COLOR_CACHE[$cache_key]}@${session}${DEL}#${window}${DEL}%${pane}${DEL}i:${pane_id}${RESET}${DEL}${display_path}"$'\n'
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
  
  # Create fzf bindings for progressive filtering (one key cycles through filters)
  # First press: filter to session, second press: add window filter, third press: add pane filter, fourth press: clear
  BIND_FILTER="${FZF_BIND_KEY}:transform:([[ \$FZF_QUERY == *'%$CURRENT_PANE'* ]] && echo \"change-query()\") || ([[ \$FZF_QUERY == *'#$CURRENT_WINDOW'* ]] && echo \"change-query('@$CURRENT_SESSION' '#$CURRENT_WINDOW' '%$CURRENT_PANE' )\") || ([[ \$FZF_QUERY == *'@$CURRENT_SESSION'* ]] && echo \"change-query('@$CURRENT_SESSION' '#$CURRENT_WINDOW' )\") || echo \"change-query('@$CURRENT_SESSION' )\""
  BINDS="$BIND_FILTER"

  if [[ "$preview" == "true" ]]; then
    local preview_cmd='
          read -r _ _ _ _ file <<< {};
          file="${file/#\~/$HOME}";
          if command -v bat >/dev/null 2>&1; then
              bat --style=numbers --color=always "$file" 2>/dev/null || cat "$file"
          else
              cat "$file"
          fi
      '

    if [[ "$use_colors" == "true" ]]; then
      fzf --ansi --exit-0 --prompt "$PROMPT" --bind="$BINDS" --with-nth=1,2,3,5 --preview "$preview_cmd" --preview-window="${PREVIEW_WINDOW}"
    else
      fzf --exit-0 --prompt "$PROMPT" --bind="$BINDS" --with-nth=1,2,3,5 --preview "$preview_cmd" --preview-window="${PREVIEW_WINDOW}"
    fi
  else
    if [[ "$use_colors" == "true" ]]; then
      fzf --ansi --exit-0 --prompt "$PROMPT" --bind="$BINDS" --with-nth=1,2,3,5
    else
      fzf --exit-0 --prompt "$PROMPT" --bind="$BINDS" --with-nth=1,2,3,5
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
socket_var=$(tmux show-environment -g FUZZMUX_NVIM_SOCKET_${pane_id} 2>/dev/null || true)
socket="${socket_var#*=}"

if [[ -n "$socket" ]]; then
  socket=${socket#\'}
  socket=${socket%\'}

  nvim --headless --clean --server \
    "$socket" \
    --remote-send "<C-\\><C-N>:buffer ${filepath}<cr><c-l>"
fi
