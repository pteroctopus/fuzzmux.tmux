#!/usr/bin/env bash
# fuzzmux.tmux - TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux_option_or_fallback() {
    local option_value
    option_value="$(tmux show-option -gqv "$1")"
    if [ -z "$option_value" ]; then
        echo "$2"
    else
        echo "$option_value"
    fi
}

# Set plugin defaults if not already set
tmux set-option -gq @fuzzmux-enabled "$(tmux_option_or_fallback @fuzzmux-enabled 1)"
tmux set-option -gq @fuzzmux-default-bindings "$(tmux_option_or_fallback @fuzzmux-default-bindings 1)"
tmux set-option -gq @fuzzmux-preview-enabled "$(tmux_option_or_fallback @fuzzmux-preview-enabled 1)"
tmux set-option -gq @fuzzmux-colors-enabled "$(tmux_option_or_fallback @fuzzmux-colors-enabled 1)"

# Feature toggles
tmux set-option -gq @fuzzmux-session-enabled "$(tmux_option_or_fallback @fuzzmux-session-enabled 1)"
tmux set-option -gq @fuzzmux-pane-enabled "$(tmux_option_or_fallback @fuzzmux-pane-enabled 1)"
tmux set-option -gq @fuzzmux-window-enabled "$(tmux_option_or_fallback @fuzzmux-window-enabled 1)"
tmux set-option -gq @fuzzmux-nvim-enabled "$(tmux_option_or_fallback @fuzzmux-nvim-enabled 1)"

# Popup appearance defaults
tmux set-option -gq @fuzzmux-popup-width "$(tmux_option_or_fallback @fuzzmux-popup-width '90%')"
tmux set-option -gq @fuzzmux-popup-height "$(tmux_option_or_fallback @fuzzmux-popup-height '90%')"
tmux set-option -gq @fuzzmux-popup-border-style "$(tmux_option_or_fallback @fuzzmux-popup-border-style 'rounded')"
tmux set-option -gq @fuzzmux-popup-border-color "$(tmux_option_or_fallback @fuzzmux-popup-border-color 'green')"

# Initialize hooks
# tmux set-hook -g session-renamed "run-shell '$CURRENT_DIR/scripts/session_renamed.sh #{session_name}'"

# Load plugin initializer
"$CURRENT_DIR/scripts/init.sh"
