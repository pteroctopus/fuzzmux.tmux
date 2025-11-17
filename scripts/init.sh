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

# Unbind previous keys
for key in session session-zoom pane pane-zoom window window-zoom nvim nvim-zoom; do
  prev_key=$(get_tmux_option "@fuzzmux-prev-bind-${key}" "")
  [[ -n "$prev_key" ]] && tmux unbind-key "$prev_key" 2>/dev/null || true
done

# Build popup arguments (shared by all features)
POPUP_ARGS=" --popup-width=$(get_tmux_option '@fuzzmux-popup-width' '90%')"
POPUP_ARGS+=" --popup-height=$(get_tmux_option '@fuzzmux-popup-height' '90%')"
POPUP_ARGS+=" --popup-border=$(get_tmux_option '@fuzzmux-popup-border-style' 'rounded')"
POPUP_ARGS+=" --popup-color=$(get_tmux_option '@fuzzmux-popup-border-color' 'cyan')"

declare -A FUZZMUX_DEFAULT_KEYS=(
  [session]=s
  [session-zoom]=S
  [pane]=p
  [pane-zoom]=P
  [window]=w
  [window-zoom]=W
  [nvim]=f
  [nvim-zoom]=F
)

# Bind keys for each enabled feature
bind_feature() {
  local feature=$1 script=$2 key_opt=$3 key_zoom_opt=$4

  [[ "$(get_tmux_option "@fuzzmux-${feature}-enabled" '1')" != "1" ]] && return

  local key_name="${feature}"      # e.g. "session"
  local default_key="${FUZZMUX_DEFAULT_KEYS[$key_name]}"
  local key="$(get_tmux_option "$key_opt" "$default_key")"

  local key_zoom_name="${feature}-zoom"
  local default_key_zoom="${FUZZMUX_DEFAULT_KEYS[$key_zoom_name]}"
  local key_zoom="$(get_tmux_option "$key_zoom_opt" "$default_key_zoom")"

  # guard: invalid/empty keys
  if [[ -z "$key" || -z "$key_zoom" ]]; then
    return
  fi

  # Build feature-specific arguments
  local args="${POPUP_ARGS}"
  [[ "$(get_tmux_option "@fuzzmux-${feature}-preview-enabled" '1')" == "1" ]] && args+=" --preview"
  [[ "$(get_tmux_option '@fuzzmux-colors-enabled' '1')" == "1" ]] && args+=" --colors"

  tmux bind-key "$key" run-shell "${PLUGIN_DIR}/bin/${script}${args}"
  tmux bind-key "$key_zoom" run-shell "${PLUGIN_DIR}/bin/${script}${args} --zoom"

  tmux set-option -g "@fuzzmux-prev-bind-${feature}" "$key"
  tmux set-option -g "@fuzzmux-prev-bind-${feature}-zoom" "$key_zoom"
}

if [[ "$(get_tmux_option '@fuzzmux-enable-bindings' '1')" == "1" ]]; then
  bind_feature session fzf_session_switcher.sh @fuzzmux-bind-session @fuzzmux-bind-session-zoom
  bind_feature pane fzf_pane_switcher.sh @fuzzmux-bind-pane @fuzzmux-bind-pane-zoom
  bind_feature window fzf_window_switcher.sh @fuzzmux-bind-window @fuzzmux-bind-window-zoom
  bind_feature nvim fzf_nvim_files.sh @fuzzmux-bind-nvim @fuzzmux-bind-nvim-zoom
fi

tmux display-message "fuzzmux.tmux: Plugin loaded successfully"
