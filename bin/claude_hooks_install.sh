#!/usr/bin/env bash
set -euo pipefail

# Install or remove the fuzzmux Claude Code hooks in a Claude Code settings file.
#
# Usage:
#   claude_hooks_install.sh [--settings <file>] [--dry-run]
#   claude_hooks_install.sh --uninstall [--settings <file>] [--dry-run]
#   claude_hooks_install.sh --print
#
# Default settings file: ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json (user
# scope). Pass --settings .claude/settings.json inside a project for project
# scope. Existing hooks are preserved; earlier fuzzmux entries are replaced, so
# re-running after a plugin update is safe. A backup is written next to the file.
#
# --print shows the hook fragment for manual editing and touches nothing.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$CURRENT_DIR/claude_hook.sh"
# Matched against existing commands to find our own entries (any plugin path).
MARKER="/bin/claude_hook.sh"

SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
UNINSTALL=false
DRY_RUN=false
PRINT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --settings=*) SETTINGS="${1#*=}" ;;
  --settings)
    shift
    SETTINGS="${1:-}"
    ;;
  --uninstall) UNINSTALL=true ;;
  --dry-run) DRY_RUN=true ;;
  --print) PRINT=true ;;
  -h | --help)
    sed -n '4,17p' "$0"
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required (https://jqlang.github.io/jq/)" >&2
  exit 1
fi
[[ -x "$HOOK_SCRIPT" ]] || {
  echo "Hook script not found or not executable: $HOOK_SCRIPT" >&2
  exit 1
}

# Quote the path so a plugin directory containing spaces still works.
HOOK_CMD="\"$HOOK_SCRIPT\""

# event, matcher ("" = every occurrence), argument passed to claude_hook.sh
ENTRIES='[
  {"event": "SessionStart",       "matcher": "",                  "arg": "session-start"},
  {"event": "UserPromptSubmit",   "matcher": "",                  "arg": "prompt"},
  {"event": "PermissionRequest",  "matcher": "",                  "arg": "permission"},
  {"event": "Notification",       "matcher": "permission_prompt", "arg": "notify-permission"},
  {"event": "Notification",       "matcher": "idle_prompt",       "arg": "notify-idle"},
  {"event": "PreToolUse",         "matcher": "AskUserQuestion",   "arg": "question"},
  {"event": "PostToolUse",        "matcher": "",                  "arg": "tool-done"},
  {"event": "PostToolUseFailure", "matcher": "",                  "arg": "tool-done"},
  {"event": "Stop",               "matcher": "",                  "arg": "stop"},
  {"event": "SessionEnd",         "matcher": "",                  "arg": "session-end"}
]'

# jq: drop our previous entries from every event we manage, then (unless
# uninstalling) append the current ones. Events left empty are removed.
JQ_PROGRAM='
def strip_ours:
  map(.hooks = ((.hooks // []) | map(select(((.command // "") | contains($marker)) | not))))
  | map(select((.hooks | length) > 0));
def group($e):
  (if $e.matcher == "" then {} else {matcher: $e.matcher} end)
  + {hooks: [{type: "command", command: ($cmd + " " + $e.arg), timeout: 5}]};
.hooks = ((.hooks // {})
  | reduce ($entries[] | .event) as $ev (.; .[$ev] = ((.[$ev] // []) | strip_ours))
  | reduce $entries[] as $e (.; if $uninstall then . else .[$e.event] += [group($e)] end)
  | reduce ($entries[] | .event) as $ev (.; if (.[$ev] | length) == 0 then del(.[$ev]) else . end))
'

if [[ "$PRINT" == "true" ]]; then
  jq -n --argjson entries "$ENTRIES" --arg cmd "$HOOK_CMD" --arg marker "$MARKER" --argjson uninstall false \
    '{} | '"$JQ_PROGRAM" | jq '{hooks}'
  exit 0
fi

if [[ -e "$SETTINGS" ]]; then
  if ! jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1; then
    echo "Not a JSON object, refusing to touch it: $SETTINGS" >&2
    exit 1
  fi
  CURRENT="$(cat "$SETTINGS")"
else
  if [[ "$UNINSTALL" == "true" ]]; then
    echo "Nothing to do, file does not exist: $SETTINGS"
    exit 0
  fi
  CURRENT='{}'
fi

NEW="$(printf '%s' "$CURRENT" | jq --argjson entries "$ENTRIES" --arg cmd "$HOOK_CMD" \
  --arg marker "$MARKER" --argjson uninstall "$UNINSTALL" "$JQ_PROGRAM")"

if [[ "$(printf '%s' "$CURRENT" | jq -S .)" == "$(printf '%s' "$NEW" | jq -S .)" ]]; then
  echo "No changes needed: $SETTINGS"
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run, would write $SETTINGS:"
  if command -v diff >/dev/null 2>&1; then
    diff -u <(printf '%s\n' "$CURRENT" | jq .) <(printf '%s\n' "$NEW") || true
  else
    printf '%s\n' "$NEW"
  fi
  exit 0
fi

mkdir -p "$(dirname "$SETTINGS")"
if [[ -e "$SETTINGS" ]]; then
  BACKUP="$SETTINGS.bak.fuzzmux.$(date +%Y%m%d%H%M%S)"
  cp -p "$SETTINGS" "$BACKUP"
  echo "Backup: $BACKUP"
fi
TMP="$(mktemp "$SETTINGS.tmp.XXXXXX")"
printf '%s\n' "$NEW" >"$TMP"
mv "$TMP" "$SETTINGS"

if [[ "$UNINSTALL" == "true" ]]; then
  echo "Removed fuzzmux Claude Code hooks from $SETTINGS"
else
  echo "Installed fuzzmux Claude Code hooks into $SETTINGS"
  echo "Hook: $HOOK_SCRIPT"
  echo "New Claude Code sessions pick this up immediately; check with /hooks inside Claude Code."
fi
