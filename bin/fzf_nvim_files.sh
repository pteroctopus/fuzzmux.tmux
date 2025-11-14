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

declare -A COLORS
COLORS[reset]=$'\033[0m'
COLORS[red]=$'\033[31m'
COLORS[green]=$'\033[32m'
COLORS[yellow]=$'\033[33m'
COLORS[blue]=$'\033[34m'
COLORS[magenta]=$'\033[35m'
COLORS[cyan]=$'\033[36m'
COLOR_NAMES=(red green yellow blue magenta cyan)

pick_color() {
    local s="$1"
    local w="$2"
    
    # Simple hash: combine s and w and sum ASCII codes
    local combined="${s}${w}"
    local sum=0
    for ((i=0; i<${#combined}; i++)); do
        sum=$((sum + $(printf "%d" "'${combined:i:1}") ))
    done

    # Pick color deterministically
    local idx=$((sum % ${#COLOR_NAMES[@]}))
    local color_name="${COLOR_NAMES[$idx]}"

    # Return the actual ANSI escape sequence
    printf "%s" "${COLORS[$color_name]}"
}

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
    session=$(echo "$parts" | cut -d_ -f1)
    window=$(echo "$parts" | cut -d_ -f2)
    pane=$(echo "$parts" | cut -d_ -f3)
    
    # Split files by colon and create one line per file
    IFS=':' read -ra PATHS <<< "$files"
    for filepath in "${PATHS[@]}"; do
        if [[ -n "$filepath" ]]; then
            # Replace home directory with ~
            display_path="${filepath/#$HOME/\~}"
            if [[ "$USE_COLORS" == "true" ]]; then
                FILE_LIST+="$(pick_color "$session" "$window")s${session} w${window} p${pane}${COLORS[reset]} ${display_path}"$'\n'
            else
                FILE_LIST+="s${session} w${window} p${pane} ${display_path}"$'\n'
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
          fzf --ansi --exit-0 --preview "$preview_cmd"
      else
          fzf --exit-0 --preview "$preview_cmd"
      fi
    else
      if [[ "$use_colors" == "true" ]]; then
          fzf --ansi --exit-0
      else
          fzf --exit-0
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
read -r session window pane filepath <<< "$SELECTION"
session="${session#s}"
window="${window#w}"
pane="${pane#p}"

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
tmux send-keys -t "${session}:${window}.${pane}" Escape ":buffer ${filepath}" Enter
