#!/usr/bin/env bash
set -euo pipefail

# fuzzmux.tmux - Claude Code session history: search every session ever run
# (by your prompts, or with ctrl-f also by Claude's answers), then jump to the
# running instance or resume the session where it last ran.
#
# Modes (internal, driven by the popup and fzf):
#   <no --run>          open the popup, re-invoke with --run
#   --run               build the list and run fzf
#   --deep <query>      rows for sessions whose transcript matches (fzf reload)
#   --preview-line <l>  preview for the selected row

# Check if running inside tmux
if [[ -z "${TMUX:-}" ]]; then
  echo "Error: Must be run from inside tmux"
  exit 1
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$CURRENT_DIR")"
# shellcheck source=claude_lib.sh
source "$CURRENT_DIR/claude_lib.sh"

DEL="$CLAUDE_DEL"
CFG="$(claude_config_dir)"
HISTORY="$CFG/history.jsonl"
PROJECTS="$CFG/projects"
ELLIPSIS="$(printf '\342\200\246')" # U+2026
BAR="$(printf '\342\224\202')"      # U+2502
ARROW="$(printf '\302\273')"        # U+00BB

# --- helper modes ---------------------------------------------------------------

# Registry: last recorded tmux location per session id.
#   prints: tmux_session US window_id US window_index US pane US cwd US epoch
registry_lookup() {
  local file sid=$1
  file="$(claude_registry_file)"
  [[ -f "$file" ]] || return 0
  awk -F "$DEL" -v sid="$sid" '$1 == sid { line = $0 } END { if (line != "") print line }' "$file" | cut -d "$DEL" -f 2-
}

# Keep the registry small: rewrite with the last line per session id.
registry_compact() {
  local file lines tmp
  file="$(claude_registry_file)"
  [[ -f "$file" ]] || return 0
  lines="$(wc -l <"$file" | tr -d ' ')"
  ((lines > 3000)) || return 0
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -F "$DEL" '{ last[$1] = $0 } END { for (k in last) print last[k] }' "$file" >"$tmp" && mv "$tmp" "$file"
}

# Right-pad by character count into a variable, without a subshell.
pad_into() {
  local -n _out=$1
  local text=$2 fill=$(($3 - ${#2}))
  ((fill < 0)) && fill=0
  printf -v _out '%s%*s' "$text" "$fill" ''
}

# ANSI colour per state, computed once (hundreds of rows, one tmux call each
# otherwise).
declare -A STATE_ANSI
state_ansi_into() {
  local -n _out=$1
  local state=$2 key=$2
  [[ "$state" == "closed" ]] && key=idle
  if [[ -z "${STATE_ANSI[$key]+set}" ]]; then
    STATE_ANSI[$key]="$(claude_style_to_ansi "$(claude_state_style "$key")")"
  fi
  _out="${STATE_ANSI[$key]}"
}

# Visible part of a row for one session, into the variable named by $1.
row_visible_into() {
  local -n _row=$1
  local state=$2 age=$3 dir=$4 title=$5 color="" c_state c_age c_dir c_title
  [[ "$USE_COLORS" == "true" ]] && state_ansi_into color "$state"
  pad_into c_state "$state" 10
  pad_into c_age "$age" 4
  pad_into c_dir "$dir" 38
  pad_into c_title "$title" 50
  _row="${color}${c_state}${color:+$RESET}  ${c_age}  ${c_dir}  ${c_title}"
}

if [[ "${1:-}" == "--deep" ]]; then
  shift
  query="$*"
  USE_COLORS="${FUZZMUX_CH_COLORS:-false}"
  RESET=$'\033[0m'
  meta="${FUZZMUX_CH_META:?}"
  if [[ -z "$query" ]]; then
    cat "${FUZZMUX_CH_ROWS:?}"
    exit 0
  fi
  command -v rg >/dev/null 2>&1 || {
    printf '%s%s\n' "-${DEL}" "ripgrep (rg) is required for searching answers"
    exit 0
  }
  # Fixed-string query inside a context-capturing regex.
  esc="$(printf '%s' "$query" | sed 's/[][\\.^$*+?(){}|\/]/\\&/g')"
  visible=""
  rg --no-messages -i --max-depth 2 -g '*.jsonl' -m 1 -o --no-heading -H \
    -e ".{0,40}${esc}.{0,40}" "$PROJECTS" 2>/dev/null | head -n 300 |
    while IFS= read -r hit; do
      path="${hit%%:*}"
      snippet="${hit#*:}"
      sid="${path##*/}"
      sid="${sid%.jsonl}"
      line="$(awk -F "$DEL" -v sid="$sid" '$1 == sid { print; exit }' "$meta")"
      [[ -n "$line" ]] || continue
      IFS="$DEL" read -r _ state age dir title <<<"$line"
      snippet="${snippet//[$'\t\r']/ }"
      row_visible_into visible "$state" "$age" "$dir" "$title"
      printf '%s%s%s  %s %s\n' "$sid" "$DEL" "$visible" "$ARROW" "$snippet"
    done
  exit 0
fi

if [[ "${1:-}" == "--preview-line" ]]; then
  line="${2:-}"
  sid="${line%%"$DEL"*}"
  [[ -n "$sid" && "$sid" != "-" ]] || exit 0
  meta="${FUZZMUX_CH_META:-}"
  if [[ -n "$meta" && -f "$meta" ]]; then
    IFS="$DEL" read -r _ state age dir title < <(awk -F "$DEL" -v sid="$sid" '$1 == sid { print; exit }' "$meta") || true
    printf '%s  %s  %s\n' "${state:-}" "${age:-}" "${dir:-}"
  fi
  loc="$(registry_lookup "$sid")"
  if [[ -n "$loc" ]]; then
    IFS="$DEL" read -r tsess _ widx _ cwd _ <<<"$loc"
    printf 'last ran in @%s #%s  %s\n' "$tsess" "$widx" "${cwd/#$HOME/\~}"
  fi
  printf 'session %s\n\n' "$sid"
  if [[ -f "$HISTORY" ]]; then
    jq -r --arg sid "$sid" 'select(.sessionId == $sid)
      | "\((.timestamp / 1000 | floor | strflocaltime("%Y-%m-%d %H:%M")))  \(.display | gsub("[\n\r\t]+"; " ") | .[0:300])"' \
      "$HISTORY" 2>/dev/null | awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }'
  fi
  exit 0
fi

# --- popup phase 1: option parsing and display-popup --------------------------------

# Check if fzf is installed
if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "fuzzmux.tmux: ERROR - fzf is not installed"
  exit 1
fi

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
  --zoom) ZOOM=true; shift ;;
  --colors) USE_COLORS=true; shift ;;
  --preview) PREVIEW=true; shift ;;
  --preview-window=*) PREVIEW_WINDOW="${1#*=}"; shift ;;
  --popup-width=*) POPUP_WIDTH="${1#*=}"; shift ;;
  --popup-height=*) POPUP_HEIGHT="${1#*=}"; shift ;;
  --popup-border=*) POPUP_BORDER="${1#*=}"; shift ;;
  --popup-color=*) POPUP_COLOR="${1#*=}"; shift ;;
  --color-palette=*) COLOR_PALETTE="${1#*=}"; shift ;;
  --fzf-bind=*) FZF_BIND_KEY="${1#*=}"; shift ;;
  --run) break ;;
  *) shift ;;
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
    -T "Find Claude Code session" \
    -w "${POPUP_WIDTH}" \
    -h "${POPUP_HEIGHT}" \
    -E "$0$ARGS --run"
  exit 0
fi

# --- popup phase 2: build the list ---------------------------------------------------

# shellcheck source=../scripts/colors.sh
source "$PLUGIN_DIR/scripts/colors.sh" "$COLOR_PALETTE"

if ! command -v jq >/dev/null 2>&1; then
  echo "fuzzmux.tmux: jq is required for the Claude Code session history."
  sleep 2
  exit 0
fi
if [[ ! -f "$HISTORY" ]]; then
  echo "fuzzmux.tmux: No Claude Code history found at $HISTORY"
  sleep 2
  exit 0
fi

registry_compact

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fuzzmux-claude-history.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ROWS="$WORK/rows"
META="$WORK/meta"
: >"$ROWS"
: >"$META"

# Sessions that still have a transcript (claude --resume needs one).
declare -A HAS_TRANSCRIPT
while IFS= read -r f; do
  f="${f##*/}"
  HAS_TRANSCRIPT["${f%.jsonl}"]=1
done < <(find "$PROJECTS" -maxdepth 2 -name '*.jsonl' 2>/dev/null)

# Running instances: session id -> pane and state.
declare -A RUN_PANE RUN_STATE
while IFS="$DEL" read -r pane state _since _detail _name _cwd _sess _win _idx _title _pa _wa _sa _src _mode sid; do
  [[ -n "${sid:-}" ]] || continue
  RUN_PANE[$sid]=$pane
  RUN_STATE[$sid]=$state
done < <(claude_agents_list)

printf -v NOW '%(%s)T' -1
visible=""

# One line per session from the prompt history, newest first:
#   sid US last_ts_ms US project US count US title US all prompts
while IFS="$DEL" read -r sid last_ts project _count title prompts; do
  [[ -n "$sid" && -n "${HAS_TRANSCRIPT[$sid]:-}" ]] || continue
  state="${RUN_STATE[$sid]:-closed}"
  secs=$((NOW - last_ts / 1000)); ((secs < 0)) && secs=0
  if ((secs < 60)); then age="${secs}s"; elif ((secs < 3600)); then age="$((secs / 60))m"; elif ((secs < 86400)); then age="$((secs / 3600))h"; else age="$((secs / 86400))d"; fi
  dir="${project/#$HOME/\~}"
  ((${#dir} > 38)) && dir="${ELLIPSIS}${dir: -37}"
  [[ -n "$title" ]] || title="-"
  ((${#title} > 50)) && title="${title:0:49}${ELLIPSIS}"
  printf '%s%s%s%s%s%s%s%s%s\n' "$sid" "$DEL" "$state" "$DEL" "$age" "$DEL" "$dir" "$DEL" "$title" >>"$META"
  row_visible_into visible "$state" "$age" "$dir" "$title"
  printf '%s%s%s  %s %s\n' "$sid" "$DEL" "$visible" "$BAR" "$prompts" >>"$ROWS"
done < <(jq -rs '
  map(select(.sessionId != null and .display != null))
  | group_by(.sessionId)
  | map({
      sid: .[0].sessionId,
      last_ts: (map(.timestamp // 0) | max),
      project: ((map(.project) | map(select(. != null)) | last) // ""),
      count: length,
      title: (((map(.display) | map(select((startswith("<") or startswith("/")) | not)) | first) // .[0].display) | gsub("[\n\r\t]+"; " ")),
      prompts: (map(.display | gsub("[\n\r\t]+"; " ") | .[0:300]) | join(" | "))
    })
  | sort_by(-.last_ts)
  | .[] | [.sid, (.last_ts | tostring), .project, (.count | tostring), .title, .prompts] | join("")' "$HISTORY" 2>/dev/null)

if [[ ! -s "$ROWS" ]]; then
  echo "fuzzmux.tmux: No Claude Code sessions with a transcript found."
  sleep 2
  exit 0
fi

export FUZZMUX_CH_ROWS="$ROWS" FUZZMUX_CH_META="$META" FUZZMUX_CH_COLORS="$USE_COLORS" CLAUDE_DEL

# --- fzf ----------------------------------------------------------------------------------

SELF="$(printf '%q' "$0")"
PROMPT_NORMAL="history > "
PROMPT_DEEP="deep > "
# The filter key toggles deep mode: the query goes to ripgrep over the transcripts
# (Claude's answers included) instead of fzf's own filtering, reloading on every
# keystroke.
BIND_TOGGLE="${FZF_BIND_KEY}:transform:if [[ \$FZF_PROMPT == '${PROMPT_DEEP}' ]]; then echo 'change-prompt(${PROMPT_NORMAL})+enable-search+reload(cat \"\$FUZZMUX_CH_ROWS\")'; else echo 'change-prompt(${PROMPT_DEEP})+disable-search+reload(${SELF} --deep {q})'; fi"
BIND_CHANGE="change:transform:[[ \$FZF_PROMPT == '${PROMPT_DEEP}' ]] && echo 'reload(${SELF} --deep {q})' || true"
PREVIEW_CMD="${SELF} --preview-line {}"

FZF_ARGS=(--ansi --exact --exit-0 --no-hscroll --prompt "$PROMPT_NORMAL"
  --delimiter="$DEL" --with-nth=2
  --bind="$BIND_TOGGLE" --bind="$BIND_CHANGE")
if [[ "$PREVIEW" == "true" ]]; then
  FZF_ARGS+=(--preview "$PREVIEW_CMD" --preview-window="$PREVIEW_WINDOW")
fi

SELECTION=$(fzf "${FZF_ARGS[@]}" <"$ROWS") || exit 0
sid="${SELECTION%%"$DEL"*}"
[[ -n "$sid" && "$sid" != "-" ]] || exit 0

# --- act: switch to the running instance, or resume where it last ran -----------------

goto_pane() {
  local pane=$1 session window
  session="$(tmux display-message -p -t "$pane" '#{session_name}')"
  window="$(tmux display-message -p -t "$pane" '#{window_index}')"
  tmux select-pane -t "$pane"
  tmux switch-client -t "${session}:${window}"
  if [[ "$ZOOM" == "true" ]]; then
    [[ "$(tmux display-message -t "$pane" -p '#{window_zoomed_flag}')" == "1" ]] || tmux resize-pane -Z -t "$pane"
  fi
}

if [[ -n "${RUN_PANE[$sid]:-}" ]] && tmux display-message -p -t "${RUN_PANE[$sid]}" '#{pane_id}' >/dev/null 2>&1; then
  goto_pane "${RUN_PANE[$sid]}"
  exit 0
fi

# Where did it run last time? Registry first, project directory as fallback.
tsess="" wid="" cwd=""
loc="$(registry_lookup "$sid")"
if [[ -n "$loc" ]]; then
  IFS="$DEL" read -r tsess wid _ _ cwd _ <<<"$loc"
fi
[[ -n "$cwd" ]] || cwd="$(awk -F "$DEL" -v sid="$sid" '$1 == sid { print $3; exit }' "$META")"
cwd="${cwd/#\~/$HOME}"
[[ -d "$cwd" ]] || cwd="$HOME"

claude_cmd="$(claude_option @fuzzmux-claude-command claude)"
run_cmd="$(printf '%s --resume %q; exec "${SHELL:-sh}"' "$claude_cmd" "$sid")"

if [[ -n "$wid" ]] && tmux list-windows -a -F '#{window_id}' | grep -qx -- "$wid"; then
  # Same place: a new pane in the window it last ran in.
  new_pane="$(tmux split-window -P -F '#{pane_id}' -t "$wid" -c "$cwd" "$run_cmd")"
elif [[ -n "$tsess" ]] && tmux has-session -t "=$tsess" 2>/dev/null; then
  new_pane="$(tmux new-window -P -F '#{pane_id}' -t "${tsess}:" -c "$cwd" "$run_cmd")"
else
  new_pane="$(tmux new-window -P -F '#{pane_id}' -c "$cwd" "$run_cmd")"
fi
goto_pane "$new_pane"
