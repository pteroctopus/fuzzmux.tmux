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

  tmux display-popup -S "fg=${POPUP_COLOR}" \
    -b "${POPUP_BORDER}" \
    -T "Find Claude Code agent" \
    -w "${POPUP_WIDTH}" \
    -h "${POPUP_HEIGHT}" \
    -E "$0$ARGS --run"
  exit 0
fi

# Source scripts
source "$PLUGIN_DIR/scripts/colors.sh" "$COLOR_PALETTE"
source "$CURRENT_DIR/claude_lib.sh"

# Where the popup was opened from: the pane gets the * marker, other panes of
# the same window get +, and rows in the same session show the session in bold.
IFS="$CLAUDE_DEL" read -r CURRENT_SESSION CURRENT_WINDOW CURRENT_PANE_ID < <(
  tmux display-message -p "#{session_name}${CLAUDE_DEL}#{window_index}${CLAUDE_DEL}#{pane_id}"
)
BOLD=$'\033[1m'

AGENTS="$(claude_agents_list)"
if [[ -z "$AGENTS" ]]; then
  if command -v jq >/dev/null 2>&1; then
    echo "fuzzmux.tmux: No Claude Code agents found in any tmux pane."
  else
    echo "fuzzmux.tmux: No Claude Code agents found. Install jq to detect agents without hooks."
  fi
  sleep 2
  exit 0
fi

# State colours come from the @fuzzmux-claude-<group>-style tmux options
# (claude_lib.sh), converted from tmux style syntax to ANSI for fzf.
declare -A STATE_ANSI
state_ansi() {
  if [[ -z "${STATE_ANSI[$1]+set}" ]]; then
    STATE_ANSI[$1]="$(claude_style_to_ansi "$(claude_state_style "$1")")"
  fi
  printf '%s' "${STATE_ANSI[$1]}"
}

# Cache colors to avoid recalculating for same session
declare -A COLOR_CACHE

printf -v NOW '%(%s)T' -1

# Collect the rows first so each column can be padded to its widest plain value.
# Padding happens before colouring, so ANSI sequences of different lengths never
# skew the alignment (`column -t` cannot guarantee that once styles differ per
# row). The first field is the pane id, separated by CLAUDE_DEL and hidden in
# fzf via --delimiter/--with-nth; a whitespace split would also eat the leading
# blank of the marker column on unmarked rows and shift the marked row.
PANES=() MARKERS=() STATES=() LABELS=() AGES=() SESSIONS=() WINDOWS=() INDEXES=() MODES=() TITLES=() CWDS=()
w_label=0 w_age=0 w_sess=0 w_win=0 w_idx=0 w_mode=0 w_title=0
while IFS="$CLAUDE_DEL" read -r pane state since detail _name cwd sess win idx title _pa _wa _sa _src mode _sid; do
  active_marker=" "
  if [[ "$pane" == "$CURRENT_PANE_ID" ]]; then
    active_marker="*"
  elif [[ "$sess" == "$CURRENT_SESSION" && "$win" == "$CURRENT_WINDOW" ]]; then
    active_marker="+"
  fi

  age="-"
  [[ "$since" =~ ^[0-9]+$ && "$since" -gt 0 ]] && age="$(claude_age $((NOW - since)))"

  label="$state"
  [[ -n "$detail" ]] && label+=" ($detail)"
  [[ -n "$title" ]] || title="${_name:--}"
  [[ -n "$cwd" ]] || cwd="-"
  mode="$(claude_mode_label "$mode")"

  PANES+=("$pane") MARKERS+=("$active_marker") STATES+=("$state") LABELS+=("$label") AGES+=("$age")
  SESSIONS+=("@${sess}") WINDOWS+=("#${win}") INDEXES+=("%${idx}") MODES+=("$mode") TITLES+=("$title") CWDS+=("$cwd")
  ((${#mode} > w_mode)) && w_mode=${#mode}
  ((${#label} > w_label)) && w_label=${#label}
  ((${#age} > w_age)) && w_age=${#age}
  ((${#sess} + 1 > w_sess)) && w_sess=$((${#sess} + 1))
  ((${#win} + 1 > w_win)) && w_win=$((${#win} + 1))
  ((${#idx} + 1 > w_idx)) && w_idx=$((${#idx} + 1))
  ((${#title} > w_title)) && w_title=${#title}
done <<<"$AGENTS"

FORMATTED_LIST=""
for i in "${!PANES[@]}"; do
  line="${PANES[$i]}${CLAUDE_DEL}${MARKERS[$i]}  "
  if [[ "$USE_COLORS" == "true" ]]; then
    sess="${SESSIONS[$i]#@}"
    if [[ -z "${COLOR_CACHE[$sess]:-}" ]]; then
      COLOR_CACHE[$sess]=$(pick_color "$sess")
    fi
    line+="$(state_ansi "${STATES[$i]}")$(claude_pad "${LABELS[$i]}" "$w_label")${RESET}  "
    line+="$(claude_pad "${AGES[$i]}" "$w_age")  "
    [[ "$sess" == "$CURRENT_SESSION" ]] && line+="$BOLD"
    line+="${COLOR_CACHE[$sess]}$(claude_pad "${SESSIONS[$i]}" "$w_sess")  "
    line+="$(claude_pad "${WINDOWS[$i]}" "$w_win")  $(claude_pad "${INDEXES[$i]}" "$w_idx")${RESET}  "
  else
    line+="$(claude_pad "${LABELS[$i]}" "$w_label")  $(claude_pad "${AGES[$i]}" "$w_age")  "
    line+="$(claude_pad "${SESSIONS[$i]}" "$w_sess")  $(claude_pad "${WINDOWS[$i]}" "$w_win")  "
    line+="$(claude_pad "${INDEXES[$i]}" "$w_idx")  "
  fi
  line+="$(claude_pad "${MODES[$i]}" "$w_mode")  $(claude_pad "${TITLES[$i]}" "$w_title")  ${CWDS[$i]}"
  FORMATTED_LIST+="${line}"$'\n'
done
FORMATTED_LIST="${FORMATTED_LIST%$'\n'}"

# Start fzf selection
PROMPT="claude > "
# Toggle filtering: press once to show only agents that need you, again to clear
ATTENTION_QUERY="permission | question | waiting "
BIND_FILTER="${FZF_BIND_KEY}:transform:[[ \$FZF_QUERY == *\"permission | question\"* ]] && echo \"change-query()\" || echo \"change-query(${ATTENTION_QUERY})\""
BINDS="$BIND_FILTER"

# Exact (substring) matching: rows are structured words (state, session, title,
# path) and fuzzy matching lets a state name hit almost every row through the
# letters of a long path. Prefix a term with ' for fuzzy matching when wanted.
# Note: fzf matches against the --with-nth output, so the hidden pane id is
# already excluded; an --nth would count fields of the transformed line.
FZF_MATCH="--exact"

# Preview the pane content, bottom-aligned (Claude's prompt lives at the bottom).
# The pane id is everything before the first CLAUDE_DEL of the selected line.
export CLAUDE_DEL
PREVIEW_CMD='bash -c '\''
  pane="${1%%"${CLAUDE_DEL}"*}"
  tmux capture-pane -p -e -t "$pane" | sed -e :a -e "/^[[:space:]]*\$/{\$d;N;ba" -e "}" | tail -n "${FZF_PREVIEW_LINES:-40}"
'\'' _ {}'

if [[ "$PREVIEW" == "true" ]]; then
  SELECTION=$(
    echo "$FORMATTED_LIST" | fzf --ansi --exit-0 "$FZF_MATCH" --prompt "$PROMPT" --bind="$BINDS" \
      --delimiter="$CLAUDE_DEL" --with-nth=2 \
      --preview "$PREVIEW_CMD" \
      --preview-window="${PREVIEW_WINDOW}"
  ) || exit 0
else
  SELECTION=$(echo "$FORMATTED_LIST" | fzf --ansi --exit-0 "$FZF_MATCH" --prompt "$PROMPT" --bind="$BINDS" --delimiter="$CLAUDE_DEL" --with-nth=2) || exit 0
fi

# Switch to the selected agent's pane
pane_id="${SELECTION%%"${CLAUDE_DEL}"*}"
[[ "$pane_id" =~ ^%[0-9]+$ ]] || exit 0

# Query session/window separately to tolerate session names containing spaces.
session="$(tmux display-message -p -t "$pane_id" '#{session_name}')"
window="$(tmux display-message -p -t "$pane_id" '#{window_index}')"
# Select the pane before switching the client so focus hooks see the right pane.
tmux select-pane -t "$pane_id"
tmux switch-client -t "${session}:${window}"
if [[ "$ZOOM" == "true" ]]; then
  is_zoomed=$(tmux display-message -t "$pane_id" -p '#{window_zoomed_flag}')
  if [[ "$is_zoomed" != "1" ]]; then
    tmux resize-pane -Z -t "$pane_id"
  fi
fi
