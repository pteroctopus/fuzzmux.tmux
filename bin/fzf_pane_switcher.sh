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
    tmux display-popup -S "fg=${POPUP_COLOR}" -b "${POPUP_BORDER}" -T "Find tmux pane" -w "${POPUP_WIDTH}" -h "${POPUP_HEIGHT}" -E "$0$ARGS --run"
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

FORMAT="#{session_name}|#{window_index}|#{pane_index}|#{pane_id}|#{pane_current_command}|#{pane_title}|#{=|-40|…;s|$HOME|~|:pane_current_path}"

PANE_LIST=$(tmux list-panes -a -F "$FORMAT")

FORMATED_PANE_LIST=""
while IFS='|' read -r session window pane pane_id command title path; do
    var_name="FUZZMUX_CURRENT_FILE_${pane_id}"
    nvim_file=$(tmux show-environment -g "$var_name" 2>/dev/null | cut -d= -f2- || echo "")
    nvim_file="${nvim_file/#$HOME/\~}"
    if [[ "$USE_COLORS" == "true" ]]; then
        FORMATED_PANE_LIST+="$(pick_color "$session" "$window")s:${session} w:${window} p:${pane}${COLORS[reset]} ${command} ${title} ${path} ${nvim_file}"$'\n'
    else
        FORMATED_PANE_LIST+="s:${session} w:${window} p:${pane} ${command} ${title} ${path} ${nvim_file}"$'\n'
    fi
done <<< "$PANE_LIST"

FORMATED_PANE_LIST=$(echo "$FORMATED_PANE_LIST" | column -t -s ' ')

if [[ "$PREVIEW" == "true" ]]; then
    SELECTION=$(echo "$FORMATED_PANE_LIST" | fzf --ansi --exit-0 \
        --preview '
            sess=$(echo {} | awk "{print \$1}" | sed "s/^s://")
            win=$(echo {} | awk "{print \$2}" | sed "s/^w://")
            pane=$(echo {} | awk "{print \$3}" | sed "s/^p://")
            command=$(echo {} | awk "{print \$4}" | sed "s/^p//")
            if [[ "$command" == "zsh" ]]; then
              tmux capture-pane -pt "${sess}:${win}.${pane}" -e | sed "/./!d" | tail -n "$FZF_PREVIEW_LINES"
            else
              tmux capture-pane -pt "${sess}:${win}.${pane}" -e | head -n "$FZF_PREVIEW_LINES"
            fi
        ' \
        --preview-window=top:50%
    ) || exit 0
else
    SELECTION=$(echo "$FORMATED_PANE_LIST" | fzf --ansi --exit-0) || exit 0
fi

while IFS=" " read -r session window pane _rest; do
    session="${session#s:}"
    window="${window#w:}"
    pane="${pane#p:}"
    tmux switch-client -t "${session}:${window}"
    tmux select-pane -t "${pane}"
    if [[ "$ZOOM" == "true" ]]; then
        # Check if pane is already zoomed
        is_zoomed=$(tmux display-message -t "${session}:${window}.${pane}" -p '#{window_zoomed_flag}')
        if [[ "$is_zoomed" != "1" ]]; then
            tmux resize-pane -Z -t "${pane}"
        fi
    fi
done <<< "$SELECTION"
