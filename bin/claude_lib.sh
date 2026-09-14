#!/usr/bin/env bash
# Shared helpers for the fuzzmux Claude Code agent features.
# Sourced by fzf_claude_switcher.sh and claude_status.sh - not executed directly.
#
# Two data sources are merged into one view of "Claude Code instances running in
# tmux panes":
#
#  1. Claude Code's own per-process state files (no setup required):
#       ${CLAUDE_CONFIG_DIR:-~/.claude}/sessions/<pid>.json
#     Every interactive session records the pane it runs in
#     ("tmux": "session:@window.%pane") and a status: "busy", "idle", "waiting"
#     (blocked on a permission prompt or question), or the kind of background
#     work still running after the turn ended ("shell", "monitor", "agent").
#     This is the same data `claude agents --json` prints.
#
#  2. Pane user options written by bin/claude_hook.sh (optional; registered in
#     Claude Code's hook settings by bin/claude_hooks_install.sh):
#       @fuzzmux-claude-state   permission | question | waiting | working |
#                               background | idle
#       @fuzzmux-claude-since   epoch seconds when that state was entered
#       @fuzzmux-claude-detail  free text, e.g. the tool awaiting permission
#       @fuzzmux-claude-mode    Claude's permission mode (hook payloads only)
#     Hooks are event-driven and know things the state file does not: which
#     tool waits for permission, whether a question is pending, and only hooks
#     can tell an unread finished turn ("waiting") from an agent whose output
#     you already looked at ("idle", see bin/claude_focus.sh). The state file in
#     turn is the only source that knows about background work ("background":
#     the turn is over but a shell, monitor or agent still runs and will wake
#     the agent up by itself).
#
# claude_agents_list prints one row per live agent, most urgent first, with
# fields separated by CLAUDE_DEL (ASCII unit separator - unlike a tab it is not
# whitespace, so `read` keeps empty fields in place):
#   pane_id state since detail name cwd session window pane_index title
#   pane_active window_active session_attached source mode session_id

CLAUDE_DEL=$'\x1f'
# Claude Code prefixes its pane title with this glyph (U+2733, as UTF-8 bytes so
# the file stays ASCII and the value does not depend on the locale).
CLAUDE_TITLE_GLYPH="$(printf '\342\234\263')"

claude_config_dir() {
  printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

# Where the hook records the last tmux location of every Claude session
# (session id, tmux session, window id, window index, pane, cwd, epoch), one
# appended line per event; readers take the last line per session id.
claude_registry_file() {
  printf '%s/fuzzmux/claude-sessions.log' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# Read a global tmux option, falling back to a default when unset/empty.
claude_option() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  printf '%s' "${value:-$2}"
}

# Urgency rank: lower sorts first.
claude_state_rank() {
  case "$1" in
  permission) echo 0 ;;
  question) echo 1 ;;
  waiting) echo 2 ;;
  working) echo 3 ;;
  background) echo 4 ;;
  idle) echo 5 ;;
  *) echo 6 ;;
  esac
}

# Coarse class of one of OUR states (apply claude_file_state first for file
# statuses), used to reconcile the two sources.
claude_state_class() {
  case "$1" in
  working) echo busy ;;
  permission | question) echo blocked ;;
  background) echo background ;;
  waiting | idle) echo idle ;;
  *) echo other ;;
  esac
}

# Map the status found in Claude's state file onto our state vocabulary. The
# file cannot tell unread output from read output, so not busy is plain idle;
# "waiting" there means blocked on the user, i.e. a permission prompt in most
# cases; anything else names background work that is still running.
claude_file_state() {
  case "$1" in
  busy | compacting) echo working ;;
  idle | starting | "") echo idle ;;
  waiting) echo permission ;;
  error) echo error ;;
  *) echo background ;;
  esac
}

# tmux style (see STYLES in tmux(1)) used for a state, read from the
# @fuzzmux-claude-<group>-style options so users can theme them like tmux's own
# *-style options. Defaults use the terminal's named colors. Shared by the status
# snippet (styles pass straight through) and the picker (converted to ANSI).
claude_state_style() {
  case "$1" in
  permission | question | attention) claude_option @fuzzmux-claude-attention-style 'fg=red,bold' ;;
  waiting) claude_option @fuzzmux-claude-waiting-style 'fg=yellow' ;;
  working) claude_option @fuzzmux-claude-working-style 'fg=brightgreen' ;;
  background) claude_option @fuzzmux-claude-background-style 'fg=cyan' ;;
  idle) claude_option @fuzzmux-claude-idle-style 'dim' ;;
  *) printf '' ;;
  esac
}

# SGR parameter for a tmux colour name: named colours (optionally bright*),
# colourN/colorN, #rrggbb, default. $2 is 3 for foreground, 4 for background.
claude_color_code() {
  local color="$1" plane="$2" bright=0 base hex
  case "$color" in
  default | terminal) printf '%s9' "$plane"; return ;;
  \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
    hex="${color#\#}"
    printf '%s8;2;%d;%d;%d' "$plane" "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
    return ;;
  colour[0-9]* | color[0-9]*) printf '%s8;5;%s' "$plane" "${color##*[a-z]}"; return ;;
  bright*) bright=1; color="${color#bright}" ;;
  esac
  case "$color" in
  black) base=0 ;; red) base=1 ;; green) base=2 ;; yellow) base=3 ;;
  blue) base=4 ;; magenta) base=5 ;; cyan) base=6 ;; white) base=7 ;;
  *) return ;;
  esac
  if ((bright)); then
    [[ "$plane" == 3 ]] && printf '%d' $((90 + base)) || printf '%d' $((100 + base))
  else
    printf '%d%d' "$plane" "$base"
  fi
}

# Convert a tmux style string (fg=, bg=, bold, dim, italics, underscore, blink,
# reverse, default/none; comma separated) into one ANSI SGR sequence. Unknown
# tokens are ignored. Empty when nothing applies.
claude_style_to_ansi() {
  local style="$1" token code params=""
  local IFS=','
  for token in $style; do
    code=""
    case "$token" in
    fg=*) code="$(claude_color_code "${token#fg=}" 3)" ;;
    bg=*) code="$(claude_color_code "${token#bg=}" 4)" ;;
    bold | bright) code=1 ;;
    dim) code=2 ;;
    italics) code=3 ;;
    underscore) code=4 ;;
    blink) code=5 ;;
    reverse) code=7 ;;
    default | none) code=0 ;;
    esac
    [[ -n "$code" ]] && params+="${params:+;}${code}"
  done
  [[ -n "$params" ]] && printf '\033[%sm' "$params"
  return 0
}

# Right-pad $1 with spaces to $2 characters (character count, so UTF-8 titles
# do not throw the columns off the way byte-based padding would).
claude_pad() {
  local text="$1" fill=$(($2 - ${#1}))
  ((fill < 0)) && fill=0
  printf '%s%*s' "$text" "$fill" ''
}

# Short label for a Claude Code permission mode, "-" when unknown (no hooks).
claude_mode_label() {
  case "$1" in
  default) echo manual ;;
  acceptEdits) echo edits ;;
  bypassPermissions) echo bypass ;;
  dontAsk) echo dontask ;;
  "") echo "-" ;;
  *) echo "$1" ;;
  esac
}

# Strip the glyph Claude Code prepends to the pane title.
claude_clean_title() {
  local title="$1"
  title="${title#"${CLAUDE_TITLE_GLYPH}" }"
  title="${title#"${CLAUDE_TITLE_GLYPH}"}"
  printf '%s' "$title"
}

# Humanize an age in seconds: 42s, 5m, 3h, 2d.
claude_age() {
  local s=$1
  ((s < 0)) && s=0
  if ((s < 60)); then
    printf '%ds' "$s"
  elif ((s < 3600)); then
    printf '%dm' $((s / 60))
  elif ((s < 86400)); then
    printf '%dh' $((s / 3600))
  else
    printf '%dd' $((s / 86400))
  fi
}

# True when a pane's foreground command is an interactive shell (Claude exited).
claude_is_shell() {
  case "$1" in
  sh | bash | zsh | fish | dash | ksh | tcsh | csh | nu) return 0 ;;
  *) return 1 ;;
  esac
}

# Remove stale hook state from a pane whose Claude process is gone.
claude_clear_pane_state() {
  tmux set-option -pu -t "$1" @fuzzmux-claude-state 2>/dev/null || true
  tmux set-option -pu -t "$1" @fuzzmux-claude-since 2>/dev/null || true
  tmux set-option -pu -t "$1" @fuzzmux-claude-detail 2>/dev/null || true
}

claude_agents_list() {
  local DEL="$CLAUDE_DEL"

  # --- All panes in one tmux call, hook state included via pane user options.
  local -A P_SESSION P_WINDOW P_INDEX P_TITLE P_CMD P_ACTIVE P_WACTIVE P_ATTACHED
  local -A P_STATE P_SINCE P_DETAIL P_PATH P_MODE
  local pane sess win idx title cmd active wactive attached hstate hsince hdetail hmode path
  local format
  format="#{pane_id}${DEL}#{session_name}${DEL}#{window_index}${DEL}#{pane_index}${DEL}"
  format+="#{pane_title}${DEL}#{pane_current_command}${DEL}#{pane_active}${DEL}"
  format+="#{window_active}${DEL}#{session_attached}${DEL}#{@fuzzmux-claude-state}${DEL}"
  format+="#{@fuzzmux-claude-since}${DEL}#{@fuzzmux-claude-detail}${DEL}#{@fuzzmux-claude-mode}${DEL}"
  format+="#{pane_current_path}"
  while IFS="$DEL" read -r pane sess win idx title cmd active wactive attached hstate hsince hdetail hmode path; do
    [[ "$pane" =~ ^%[0-9]+$ ]] || continue
    P_SESSION[$pane]=$sess
    P_WINDOW[$pane]=$win
    P_INDEX[$pane]=$idx
    P_TITLE[$pane]=$title
    P_CMD[$pane]=$cmd
    P_ACTIVE[$pane]=$active
    P_WACTIVE[$pane]=$wactive
    P_ATTACHED[$pane]=$attached
    P_PATH[$pane]=$path
    P_MODE[$pane]=$hmode
    if [[ -n "$hstate" ]]; then
      P_STATE[$pane]=$hstate
      P_SINCE[$pane]=$hsince
      P_DETAIL[$pane]=$hdetail
    fi
  done < <(tmux list-panes -a -F "$format" 2>/dev/null)

  # --- Claude Code state files (one jq call per file so a corrupt file cannot
  # take the others down).
  local -A F_STATUS F_SINCE F_NAME F_CWD F_SID
  local dir f row cpid fstatus fsince fname fcwd fsid
  dir="$(claude_config_dir)/sessions"
  if command -v jq >/dev/null 2>&1 && [[ -d "$dir" ]]; then
    for f in "$dir"/*.json; do
      [[ -f "$f" ]] || continue
      row="$(jq -r '
        select((.kind // "interactive") == "interactive"
               and ((.tmux // "") | type) == "string" and (.tmux // "") != "")
        | [ (.pid | tostring), (.tmux | split(".") | last), (.status // ""),
            ((.statusUpdatedAt // .updatedAt // .startedAt // 0) | tostring),
            (.name // ""), (.cwd // ""), (.sessionId // "") ]
        | map(tostring) | join("\u001f")' "$f" 2>/dev/null)" || continue
      [[ -n "$row" ]] || continue
      IFS="$DEL" read -r cpid pane fstatus fsince fname fcwd fsid <<<"$row"
      [[ "$cpid" =~ ^[0-9]+$ && "$pane" =~ ^%[0-9]+$ ]] || continue
      kill -0 "$cpid" 2>/dev/null || continue # process gone: stale file
      [[ -n "${P_SESSION[$pane]:-}" ]] || continue # pane gone
      [[ "$fsince" =~ ^[0-9]+$ ]] || fsince=0
      ((fsince > 100000000000)) && fsince=$((fsince / 1000)) # ms -> s
      F_STATUS[$pane]=$fstatus
      F_SINCE[$pane]=$fsince
      F_NAME[$pane]=$fname
      F_CWD[$pane]=$fcwd
      F_SID[$pane]=$fsid
    done
  fi

  # --- Merge. Background work is only visible in the state file, so that wins
  # outright. Otherwise the hook state is richer and wins whenever both sources
  # agree on the coarse class; when they disagree the more recent source wins
  # (covers a hook left at "working" after the user interrupted Claude with
  # Esc, where no Stop fires, and a permission prompt the file still calls busy).
  local -A SEEN
  local state since detail origin fstate fclass hclass cwd out=""
  for pane in "${!F_STATUS[@]}" "${!P_STATE[@]}"; do
    [[ -n "${SEEN[$pane]:-}" ]] && continue
    SEEN[$pane]=1
    [[ -n "${P_SESSION[$pane]:-}" ]] || continue
    hstate="${P_STATE[$pane]:-}"
    fstatus="${F_STATUS[$pane]:-}"
    hsince="${P_SINCE[$pane]:-0}"
    [[ "$hsince" =~ ^[0-9]+$ ]] || hsince=0

    if [[ -n "$hstate" && -z "$fstatus" ]] && claude_is_shell "${P_CMD[$pane]}"; then
      # Hook state left behind by a Claude process that is gone.
      claude_clear_pane_state "$pane"
      continue
    fi

    fstate=""
    fclass=""
    if [[ -n "$fstatus" ]]; then
      fstate="$(claude_file_state "$fstatus")"
      fclass="$(claude_state_class "$fstate")"
    fi
    if [[ -n "$fstatus" && "$fclass" == "background" ]]; then
      state=background; since="${F_SINCE[$pane]}"; detail="$fstatus"; origin="file"
    elif [[ -n "$hstate" && -n "$fstatus" ]]; then
      hclass="$(claude_state_class "$hstate")"
      if [[ "$fclass" == "$hclass" || "$hsince" -ge "${F_SINCE[$pane]}" ]]; then
        state=$hstate; since=$hsince; detail="${P_DETAIL[$pane]:-}"; origin="hook"
      else
        state=$fstate; since="${F_SINCE[$pane]}"; detail=""; origin="file"
      fi
    elif [[ -n "$hstate" ]]; then
      state=$hstate; since=$hsince; detail="${P_DETAIL[$pane]:-}"; origin="hook"
    else
      state=$fstate; since="${F_SINCE[$pane]}"; detail=""; origin="file"
    fi

    cwd="${F_CWD[$pane]:-${P_PATH[$pane]}}"
    cwd="${cwd/#$HOME/\~}"

    out+="$(claude_state_rank "$state")${DEL}${since}${DEL}"
    out+="${pane}${DEL}${state}${DEL}${since}${DEL}${detail}${DEL}${F_NAME[$pane]:-}${DEL}${cwd}${DEL}"
    out+="${P_SESSION[$pane]}${DEL}${P_WINDOW[$pane]}${DEL}${P_INDEX[$pane]}${DEL}"
    out+="$(claude_clean_title "${P_TITLE[$pane]}")${DEL}"
    out+="${P_ACTIVE[$pane]}${DEL}${P_WACTIVE[$pane]}${DEL}${P_ATTACHED[$pane]}${DEL}${origin}${DEL}"
    out+="${P_MODE[$pane]:-}${DEL}${F_SID[$pane]:-}"$'\n'
  done

  [[ -n "$out" ]] || return 0
  # Sort by urgency, then most recent state change first; drop the sort keys.
  printf '%s' "$out" | sort -t "$DEL" -k1,1n -k2,2nr | cut -d "$DEL" -f 3-
}
