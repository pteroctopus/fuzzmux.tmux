#!/usr/bin/env bash
# fuzzmux.tmux - TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load plugin initializer
"$CURRENT_DIR/scripts/init.sh"
