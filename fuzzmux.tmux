#!/usr/bin/env bash
# fuzzmux.tmux - TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load plugin initializer
"$CURRENT_DIR/scripts/init.sh"

# Register custom tmux command
tmux set-option -su command-alias
tmux set-option -sa command-alias "fuzzmux-broadcast-nvim=command-prompt -p \"nvim:\" \"set -g @fuzzmux-nvim-broadcast '%%'; run-shell '$CURRENT_DIR/bin/nvim_broadcast.sh'\""
