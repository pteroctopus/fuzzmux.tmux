#!/usr/bin/env bash
set -euo pipefail

# Compact status-line summary of the Claude Code agents running in tmux panes,
# meant for a `#()` in status-left/status-right:
#
#   set -g status-right '#(~/.tmux/plugins/fuzzmux.tmux/bin/claude_status.sh) %H:%M'
#
# Output, empty when no agent is running:
#   !2 *1 ~3    ->  2 need you (permission/question), 1 waiting, 3 working
#
# Options:
#   --no-colors        plain text (default wraps each group in a tmux style; also
#                      implied by @fuzzmux-colors-enabled '0')
#   --prefix=<text>    text placed before the summary (default: none)
#   --idle             also show idle agents as .N
#
# Styles come from the tmux options (tmux STYLES syntax, see claude_lib.sh):
#   @fuzzmux-claude-attention-style  default fg=red,bold
#   @fuzzmux-claude-waiting-style    default fg=yellow
#   @fuzzmux-claude-working-style    default fg=brightgreen
#   @fuzzmux-claude-idle-style       default dim

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=claude_lib.sh
source "$CURRENT_DIR/claude_lib.sh"

USE_COLORS=true
[[ "$(claude_option '@fuzzmux-colors-enabled' '1')" == "1" ]] || USE_COLORS=false
PREFIX=""
SHOW_IDLE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
  --no-colors) USE_COLORS=false ;;
  --prefix=*) PREFIX="${1#*=}" ;;
  --idle) SHOW_IDLE=true ;;
  esac
  shift
done

attention=0 waiting=0 working=0 idle=0
while IFS="$CLAUDE_DEL" read -r _pane state _rest; do
  case "$state" in
  permission | question) ((attention++)) || true ;;
  waiting) ((waiting++)) || true ;;
  working) ((working++)) || true ;;
  idle) ((idle++)) || true ;;
  esac
done < <(claude_agents_list)

part() {
  local style=$1 text=$2
  if [[ "$USE_COLORS" == "true" ]]; then
    printf '#[%s]%s#[default]' "$style" "$text"
  else
    printf '%s' "$text"
  fi
}

out=""
((attention > 0)) && out+="$(part "$(claude_state_style attention)" "!${attention}") "
((waiting > 0)) && out+="$(part "$(claude_state_style waiting)" "*${waiting}") "
((working > 0)) && out+="$(part "$(claude_state_style working)" "~${working}") "
[[ "$SHOW_IDLE" == "true" ]] && ((idle > 0)) && out+="$(part "$(claude_state_style idle)" ".${idle}") "

[[ -n "$out" ]] || exit 0
printf '%s%s\n' "$PREFIX" "${out% }"
