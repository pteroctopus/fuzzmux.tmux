#!/usr/bin/env bash
# fuzzmux.tmux - TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load plugin initializer
"$CURRENT_DIR/scripts/init.sh"

# Register custom tmux command
tmux set-option -su command-alias
tmux set-option -sa command-alias "fuzzmux-broadcast-nvim=command-prompt -p \"nvim:\" \"set -g @fuzzmux-nvim-broadcast '%%'; run-shell '$CURRENT_DIR/bin/nvim_broadcast.sh'\""

# Bind fuzzmux-broadcast-nvim command (default: prefix + b), honouring the master
# bindings toggle for consistency with the other features.
if [[ "$(tmux show-option -gqv '@fuzzmux-enable-bindings')" != "0" ]]; then
  broadcast_nvim_key="$(tmux show-option -gqv '@fuzzmux-bind-broadcast-nvim')"
  broadcast_nvim_key="${broadcast_nvim_key:-b}"
  # Handle '!' prefix marker for root table bindings
  if [[ "${broadcast_nvim_key}" == \!* ]]; then
    tmux bind-key -n "${broadcast_nvim_key:1}" fuzzmux-broadcast-nvim
  else
    tmux bind-key "$broadcast_nvim_key" fuzzmux-broadcast-nvim
  fi
fi
