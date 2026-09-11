#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$CURRENT_DIR")"

get_tmux_option() {
  local value
  value=$(tmux show-option -gqv "$1")
  echo "${value:-$2}"
}

# Check dependencies
if [[ -z "${TMUX:-}" ]]; then
  echo "fuzzmux.tmux: Must be run from inside tmux"
  exit 1
fi

# TMUX_VERSION=$(tmux -V | cut -d' ' -f2)
# if ! printf '%s\n3.2\n' "$TMUX_VERSION" | sort -V -C; then
#   tmux display-message "fuzzmux.tmux: ERROR - tmux version 3.2+ required (current: $TMUX_VERSION)"
#   exit 1
# fi

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "fuzzmux.tmux: ERROR - fzf is not installed. See: https://github.com/junegunn/fzf"
  exit 1
fi

command -v bat >/dev/null 2>&1 || tmux display-message "fuzzmux.tmux: WARNING - bat not found (optional, for better previews)"
command -v column >/dev/null 2>&1 || tmux display-message "fuzzmux.tmux: WARNING - column not found (optional, for formatting)"
command -v jq >/dev/null 2>&1 || tmux display-message "fuzzmux.tmux: WARNING - jq not found (optional, for Claude Code agent detection)"

# Unbind previous keys
for key in session session-zoom pane pane-zoom window window-zoom nvim nvim-zoom claude claude-zoom claude-history claude-history-zoom jump-back jump-forward; do
  prev_key=$(get_tmux_option "@fuzzmux-prev-bind-${key}" "")
  if [[ -n "$prev_key" ]]; then
    # Handle '!' prefix marker for root table bindings
    if [[ "${prev_key}" == \!* ]]; then
      tmux unbind-key -n "${prev_key:1}" 2>/dev/null || true
    else
      tmux unbind-key "$prev_key" 2>/dev/null || true
    fi
  fi
done

# Build popup arguments (shared by all features)
POPUP_ARGS=" --popup-width=$(get_tmux_option '@fuzzmux-popup-width' '90%')"
POPUP_ARGS+=" --popup-height=$(get_tmux_option '@fuzzmux-popup-height' '90%')"
POPUP_ARGS+=" --popup-border=$(get_tmux_option '@fuzzmux-popup-border-style' 'rounded')"
POPUP_ARGS+=" --popup-color=$(get_tmux_option '@fuzzmux-popup-border-color' 'white')"

declare -A FUZZMUX_DEFAULT_KEYS=(
  [session]=s
  [session-zoom]=S
  [pane]=p
  [pane-zoom]=P
  [window]=w
  [window-zoom]=W
  [nvim]=f
  [nvim-zoom]=F
  [claude]=a
  [claude-zoom]=A
  [claude-history]=y
  [claude-history-zoom]=Y
  [fzf-bind-filtering]=ctrl-f
)

# Bind keys for each enabled feature (supports leading '!' marker for no-prefix binds)
bind_feature() {
  local feature=$1 script=$2 key_opt=$3 key_zoom_opt=$4

  # Feature enablement (default ON)
  [[ "$(get_tmux_option "@fuzzmux-${feature}-enabled" '1')" != "1" ]] && return

  # Get configured/raw keys (raw preserves marker '!' if present)
  local key_name="${feature}"
  local default_key="${FUZZMUX_DEFAULT_KEYS[$key_name]}"
  local key_raw
  key_raw="$(get_tmux_option "$key_opt" "$default_key")"

  local key_zoom_name="${feature}-zoom"
  local default_key_zoom="${FUZZMUX_DEFAULT_KEYS[$key_zoom_name]}"
  local key_zoom_raw
  key_zoom_raw="$(get_tmux_option "$key_zoom_opt" "$default_key_zoom")"

  # Sanity: must have a value (raw may include leading '!')
  [[ -z "$key_raw" || -z "$key_zoom_raw" ]] && return

  # Detect marker '!' meaning "bind without prefix" and strip it for the real tmux token
  local key_prefixless=false
  local key_zoom_prefixless=false
  local key key_zoom

  if [[ "${key_raw}" == \!* ]]; then
    key_prefixless=true
    key="${key_raw:1}"
  else
    key="$key_raw"
  fi

  if [[ "${key_zoom_raw}" == \!* ]]; then
    key_zoom_prefixless=true
    key_zoom="${key_zoom_raw:1}"
  else
    key_zoom="$key_zoom_raw"
  fi

  # After stripping marker, still must be non-empty
  [[ -z "$key" || -z "$key_zoom" ]] && return

  # Build feature-specific arguments (ensure POPUP_ARGS default)
  local args="${POPUP_ARGS:-}"
  [[ "$(get_tmux_option "@fuzzmux-${feature}-preview-enabled" '1')" == "1" ]] && args+=" --preview"
  [[ "$(get_tmux_option '@fuzzmux-colors-enabled' '1')" == "1" ]] && args+=" --colors"
  local palette="$(get_tmux_option '@fuzzmux-color-palette' '')"
  [[ -n "$palette" ]] && args+=" --color-palette=$palette"
  local preview_window="$(get_tmux_option @fuzzmux-${feature}-preview-window right:30%)"
  [[ -n $preview_window ]] && args+=" --preview-window=$preview_window"

  
  # Add fzf bind key (single key for progressive filtering)
  local fzf_bind
  fzf_bind="$(get_tmux_option '@fuzzmux-fzf-bind-filtering' "${FUZZMUX_DEFAULT_KEYS[fzf-bind-filtering]}")"
  [[ -n "$fzf_bind" ]] && args+=" --fzf-bind=$fzf_bind"

  # Perform binds: prefix (default) or no-prefix (-n)
  if $key_prefixless; then
    tmux bind-key -n "$key" run-shell "${PLUGIN_DIR}/bin/${script}${args}"
  else
    tmux bind-key "$key" run-shell "${PLUGIN_DIR}/bin/${script}${args}"
  fi

  if $key_zoom_prefixless; then
    tmux bind-key -n "$key_zoom" run-shell "${PLUGIN_DIR}/bin/${script}${args} --zoom"
  else
    tmux bind-key "$key_zoom" run-shell "${PLUGIN_DIR}/bin/${script}${args} --zoom"
  fi

  # Remember previous binds (store raw so marker is visible)
  tmux set-option -g "@fuzzmux-prev-bind-${feature}" "$key_raw"
  tmux set-option -g "@fuzzmux-prev-bind-${feature}-zoom" "$key_zoom_raw"
}

# Focus hooks fired on active-pane change, shared by the jumplist recorder and
# the Claude Code "seen" tracker. Listed once so install and removal stay in sync.
FOCUS_HOOKS=(pane-focus-in after-select-pane after-select-window \
  client-session-changed session-window-changed)

# Install <script> on every focus hook (idempotent: the <flag> global option
# survives config reload, so re-sourcing ~/.tmux.conf does not append twice).
install_focus_hooks() {
  local script=$1 flag=$2 h
  [[ "$(get_tmux_option "$flag" '0')" == "1" ]] && return
  tmux set -g focus-events on
  for h in "${FOCUS_HOOKS[@]}"; do
    tmux set-hook -ga "$h" "run-shell -b '${PLUGIN_DIR}/bin/${script} #{pane_id}'"
  done
  tmux set-option -g "$flag" 1
}

# Remove only the hooks running <script>, preserving user hooks and the other
# feature's hooks on the same events. Scans both server (-g) and window (-gw)
# scopes because pane-focus-in is a window hook. Re-reads each pass so index
# shifts from prior removals are handled.
remove_focus_hooks() {
  local script=$1 flag=$2 line hook idx
  while line="$({ tmux show-hooks -g; tmux show-hooks -gw; } 2>/dev/null | grep -m1 "$script")"; do
    [[ -z "$line" ]] && break
    hook="${line%%\[*}"
    idx="${line#*\[}"
    idx="${idx%%\]*}"
    tmux set-hook -gu "${hook}[${idx}]" 2>/dev/null || true
  done
  tmux set-option -gu "$flag" 2>/dev/null || true
}

# Bind a single jumplist direction, honouring the '!' no-prefix marker.
bind_jump_key() {
  local key_raw=$1 nav_arg=$2
  if [[ "${key_raw}" == \!* ]]; then
    tmux bind-key -n "${key_raw:1}" run-shell "${PLUGIN_DIR}/bin/jumplist_nav.sh ${nav_arg}"
  else
    tmux bind-key "${key_raw}" run-shell "${PLUGIN_DIR}/bin/jumplist_nav.sh ${nav_arg}"
  fi
}

# Bind back/forward keys and record them for the unbind loop.
bind_jumplist() {
  local back_raw fwd_raw
  back_raw="$(get_tmux_option '@fuzzmux-bind-jump-back' 'C-h')"
  fwd_raw="$(get_tmux_option '@fuzzmux-bind-jump-forward' 'C-l')"
  [[ -z "$back_raw" || -z "$fwd_raw" ]] && return

  bind_jump_key "$back_raw" "--back"
  bind_jump_key "$fwd_raw" "--forward"

  tmux set-option -g "@fuzzmux-prev-bind-jump-back" "$back_raw"
  tmux set-option -g "@fuzzmux-prev-bind-jump-forward" "$fwd_raw"
}

if [[ "$(get_tmux_option '@fuzzmux-enable-bindings' '1')" == "1" ]]; then
  bind_feature session fzf_session_switcher.sh @fuzzmux-bind-session @fuzzmux-bind-session-zoom
  bind_feature pane fzf_pane_switcher.sh @fuzzmux-bind-pane @fuzzmux-bind-pane-zoom
  bind_feature window fzf_window_switcher.sh @fuzzmux-bind-window @fuzzmux-bind-window-zoom
  bind_feature nvim fzf_nvim_buffer_switcher.sh @fuzzmux-bind-nvim @fuzzmux-bind-nvim-zoom
  bind_feature claude fzf_claude_switcher.sh @fuzzmux-bind-claude @fuzzmux-bind-claude-zoom
  bind_feature claude-history fzf_claude_history_switcher.sh @fuzzmux-bind-claude-history @fuzzmux-bind-claude-history-zoom
else
  # Clear stored bind options when bindings are disabled (clean slate)
  for key in session session-zoom pane pane-zoom window window-zoom nvim nvim-zoom claude claude-zoom claude-history claude-history-zoom jump-back jump-forward; do
    tmux set-option -gu "@fuzzmux-prev-bind-${key}" 2>/dev/null || true
  done
fi

# --- Pane jumplist (back/forward focused-pane navigation) ---
# Hooks track history independently of the binding toggle; the jump keys are
# only bound when bindings are also enabled.
if [[ "$(get_tmux_option '@fuzzmux-jumplist-enabled' '1')" == "1" ]]; then
  install_focus_hooks jumplist_record.sh @fuzzmux-jumplist-installed
  if [[ "$(get_tmux_option '@fuzzmux-enable-bindings' '1')" == "1" ]]; then
    bind_jumplist
  fi
else
  remove_focus_hooks jumplist_record.sh @fuzzmux-jumplist-installed
  tmux set-option -gu @fuzzmux-prev-bind-jump-back 2>/dev/null || true
  tmux set-option -gu @fuzzmux-prev-bind-jump-forward 2>/dev/null || true
fi

# --- Claude Code "seen" tracking ---
# Focusing an agent's pane turns an unread finished turn ("waiting") into
# "idle". Tracks independently of the binding toggle, like the jumplist.
if [[ "$(get_tmux_option '@fuzzmux-claude-enabled' '1')" == "1" ]]; then
  install_focus_hooks claude_focus.sh @fuzzmux-claude-focus-installed
else
  remove_focus_hooks claude_focus.sh @fuzzmux-claude-focus-installed
fi

tmux display-message "fuzzmux.tmux: Plugin loaded successfully"
