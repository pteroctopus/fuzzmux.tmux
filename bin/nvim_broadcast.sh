#!/usr/bin/env bash

CMD=$(tmux show-option -gv @fuzzmux-nvim-broadcast)

[[ -z "$CMD" ]] && exit 0

declare -a NVIM_SOCKETS=()

# Retrieve nvim socket paths from tmux environment variables
while IFS='=' read -r var_name value; do
  # Remove quotes
  value=${value#\'}
  value=${value%\'}
  NVIM_SOCKETS+=("$value")
done < <(tmux show-environment -g 2>/dev/null | grep "^FUZZMUX_NVIM_SOCKET_")

# Send command to each nvim socket
for socket in "${NVIM_SOCKETS[@]}"; do
  if [[ -S "$socket" ]]; then
    nvim --headless --clean --server "$socket" --remote-send "<C-\\><C-N>:${CMD}<CR>"
  fi
done

tmux set-option -gu @fuzzmux-nvim-broadcast
tmux display-message -ld 1500 "Neovim broadcast finished"
