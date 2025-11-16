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
    tmux display-popup -S "fg=${POPUP_COLOR}" -b "${POPUP_BORDER}" -T "Find nvim buffer" -w "${POPUP_WIDTH}" -h "${POPUP_HEIGHT}" -E "$0$ARGS --run"
    exit 0
fi

# Source scripts
source "$(dirname "$0")/colors.sh"

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

    coords=$(tmux display-message -p -t "$pane_id" '#{session_name}:#{window_index}:#{pane_index}:#{pane_id}')

    session=$(echo "$coords" | cut -d: -f1)
    window=$(echo "$coords" | cut -d: -f2)
    pane=$(echo "$coords" | cut -d: -f3)
    pane_id=$(echo "$coords" | cut -d: -f4)
    
    # Split files by colon and create one line per file
    IFS=':' read -ra PATHS <<< "$files"
    for filepath in "${PATHS[@]}"; do
        if [[ -n "$filepath" ]]; then
            # Replace home directory with ~
            display_path="${filepath/#$HOME/\~}"
            if [[ "$USE_COLORS" == "true" ]]; then
                FILE_LIST+="$(pick_color "$session" "$window")s:${session} w:${window} p:${pane} i:${pane_id}${COLORS[reset]} ${display_path}"$'\n'
            else
                FILE_LIST+="s:${session} w:${window} p:${pane} i:${pane_id} ${display_path}"$'\n'
            fi
        fi
    done
done <<< "$ENV_VARS"

if [[ -z "$FILE_LIST" ]]; then
    echo "No nvim files found in any pane"
    sleep 2
    exit 0
fi

# Format with columns
FORMATTED_LIST=$(echo "$FILE_LIST" | column -t -s ' ')

fzf_with_options() {
    local use_colors="${1:-false}"
    local preview="${2:-false}"

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
          fzf --ansi --exit-0 --with-nth=1,2,3,5 --preview "$preview_cmd"
      else
          fzf --exit-0 --with-nth=1,2,3,5 --preview "$preview_cmd"
      fi
    else
      if [[ "$use_colors" == "true" ]]; then
          fzf --ansi --exit-0 --with-nth=1,2,3,5
      else
          fzf --exit-0 --with-nth=1,2,3,5
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
read -r session window pane pane_id filepath <<< "$SELECTION"
session="${session#s:}"
window="${window#w:}"
pane="${pane#p:}"
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
current_cmd=$(tmux display-message -t "${session}:${window}.${pane}" -p '#{pane_current_command}')
if [[ "$current_cmd" != "nvim" ]]; then
    # Resume nvim if suspended
    tmux send-keys -t "${session}:${window}.${pane}" "fg" Enter
    # sleep 0.2
fi

# Send command to nvim to open the file
socket=$(tmux show-environment -g FUZZMUX_NVIM_SOCKET_${pane_id} 2>/dev/null | cut -d= -f2- || true)

if [[ -n "$socket" ]]; then
  socket=${socket#\'}
  socket=${socket%\'}

  nvim --clean --server \
    "$socket" \
    --remote-send ":buffer ${filepath}<cr><c-l>"
fi

