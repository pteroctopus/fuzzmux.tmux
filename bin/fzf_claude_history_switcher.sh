#!/usr/bin/env bash
set -euo pipefail

# fuzzmux.tmux - Claude Code session history: fzf over every line of every
# conversation ever run (your prompts and Claude's answers), plain fzf matching;
# ctrl-f switches to a one-row-per-session overview. Enter jumps to the running
# instance or resumes the session where it last ran.
#
# Modes (internal, driven by the popup and fzf):
#   <no --run>          open the popup, re-invoke with --run
#   --run               build the lists and run fzf
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
# Readable text of every conversation (your prompts and Claude's answers, no
# tool output or JSON), one file per session, refreshed from the transcript when
# it changed. The text rows and the preview come from these.
TEXT_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/fuzzmux/claude-text"
ELLIPSIS="$(printf '\342\200\246')" # U+2026
# The bar separates the fields of an fzf row (sid, line number, prefix, text) and
# doubles as the visible column separator, so fzf can limit matching to the text.
BAR="$(printf '\342\224\202')"      # U+2502
PROMPT_TEXT="text > "
PROMPT_SESSIONS="sessions > "

# --- shared helpers --------------------------------------------------------------

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

# ANSI colour per state, computed once.
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

# --- fzf preview ------------------------------------------------------------------------

if [[ "${1:-}" == "--preview-line" ]]; then
  line="${2:-}"
  sid="${line%%"$BAR"*}"
  rest="${line#*"$BAR"}"
  lineno="${rest%%"$BAR"*}"
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

  # A text row: the conversation around that line, the line itself highlighted.
  if [[ "$lineno" =~ ^[0-9]+$ && -f "$TEXT_CACHE/$sid.txt" ]]; then
    from=$((lineno - 12)); ((from < 1)) && from=1
    awk -v from="$from" -v to="$((lineno + 25))" -v hit="$lineno" \
      'NR >= from && NR <= to { if (NR == hit) printf "\033[7m%s\033[0m\n", $0; else print }' "$TEXT_CACHE/$sid.txt"
    exit 0
  fi

  # A session row: the session's prompts, newest first.
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
ROWS="$WORK/rows"       # one row per session
TEXT_ROWS="$WORK/text"  # one row per conversation line
META="$WORK/meta"
: >"$ROWS"
: >"$TEXT_ROWS"
: >"$META"

# Sessions that still have a transcript (claude --resume needs one), and the
# text cache for each: rebuilt only when the transcript is newer.
declare -A TRANSCRIPT
mkdir -p "$TEXT_CACHE"
while IFS= read -r f; do
  sid="${f##*/}"
  sid="${sid%.jsonl}"
  TRANSCRIPT[$sid]="$f"
  cache="$TEXT_CACHE/$sid.txt"
  if [[ ! -f "$cache" || "$f" -nt "$cache" ]]; then
    jq -r '
      select(.type == "user" or .type == "assistant")
      | (.message.content // empty) as $c
      | ( if ($c | type) == "string" then $c
          elif ($c | type) == "array" then ($c | map(select(.type == "text") | .text) | join("\n"))
          else "" end ) as $t
      | select(($t | length) > 0)
      | "[\(.type) \((.timestamp // "")[0:16] | sub("T"; " "))]\n\($t)\n"' "$f" >"$cache.tmp" 2>/dev/null
    if [[ -s "$cache.tmp" || -f "$cache.tmp" ]]; then mv "$cache.tmp" "$cache"; else rm -f "$cache.tmp"; fi
  fi
done < <(find "$PROJECTS" -maxdepth 2 -name '*.jsonl' 2>/dev/null)
# Drop cached text of sessions whose transcript is gone.
for cache in "$TEXT_CACHE"/*.txt; do
  [[ -f "$cache" ]] || continue
  sid="${cache##*/}"
  [[ -n "${TRANSCRIPT[${sid%.txt}]+set}" ]] || rm -f "$cache"
done

# Running instances: session id -> pane and state.
declare -A RUN_PANE RUN_STATE
while IFS="$DEL" read -r pane state _since _detail _name _cwd _sess _win _idx _title _pa _wa _sa _src _mode sid; do
  [[ -n "${sid:-}" ]] || continue
  RUN_PANE[$sid]=$pane
  RUN_STATE[$sid]=$state
done < <(claude_agents_list)

printf -v NOW '%(%s)T' -1
visible="" color="" c_state="" c_age="" c_dir=""

# One line per session from the prompt history, newest first:
#   sid US last_ts_ms US project US count US title US all prompts
while IFS="$DEL" read -r sid last_ts project _count title prompts; do
  [[ -n "$sid" && -n "${TRANSCRIPT[$sid]+set}" ]] || continue
  state="${RUN_STATE[$sid]:-closed}"
  secs=$((NOW - last_ts / 1000)); ((secs < 0)) && secs=0
  if ((secs < 60)); then age="${secs}s"; elif ((secs < 3600)); then age="$((secs / 60))m"; elif ((secs < 86400)); then age="$((secs / 3600))h"; else age="$((secs / 86400))d"; fi
  dir="${project/#$HOME/\~}"
  ((${#dir} > 38)) && dir="${ELLIPSIS}${dir: -37}"
  [[ -n "$title" ]] || title="-"
  ((${#title} > 50)) && title="${title:0:49}${ELLIPSIS}"
  # meta: sid US state US age US dir(display) US title US project(full path)
  printf '%s%s%s%s%s%s%s%s%s%s%s\n' "$sid" "$DEL" "$state" "$DEL" "$age" "$DEL" "$dir" "$DEL" "$title" "$DEL" "$project" >>"$META"
  row_visible_into visible "$state" "$age" "$dir" "$title"
  # fzf rows, bar-separated: sid | lineno (- for a session row) | prefix | text
  printf '%s%s-%s%s%s %s\n' "$sid" "$BAR" "$BAR" "$visible" "$BAR" "$prompts" >>"$ROWS"
  # Every line of the conversation as a row of its own.
  state_ansi_into color "$state"
  pad_into c_state "$state" 10
  pad_into c_age "$age" 4
  pad_into c_dir "$dir" 38
  awk -v sid="$sid" -v pre="${color}${c_state}${color:+$RESET}  ${c_age}  ${c_dir}" -v bar="$BAR" \
    'NF { printf "%s%s%d%s%s%s %s\n", sid, bar, NR, bar, pre, bar, $0 }' "$TEXT_CACHE/$sid.txt" >>"$TEXT_ROWS" 2>/dev/null || true
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

export FUZZMUX_CH_ROWS="$ROWS" FUZZMUX_CH_TEXT="$TEXT_ROWS" FUZZMUX_CH_META="$META" CLAUDE_DEL

# --- fzf ----------------------------------------------------------------------------------

SELF="$(printf '%q' "$0")"
# Default list: every conversation line, newest session first, matched by fzf
# itself and only on the text after the bar (--nth=2.. of the displayed part),
# so state, age and project never skew a text search. The filter key swaps in
# the one-row-per-session overview, where everything is searchable, with a
# cleared query; and back.
BIND_TOGGLE="${FZF_BIND_KEY}:transform:if [[ \$FZF_PROMPT == '${PROMPT_TEXT}' ]]; then echo 'change-prompt(${PROMPT_SESSIONS})+reload(cat \"\$FUZZMUX_CH_ROWS\")+change-nth(1..)+clear-query+first+refresh-preview'; else echo 'change-prompt(${PROMPT_TEXT})+reload(cat \"\$FUZZMUX_CH_TEXT\")+change-nth(2..)+clear-query+first+refresh-preview'; fi"
PREVIEW_CMD="${SELF} --preview-line {}"
h_state="" h_age="" h_dir=""
pad_into h_state "state" 10
pad_into h_age "age" 4
pad_into h_dir "project" 38
HEADER="${h_state}  ${h_age}  ${h_dir}  ${BAR} conversation line (${FZF_BIND_KEY}: sessions overview)"

FZF_ARGS=(--ansi --exit-0 --no-hscroll --tiebreak=index --prompt "$PROMPT_TEXT"
  --delimiter="$BAR" --with-nth=3.. --nth=2.. --header="$HEADER"
  --bind="$BIND_TOGGLE")
if [[ "$PREVIEW" == "true" ]]; then
  FZF_ARGS+=(--preview "$PREVIEW_CMD" --preview-window="$PREVIEW_WINDOW")
fi

SELECTION=$(fzf "${FZF_ARGS[@]}" <"$TEXT_ROWS") || exit 0
sid="${SELECTION%%"$BAR"*}"
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

# Where did it run last time? Registry first; the session's project directory
# (full path from the metadata) when the registry has nothing or the recorded
# directory is gone.
tsess="" wid="" cwd=""
loc="$(registry_lookup "$sid")"
if [[ -n "$loc" ]]; then
  IFS="$DEL" read -r tsess wid _ _ cwd _ <<<"$loc"
fi
if [[ -z "$cwd" || ! -d "$cwd" ]]; then
  cwd="$(awk -F "$DEL" -v sid="$sid" '$1 == sid { print $6; exit }' "$META")"
fi
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
