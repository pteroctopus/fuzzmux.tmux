#!/usr/bin/env bash

# Enhanced color script with custom palette support
# Usage:
#   source colors.sh                                 # Use default terminal colors
#   source colors.sh "#ff0000,#00ff00,#0000ff"       # Custom palette
#   FUZZMUX_COLORS="#ff0000,#00ff00" source colors.sh # Using environment variable

# ANSI reset sequence (exported for external use)
RESET=$'\033[0m'

# Convert hex color to ANSI 24-bit color escape sequence
hex_to_ansi() {
  local hex="$1"
  # Remove leading # if present
  hex="${hex#\#}"
  
  # Validate hex color format
  if [[ ! "$hex" =~ ^[0-9A-Fa-f]{6}$ ]]; then
    return 1
  fi
  
  # Convert to RGB
  local r=$((16#${hex:0:2}))
  local g=$((16#${hex:2:2}))
  local b=$((16#${hex:4:2}))
  
  # Return ANSI 24-bit color sequence with zero-padded values for consistent width
  printf '\033[38;2;%03d;%03d;%03dm' "$r" "$g" "$b"
}

# Default terminal color palette (uses terminal's color scheme)
DEFAULT_TERMINAL_COLORS=(
  $'\033[31m'   # red
  $'\033[32m'   # green
  $'\033[33m'   # yellow
  $'\033[34m'   # blue
  $'\033[35m'   # magenta
  $'\033[36m'   # cyan
)

# Build color array
COLORS=()

# Use FUZZMUX_COLORS environment variable or function argument
_fuzzmux_palette="${FUZZMUX_COLORS:-${1:-}}"

if [[ -n "$_fuzzmux_palette" ]]; then
  # Custom palette provided in HTML color codes
  IFS=',' read -ra PALETTE <<< "$_fuzzmux_palette"
  
  # Build ANSI color array from palette
  for hex_color in "${PALETTE[@]}"; do
    _color_code=""
    if _color_code=$(hex_to_ansi "$hex_color"); then
      COLORS+=("$_color_code")
    fi
  done
  unset _color_code
else
  # Use default terminal colors
  COLORS=("${DEFAULT_TERMINAL_COLORS[@]}")
fi

# Fallback to terminal colors if no valid colors
if [[ ${#COLORS[@]} -eq 0 ]]; then
  COLORS=("${DEFAULT_TERMINAL_COLORS[@]}")
fi

# Cleanup temporary variables
unset _fuzzmux_palette

# Pick a color deterministically based on input string(s)
# Usage: pick_color "string1" ["string2" ...]
pick_color() {
  local combined=""
  for arg in "$@"; do
    combined+="$arg"
  done
  
  # Simple hash: sum ASCII codes
  local sum=0
  for ((i = 0; i < ${#combined}; i++)); do
    sum=$((sum + $(printf "%d" "'${combined:i:1}")))
  done
  
  # Pick color deterministically
  local idx=$((sum % ${#COLORS[@]}))
  printf "%s" "${COLORS[$idx]}"
}
