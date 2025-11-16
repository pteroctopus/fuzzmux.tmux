#!/usr/bin/env bash

declare -A COLORS
COLORS[reset]=$'\033[0m'
COLORS[red]=$'\033[31m'
COLORS[green]=$'\033[32m'
COLORS[yellow]=$'\033[33m'
COLORS[blue]=$'\033[34m'
COLORS[magenta]=$'\033[35m'
COLORS[cyan]=$'\033[36m'
COLOR_NAMES=(red green yellow blue magenta cyan)

pick_color() {
    local s="${1:-x}"
    local w="${2:-x}"
    
    # Simple hash: combine s and w and sum ASCII codes
    local combined="${s}${w}"
    local sum=0
    for ((i=0; i<${#combined}; i++)); do
        sum=$((sum + $(printf "%d" "'${combined:i:1}") ))
    done

    # Pick color deterministically
    local idx=$((sum % ${#COLOR_NAMES[@]}))
    local color_name="${COLOR_NAMES[$idx]}"

    # Return the actual ANSI escape sequence
    printf "%s" "${COLORS[$color_name]}"
}

