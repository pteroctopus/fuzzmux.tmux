#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$CURRENT_DIR")"

# Get tmux option value
get_tmux_option() {
  local option="$1"
  local default="$2"
  local value
  value=$(tmux show-option -gqv "$option")
  if [[ -z "$value" ]]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# Display error message in tmux
tmux_error() {
  tmux display-message "fuzzmux.tmux: ERROR - $1"
}

# Display warning message in tmux
tmux_warning() {
  tmux display-message "fuzzmux.tmux: WARNING - $1"
}

# Display info message in tmux
tmux_info() {
  tmux display-message "fuzzmux.tmux: $1"
}

# Check if we're running inside tmux
if [[ -z "${TMUX:-}" ]]; then
  echo "fuzzmux.tmux: Must be run from inside tmux"
  exit 1
fi

# Check if plugin is enabled
ENABLED=$(get_tmux_option "@fuzzmux-enabled" "1")
if [[ "$ENABLED" != "1" ]]; then
  # Plugin is disabled - unbind all previous keys
  PREV_SESSION_KEY=$(get_tmux_option "@fuzzmux-prev-bind-session" "")
  PREV_SESSION_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-session-zoom" "")
  PREV_PANE_KEY=$(get_tmux_option "@fuzzmux-prev-bind-pane" "")
  PREV_PANE_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-pane-zoom" "")
  PREV_WINDOW_KEY=$(get_tmux_option "@fuzzmux-prev-bind-window" "")
  PREV_WINDOW_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-window-zoom" "")
  PREV_NVIM_KEY=$(get_tmux_option "@fuzzmux-prev-bind-nvim" "")
  PREV_NVIM_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-nvim-zoom" "")

  [[ -n "$PREV_SESSION_KEY" ]] && tmux unbind-key "$PREV_SESSION_KEY" 2>/dev/null || true
  [[ -n "$PREV_SESSION_KEY_ZOOM" ]] && tmux unbind-key "$PREV_SESSION_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_PANE_KEY" ]] && tmux unbind-key "$PREV_PANE_KEY" 2>/dev/null || true
  [[ -n "$PREV_PANE_KEY_ZOOM" ]] && tmux unbind-key "$PREV_PANE_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_WINDOW_KEY" ]] && tmux unbind-key "$PREV_WINDOW_KEY" 2>/dev/null || true
  [[ -n "$PREV_WINDOW_KEY_ZOOM" ]] && tmux unbind-key "$PREV_WINDOW_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_NVIM_KEY" ]] && tmux unbind-key "$PREV_NVIM_KEY" 2>/dev/null || true
  [[ -n "$PREV_NVIM_KEY_ZOOM" ]] && tmux unbind-key "$PREV_NVIM_KEY_ZOOM" 2>/dev/null || true

  tmux_info "Plugin disabled - keybindings removed"
  exit 0
fi

# Check tmux version
TMUX_VERSION=$(tmux -V | cut -d' ' -f2)
REQUIRED_VERSION="3.2"

version_compare() {
  if [[ "$1" == "$2" ]]; then
    return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  for ((i = 0; i < ${#ver1[@]}; i++)); do
    if [[ -z ${ver2[i]:-} ]]; then
      return 0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      return 0
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      return 1
    fi
  done
  return 0
}

if ! version_compare "$TMUX_VERSION" "$REQUIRED_VERSION"; then
  tmux_error "tmux version $REQUIRED_VERSION or higher required (current: $TMUX_VERSION)"
  exit 1
fi

# Check if fzf is installed
if ! command -v fzf >/dev/null 2>&1; then
  tmux_error "fzf is not installed. Please install fzf: https://github.com/junegunn/fzf"
  exit 1
fi

# Check optional dependencies and warn if missing
if ! command -v bat >/dev/null 2>&1; then
  tmux_warning "bat not found. Install for better file previews: https://github.com/sharkdp/bat"
fi

if ! command -v column >/dev/null 2>&1; then
  tmux_warning "column command not found. Output formatting may be affected"
fi

# Setup key bindings if enabled
DEFAULT_BINDINGS=$(get_tmux_option "@fuzzmux-default-bindings" "1")
if [[ "$DEFAULT_BINDINGS" != "1" ]]; then
  # Default bindings disabled - unbind all previous keys
  PREV_SESSION_KEY=$(get_tmux_option "@fuzzmux-prev-bind-session" "")
  PREV_SESSION_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-session-zoom" "")
  PREV_PANE_KEY=$(get_tmux_option "@fuzzmux-prev-bind-pane" "")
  PREV_PANE_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-pane-zoom" "")
  PREV_WINDOW_KEY=$(get_tmux_option "@fuzzmux-prev-bind-window" "")
  PREV_WINDOW_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-window-zoom" "")
  PREV_NVIM_KEY=$(get_tmux_option "@fuzzmux-prev-bind-nvim" "")
  PREV_NVIM_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-nvim-zoom" "")

  [[ -n "$PREV_SESSION_KEY" ]] && tmux unbind-key "$PREV_SESSION_KEY" 2>/dev/null || true
  [[ -n "$PREV_SESSION_KEY_ZOOM" ]] && tmux unbind-key "$PREV_SESSION_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_PANE_KEY" ]] && tmux unbind-key "$PREV_PANE_KEY" 2>/dev/null || true
  [[ -n "$PREV_PANE_KEY_ZOOM" ]] && tmux unbind-key "$PREV_PANE_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_WINDOW_KEY" ]] && tmux unbind-key "$PREV_WINDOW_KEY" 2>/dev/null || true
  [[ -n "$PREV_WINDOW_KEY_ZOOM" ]] && tmux unbind-key "$PREV_WINDOW_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_NVIM_KEY" ]] && tmux unbind-key "$PREV_NVIM_KEY" 2>/dev/null || true
  [[ -n "$PREV_NVIM_KEY_ZOOM" ]] && tmux unbind-key "$PREV_NVIM_KEY_ZOOM" 2>/dev/null || true

  tmux_info "Default bindings disabled - set up custom bindings in your tmux.conf"
elif [[ "$DEFAULT_BINDINGS" == "1" ]]; then
  # Check which features are enabled
  SESSION_ENABLED=$(get_tmux_option "@fuzzmux-session-enabled" "1")
  PANE_ENABLED=$(get_tmux_option "@fuzzmux-pane-enabled" "1")
  WINDOW_ENABLED=$(get_tmux_option "@fuzzmux-window-enabled" "1")
  NVIM_ENABLED=$(get_tmux_option "@fuzzmux-nvim-enabled" "1")

  # Get previous keybindings (if they exist) and unbind them
  PREV_SESSION_KEY=$(get_tmux_option "@fuzzmux-prev-bind-session" "")
  PREV_SESSION_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-session-zoom" "")
  PREV_PANE_KEY=$(get_tmux_option "@fuzzmux-prev-bind-pane" "")
  PREV_PANE_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-pane-zoom" "")
  PREV_WINDOW_KEY=$(get_tmux_option "@fuzzmux-prev-bind-window" "")
  PREV_WINDOW_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-window-zoom" "")
  PREV_NVIM_KEY=$(get_tmux_option "@fuzzmux-prev-bind-nvim" "")
  PREV_NVIM_KEY_ZOOM=$(get_tmux_option "@fuzzmux-prev-bind-nvim-zoom" "")

  # Unbind previous keys if they exist
  [[ -n "$PREV_SESSION_KEY" ]] && tmux unbind-key "$PREV_SESSION_KEY" 2>/dev/null || true
  [[ -n "$PREV_SESSION_KEY_ZOOM" ]] && tmux unbind-key "$PREV_SESSION_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_PANE_KEY" ]] && tmux unbind-key "$PREV_PANE_KEY" 2>/dev/null || true
  [[ -n "$PREV_PANE_KEY_ZOOM" ]] && tmux unbind-key "$PREV_PANE_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_WINDOW_KEY" ]] && tmux unbind-key "$PREV_WINDOW_KEY" 2>/dev/null || true
  [[ -n "$PREV_WINDOW_KEY_ZOOM" ]] && tmux unbind-key "$PREV_WINDOW_KEY_ZOOM" 2>/dev/null || true
  [[ -n "$PREV_NVIM_KEY" ]] && tmux unbind-key "$PREV_NVIM_KEY" 2>/dev/null || true
  [[ -n "$PREV_NVIM_KEY_ZOOM" ]] && tmux unbind-key "$PREV_NVIM_KEY_ZOOM" 2>/dev/null || true

  # Get user-defined bindings or use defaults (lowercase for normal, uppercase for zoom)
  SESSION_KEY=$(get_tmux_option "@fuzzmux-bind-session" "s")
  SESSION_KEY_ZOOM=$(get_tmux_option "@fuzzmux-bind-session-zoom" "S")
  PANE_KEY=$(get_tmux_option "@fuzzmux-bind-pane" "p")
  PANE_KEY_ZOOM=$(get_tmux_option "@fuzzmux-bind-pane-zoom" "P")
  WINDOW_KEY=$(get_tmux_option "@fuzzmux-bind-window" "w")
  WINDOW_KEY_ZOOM=$(get_tmux_option "@fuzzmux-bind-window-zoom" "W")
  NVIM_KEY=$(get_tmux_option "@fuzzmux-bind-nvim" "f")
  NVIM_KEY_ZOOM=$(get_tmux_option "@fuzzmux-bind-nvim-zoom" "F")

  # Store current keybindings as previous for next reload
  tmux set-option -g @fuzzmux-prev-bind-session "$SESSION_KEY"
  tmux set-option -g @fuzzmux-prev-bind-session-zoom "$SESSION_KEY_ZOOM"
  tmux set-option -g @fuzzmux-prev-bind-pane "$PANE_KEY"
  tmux set-option -g @fuzzmux-prev-bind-pane-zoom "$PANE_KEY_ZOOM"
  tmux set-option -g @fuzzmux-prev-bind-window "$WINDOW_KEY"
  tmux set-option -g @fuzzmux-prev-bind-window-zoom "$WINDOW_KEY_ZOOM"
  tmux set-option -g @fuzzmux-prev-bind-nvim "$NVIM_KEY"
  tmux set-option -g @fuzzmux-prev-bind-nvim-zoom "$NVIM_KEY_ZOOM"

  # Get options
  PREVIEW_ENABLED=$(get_tmux_option "@fuzzmux-preview-enabled" "1")
  COLORS_ENABLED=$(get_tmux_option "@fuzzmux-colors-enabled" "1")

  # Get popup appearance settings
  POPUP_WIDTH=$(get_tmux_option "@fuzzmux-popup-width" "90%")
  POPUP_HEIGHT=$(get_tmux_option "@fuzzmux-popup-height" "90%")
  POPUP_BORDER_STYLE=$(get_tmux_option "@fuzzmux-popup-border-style" "rounded")
  POPUP_BORDER_COLOR=$(get_tmux_option "@fuzzmux-popup-border-color" "green")

  # Build command arguments (without zoom)
  SESSION_ARGS=""
  PANE_ARGS=""
  WINDOW_ARGS=""
  NVIM_ARGS=""

  [[ "$PREVIEW_ENABLED" == "1" ]] && {
    SESSION_ARGS+=" --preview"
    PANE_ARGS+=" --preview"
    WINDOW_ARGS+=" --preview"
    NVIM_ARGS+=" --preview"
  }

  [[ "$COLORS_ENABLED" == "1" ]] && {
    SESSION_ARGS+=" --colors"
    PANE_ARGS+=" --colors"
    WINDOW_ARGS+=" --colors"
    NVIM_ARGS+=" --colors"
  }

  # Add popup settings to all
  POPUP_ARGS=" --popup-width=${POPUP_WIDTH} --popup-height=${POPUP_HEIGHT} --popup-border=${POPUP_BORDER_STYLE} --popup-color=${POPUP_BORDER_COLOR}"
  SESSION_ARGS+="${POPUP_ARGS}"
  PANE_ARGS+="${POPUP_ARGS}"
  WINDOW_ARGS+="${POPUP_ARGS}"
  NVIM_ARGS+="${POPUP_ARGS}"

  # Build command arguments with zoom
  SESSION_ARGS_ZOOM="${SESSION_ARGS} --zoom"
  PANE_ARGS_ZOOM="${PANE_ARGS} --zoom"
  WINDOW_ARGS_ZOOM="${WINDOW_ARGS} --zoom"
  NVIM_ARGS_ZOOM="${NVIM_ARGS} --zoom"

  # Set up key bindings (using prefix key) based on enabled features
  # Unbind first to ensure disabled features don't keep old bindings
  if [[ "$SESSION_ENABLED" == "1" ]]; then
    tmux bind-key "$SESSION_KEY" run-shell "${PLUGIN_DIR}/bin/fzf_session_switcher.sh${SESSION_ARGS}"
    tmux bind-key "$SESSION_KEY_ZOOM" run-shell "${PLUGIN_DIR}/bin/fzf_session_switcher.sh${SESSION_ARGS_ZOOM}"
  else
    tmux unbind-key "$SESSION_KEY" 2>/dev/null || true
    tmux unbind-key "$SESSION_KEY_ZOOM" 2>/dev/null || true
  fi

  if [[ "$PANE_ENABLED" == "1" ]]; then
    tmux bind-key "$PANE_KEY" run-shell "${PLUGIN_DIR}/bin/fzf_pane_switcher.sh${PANE_ARGS}"
    tmux bind-key "$PANE_KEY_ZOOM" run-shell "${PLUGIN_DIR}/bin/fzf_pane_switcher.sh${PANE_ARGS_ZOOM}"
  else
    tmux unbind-key "$PANE_KEY" 2>/dev/null || true
    tmux unbind-key "$PANE_KEY_ZOOM" 2>/dev/null || true
  fi

  if [[ "$WINDOW_ENABLED" == "1" ]]; then
    tmux bind-key "$WINDOW_KEY" run-shell "${PLUGIN_DIR}/bin/fzf_window_switcher.sh${WINDOW_ARGS}"
    tmux bind-key "$WINDOW_KEY_ZOOM" run-shell "${PLUGIN_DIR}/bin/fzf_window_switcher.sh${WINDOW_ARGS_ZOOM}"
  else
    tmux unbind-key "$WINDOW_KEY" 2>/dev/null || true
    tmux unbind-key "$WINDOW_KEY_ZOOM" 2>/dev/null || true
  fi

  if [[ "$NVIM_ENABLED" == "1" ]]; then
    tmux bind-key "$NVIM_KEY" run-shell "${PLUGIN_DIR}/bin/fzf_nvim_files.sh${NVIM_ARGS}"
    tmux bind-key "$NVIM_KEY_ZOOM" run-shell "${PLUGIN_DIR}/bin/fzf_nvim_files.sh${NVIM_ARGS_ZOOM}"
  else
    tmux unbind-key "$NVIM_KEY" 2>/dev/null || true
    tmux unbind-key "$NVIM_KEY_ZOOM" 2>/dev/null || true
  fi
fi

tmux_info "Plugin loaded successfully"
