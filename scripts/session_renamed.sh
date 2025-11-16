#!/usr/bin/env bash
new_session="$1"

# Get all open nvim sockets and send a command to them to refresh tmux environment variables
mapfile -t NVIM_SOCKETS < \
  <(tmux show-environment -g | grep FUZZMUX_NVIM_SOCKET_ | awk -F"'" '{print $2}')

for socket in "${NVIM_SOCKETS[@]}"; do
    nvim --clean --server \
      "$socket" \
      --remote-send \
      ":lua require('fuzzmux.tmux').refresh_vars()<cr>"
done

# log to file (or run any command)
# echo "$(date) Session renamed to $new_session" >> ~/.tmux-session-renames.log

# example of doing something asynchronously:
# (
#   sleep 1
#   echo "Async action for $new_session" >> ~/.tmux-session-renames.log
# ) &
