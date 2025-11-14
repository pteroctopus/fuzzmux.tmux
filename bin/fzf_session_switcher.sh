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
    tmux display-popup -S "fg=${POPUP_COLOR}" -b "${POPUP_BORDER}" -T "Find tmux session" -w "${POPUP_WIDTH}" -h "${POPUP_HEIGHT}" -E "$0$ARGS --run"
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
    
    # Simple hash: sum ASCII codes
    local sum=0
    for ((i=0; i<${#s}; i++)); do
        sum=$((sum + $(printf "%d" "'${s:i:1}") ))
    done

    # Pick color deterministically
    local idx=$((sum % ${#COLOR_NAMES[@]}))
    local color_name="${COLOR_NAMES[$idx]}"

    # Return the actual ANSI escape sequence
    printf "%s" "${COLORS[$color_name]}"
}

FORMAT="#{session_name}|#{session_windows}|#{session_attached}|#{session_created}"

SESSION_LIST=$(tmux list-sessions -F "$FORMAT")

FORMATTED_SESSION_LIST=""
while IFS='|' read -r session windows attached created; do
    attached_marker=""
    [[ "$attached" != "0" ]] && attached_marker="*"
    
    # Get window names for this session
    window_names=$(tmux list-windows -t "${session}" -F "#{window_name}" | paste -sd "," -)
    
    # Convert created timestamp to readable format
    created_date=$(date -r "$created" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "")
    
    if [[ "$USE_COLORS" == "true" ]]; then
        FORMATTED_SESSION_LIST+="$(pick_color "$session")s${session}${COLORS[reset]} ${windows} windows ${created_date} ${window_names} ${attached_marker}"$'\n'
    else
        FORMATTED_SESSION_LIST+="s${session} ${windows} windows ${created_date} ${window_names} ${attached_marker}"$'\n'
    fi
done <<< "$SESSION_LIST"

FORMATTED_SESSION_LIST=$(echo "$FORMATTED_SESSION_LIST" | column -t -s ' ')

if [[ "$PREVIEW" == "true" ]]; then
    SELECTION=$(echo "$FORMATTED_SESSION_LIST" | fzf --ansi --exit-0 \
        --preview '
            sess=$(echo {} | awk "{print \$1}" | sed "s/^s//")
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
        --preview-window=right:40%
    ) || exit 0
else
    SELECTION=$(echo "$FORMATTED_SESSION_LIST" | fzf --ansi --exit-0) || exit 0
fi

while IFS=" " read -r session _rest; do
    session="${session#s}"
    tmux switch-client -t "${session}"
    if [[ "$ZOOM" == "true" ]]; then
        # Zoom the active pane in the active window of the session
        is_zoomed=$(tmux display-message -t "${session}" -p '#{window_zoomed_flag}')
        if [[ "$is_zoomed" != "1" ]]; then
            tmux resize-pane -Z
        fi
    fi
done <<< "$SELECTION"
