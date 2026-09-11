# fuzzmux.tmux

Created to solve the problem of quickly navigating between tmux panes, windows, Neovim buffers and Claude Code agents using fuzzy finding.

A tmux plugin that provides fuzzy-finding capabilities for tmux panes, windows, Neovim buffers and [Claude Code](https://code.claude.com) agents using [fzf](https://github.com/junegunn/fzf).
Works with [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) to track and switch between Neovim buffers across tmux panes.

## Features

- **Fuzzy find tmux sessions** - Quickly switch between sessions with attached session markers
- **Fuzzy find tmux panes** - Quickly switch between panes across all sessions with active pane markers
- **Fuzzy find tmux windows** - Jump to any window with ease with active window markers
- **Fuzzy find Neovim buffers** - Switch to Neovim buffers across different panes **(requires [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim))**
- **Broadcast Neovim commands** - Send commands to all active Neovim instances across tmux panes **(requires [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim))**
- **Pane jumplist** - Browser/Vim-style back/forward navigation through your focused-pane history (global across all sessions)
- **Fuzzy find Claude Code agents** - Switch between [Claude Code](https://code.claude.com) instances running in any pane of any session, most urgent first (permission prompt, question, finished turn, working)
- **Claude Code notifications** - Optional Claude Code hooks show a tmux status-line message the moment an agent needs your input, optionally a desktop notification that jumps to the pane when clicked, plus a status-line summary snippet
- **Progressive filtering** - Use a single key (default `ctrl-f`) to progressively filter results by session, window, or pane
- **Active/attached markers** - Visual `*` indicator in the first column showing attached sessions, active windows, and active panes
- **Colorized output** - Color-coded session/window identifiers for better visibility
- **Live previews** - Preview pane/window content or file contents before switching
- **Zoom support** - Optionally zoom into selected pane/window
- **Optimized performance** - Fast execution using pure bash string operations and batch data fetching
- **Configurable** - Customize keybindings and behavior
- **Feature toggles** - Enable/disable individual features as needed

https://github.com/user-attachments/assets/593dd544-7c35-41aa-b9ff-09fdce9b9b81

## Requirements

- **tmux** (required)
- **fzf** (required) - [Installation instructions](https://github.com/junegunn/fzf#installation)
- **bat** (optional) - For enhanced file previews in Neovim buffer switcher
- **column** (required) - For better formatting of lists
- **jq** (optional) - For Claude Code agent detection and the hook installer
- **terminal-notifier** (optional, macOS) - For Claude Code desktop notifications that jump to the pane when clicked (`brew install terminal-notifier`)
- **notify-send** (optional, Linux) - For Claude Code desktop notifications, without a click action (`libnotify-bin` on Debian/Ubuntu, `libnotify` on Arch and Fedora)
- **fuzzmux.nvim** (optional but HIGHLY recommended) - Required for Neovim buffer tracking functionality
- **Claude Code** (optional) - A 2.1.x release that writes `~/.claude/sessions/<pid>.json` state files (the same data `claude agents --json` shows); required only for the Claude Code agent switcher

## Installation

### Using [TPM](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager)

Add this to your `~/.tmux.conf`:

```tmux
set -g @plugin 'pteroctopus/fuzzmux.tmux'
```

Then press `prefix` + <kbd>I</kbd> to install.

### Manual Installation

```bash
git clone https://github.com/pteroctopus/fuzzmux.tmux ~/.tmux/plugins/fuzzmux.tmux
```

Add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/fuzzmux.tmux/fuzzmux.tmux
```

Reload tmux config:

```bash
tmux source-file ~/.tmux.conf
```

### Optional: Claude Code integration

The Claude Code agent switcher works right after installation (it needs `jq`).
If you also want to be notified when an agent needs you, and the finer states
(`permission`, `question`, unread vs. seen), register the plugin's Claude Code
hooks once:

```bash
~/.tmux/plugins/fuzzmux.tmux/bin/claude_hooks_install.sh
```

It merges a few command hooks into `~/.claude/settings.json`, keeps a backup and
leaves your other hooks alone; `--dry-run` shows the change first and
`--uninstall` removes it. Details in [Claude Code Agents](#claude-code-agents).

## Default Key Bindings

With default settings, the following keybindings are available (after pressing your tmux prefix key):

**Normal (without zoom):**
- `prefix` + <kbd>s</kbd> - Fuzzy find and switch to a session
- `prefix` + <kbd>p</kbd> - Fuzzy find and switch to a pane
- `prefix` + <kbd>w</kbd> - Fuzzy find and switch to a window
- `prefix` + <kbd>f</kbd> - Fuzzy find and switch to a Neovim buffer (needs fuzzmax.nvim plugin)
- `prefix` + <kbd>a</kbd> - Fuzzy find and switch to a Claude Code agent
- `prefix` + <kbd>y</kbd> - Search all Claude Code sessions ever run and switch to or resume one

**With zoom (uppercase keys):**
- `prefix` + <kbd>S</kbd> - Fuzzy find and switch to a session (with zoom)
- `prefix` + <kbd>P</kbd> - Fuzzy find and switch to a pane (with zoom)
- `prefix` + <kbd>W</kbd> - Fuzzy find and switch to a window (with zoom)
- `prefix` + <kbd>F</kbd> - Fuzzy find and switch to a Neovim buffer (with zoom) (needs fuzzmax.nvim plugin)
- `prefix` + <kbd>A</kbd> - Fuzzy find and switch to a Claude Code agent (with zoom)
- `prefix` + <kbd>Y</kbd> - Search all Claude Code sessions and switch to or resume one (with zoom)

**Pane jumplist (back/forward):**
- `prefix` + <kbd>Ctrl-h</kbd> - Jump **back** to the previously focused pane
- `prefix` + <kbd>Ctrl-l</kbd> - Jump **forward** again

**Neovim broadcast:**
- `prefix` + <kbd>b</kbd> - Broadcast a Neovim command to all tracked instances (needs fuzzmux.nvim)

## Pane Jumplist

Navigate the history of focused panes like a browser's back/forward buttons (or
Vim's jumplist). Every time the active pane changes - by any means (clicking,
switching windows/sessions, or fuzzmux's own switchers) - it is recorded in a
single **global** history shared across all sessions, windows, and panes.

- `prefix` + <kbd>Ctrl-h</kbd> walks **back** toward older panes; `prefix` +
  <kbd>Ctrl-l</kbd> walks **forward** again (mnemonic: Vim's `h`/`l`).
- Focusing a *new* pane after going back discards the forward history, exactly
  like navigating somewhere new in a browser.
- Panes closed since being recorded are skipped and pruned automatically.
- History is capped (default 100 entries) and kept in a per-server file under
  `$XDG_RUNTIME_DIR`/`$TMPDIR` that is discarded when the tmux server exits.

The bindings sit behind your tmux prefix, so they never interfere with Neovim's
own `Ctrl-h`/`Ctrl-l` window navigation.

## Claude Code Agents

Press `prefix` + <kbd>a</kbd> to list every [Claude Code](https://code.claude.com)
instance running in a tmux pane, across all sessions, most urgent first:

```
  permission (Bash)  2m   @api   #1  %2  manual  Fix flaky integration test  ~/Development/api
  question           40s  @docs  #0  %1  auto    Rewrite quick start         ~/Development/docs
+ waiting            14m  @app   #2  %1  plan    Rotate the staging certs    ~/Development/app
* working            5s   @app   #2  %0  edits   Refactor auth middleware    ~/Development/app
```

Columns: marker, state, time spent in that state, session, window, pane,
Claude's permission mode, the agent's title (Claude Code's own pane title) and
its working directory. The marker is `*` for the pane you opened the popup
from and `+` for another pane of the same window, so you can tell an agent that
is already on your screen from one that needs a switch; rows in your current
session show the session name in bold. Press <kbd>Enter</kbd> to switch to the
agent.

The mode column shows how much the agent may do on its own: `manual` (Claude's
`default`, asks for every tool), `edits` (`acceptEdits`), `plan`, `auto`,
`dontask` and `bypass` (`bypassPermissions`). It comes from the hook payloads,
follows mode switches (<kbd>Shift-Tab</kbd>) at the agent's next event, and
shows `-` for agents without hook data.

With preview enabled, the preview shows the bottom of the agent's pane, where
Claude's output and prompt live.

States, in the order they are listed:

| State        | Meaning                                                        |
|--------------|----------------------------------------------------------------|
| `permission` | A tool call waits for your approval (tool name in parentheses) |
| `question`   | Claude asked you a question                                    |
| `waiting`    | Claude finished a turn that you have not looked at yet         |
| `working`    | Claude is busy                                                 |
| `background` | The turn is over but a background shell, monitor or agent is still running (kind in parentheses); Claude wakes up by itself when it finishes, nothing is expected from you |
| `idle`       | At the prompt with nothing unread: fresh or resumed session, or a finished turn you already looked at |

`waiting` clears itself the moment you focus the agent's pane, by whatever
means (this switcher, the pane switcher, a click, a window change): the plugin
installs tmux focus hooks for that, the same way the pane jumplist does. A turn
that finishes while you are looking at its pane goes straight to `idle`.
`permission` and `question` stay until you answer, whether you looked or not.
So `waiting` in the picker, the `Ctrl-f` filter and the `*N` status count all
mean "finished something you have not seen".

**Searching:** This switcher uses fzf's exact (substring) matching, so typing
`waiting` lists exactly the waiting agents and `cop` the ones whose session,
title or path contains it. Prefix a term with `'` for fuzzy matching. Session
names, window and pane numbers, titles and paths are all searchable; the hidden
pane id is not.

**Filtering:** Press <kbd>Ctrl-f</kbd> (default) to show only the agents that
need you (`permission`, `question`, `waiting`); press again to show all.

**Colors:** The state column and the status-line summary share four tmux
styles, using your terminal's named colors by default. Override them with tmux
`STYLES` syntax (names, `brightgreen`, `colour208`, `#rrggbb`, `bold`, `dim`,
`reverse`, ...):

```tmux
set -g @fuzzmux-claude-attention-style 'fg=red,bold'   # permission, question
set -g @fuzzmux-claude-waiting-style 'fg=yellow'       # finished turn
set -g @fuzzmux-claude-working-style 'fg=brightgreen'  # busy
set -g @fuzzmux-claude-background-style 'fg=cyan'      # background work running
set -g @fuzzmux-claude-idle-style 'dim'                # fresh session

# Rose Pine example
set -g @fuzzmux-claude-attention-style 'fg=#eb6f92,bold'
set -g @fuzzmux-claude-waiting-style 'fg=#f6c177'
set -g @fuzzmux-claude-working-style 'fg=#9ccfd8'
```

The session/window/pane columns keep following `@fuzzmux-color-palette` like the
other switchers, and `@fuzzmux-colors-enabled '0'` turns everything plain.

### How agents are detected

No setup is needed for the switcher. Claude Code writes a state file for every
running instance (`~/.claude/sessions/<pid>.json`, honouring
`$CLAUDE_CONFIG_DIR`) that records the tmux pane it runs in and whether it is
busy, idle, waiting for you, or still running background work; fuzzmux reads
those files with `jq` and drops entries whose process or pane is gone. Without
the hooks below, agents show as `working`, `idle`, `permission` (Claude's
"waiting" status, which does not say whether a tool or a question is pending)
or `background`: Claude Code alone cannot name the tool that waits for
approval, nor tell an unread finished turn from one you already looked at.
`background` comes only from the state file, since no hook fires for
background shells, monitors or agents.

The optional hooks refine this: they record the exact state as pane user options
(`@fuzzmux-claude-state`, `@fuzzmux-claude-since`, `@fuzzmux-claude-detail`,
`@fuzzmux-claude-mode`) the moment an event happens. When both sources exist, the hook state wins whenever
the two agree on busy/idle; otherwise the more recent source wins, which covers
an interrupted turn (<kbd>Esc</kbd> fires no `Stop` hook) and a permission
prompt (still "busy" in the state file).

### Notifications when an agent needs you

Claude Code hooks are the only event-driven signal available, so notifications
need a small piece of Claude Code configuration. Install it with:

```bash
~/.tmux/plugins/fuzzmux.tmux/bin/claude_hooks_install.sh
```

The installer merges command hooks into `~/.claude/settings.json` (a backup is
written next to it; existing hooks are preserved and earlier fuzzmux entries are
replaced, so re-running after a plugin update or move is safe). It registers
`bin/claude_hook.sh` for `SessionStart`, `UserPromptSubmit`, `PermissionRequest`,
`Notification` (`permission_prompt`, `idle_prompt`), `PreToolUse`
(`AskUserQuestion`), `PostToolUse`, `PostToolUseFailure`, `Stop` and
`SessionEnd`. New Claude Code sessions pick the hooks up immediately; sessions
started earlier are tracked from their next event. Verify inside Claude Code
with `/hooks`.

Whenever an agent enters `permission`, `question` or `waiting`, every attached
client shows a message in its status line for a few seconds, for example:

```
Claude needs permission for Bash: @api #1.%2 (Fix flaky integration test)
```

The message is skipped when you are already looking at that pane, meaning it is
the active pane of the window in front of you *and* your terminal window has the
OS focus. tmux learns the latter from the terminal's focus events, so after
<kbd>Alt-Tab</kbd> to another application the same pane counts as unwatched and
the notification is sent; coming back marks the agent as seen. Terminals that do
not report focus (macOS Terminal.app, for one) never look focused to tmux; set
`@fuzzmux-claude-focus-check 'pane'` there to fall back to "active pane of an
attached client". Options:

```tmux
set -g @fuzzmux-claude-notify '0'            # no messages (state tracking stays on)
set -g @fuzzmux-claude-notify-focused '1'    # also notify for the pane you are viewing
set -g @fuzzmux-claude-focus-check 'pane'    # ignore terminal focus (see above)
set -g @fuzzmux-claude-notify-delay '2'      # seconds between a finished turn and its
                                             # notification (see below)
set -g @fuzzmux-claude-notify-duration '8000' # milliseconds (default 5000)
set -g @fuzzmux-claude-notify-bell '1'       # also ring the pane's bell (see below)
```

The bell goes through tmux's normal alert path, so it follows tmux's scope: with
`monitor-bell on` the agent's window is highlighted in the window list of *its*
session, and the terminal bell reaches clients attached to *that* session
(`bell-action`). An agent finishing in another session rings nothing where you
are; the status-line count below covers that case.

**Desktop notifications** reach you when the terminal is not in front:

```tmux
set -g @fuzzmux-claude-notify-desktop '1'
# set -g @fuzzmux-claude-notify-desktop-app 'com.mitchellh.ghostty'  # app to bring forward on click
```

On macOS with [terminal-notifier](https://github.com/julienXX/terminal-notifier)
installed, each notification carries the agent's location and title, replaces the
previous one for the same agent, and a click brings your terminal to the front
and switches tmux to that pane (`bin/claude_goto.sh`), which also marks the agent
as seen. The terminal to activate is detected from the tmux server's environment
(`__CFBundleIdentifier`); set `@fuzzmux-claude-notify-desktop-app` to override
it. macOS asks once to allow notifications from terminal-notifier. Without
terminal-notifier the hook falls back to `osascript`, which shows the
notification but cannot react to clicks (macOS attributes it to Script Editor,
so a click opens that instead). On Linux `notify-send` is used, also without a
click action. All three channels (message, bell, desktop) are
independent switches that share the same triggers and the same focused-pane
suppression.

A finished turn is not always the end: when Claude ends its turn with a
background shell, monitor or agent still running, it continues by itself once
that finishes. The `Stop` hook cannot see this, so the hook waits
`@fuzzmux-claude-notify-delay` seconds (default 2) and re-reads Claude's state
file: if it reports background work, the agent becomes `background` and no
notification is sent; otherwise the notification goes out as usual. The
"finished" notification therefore arrives about two seconds late, and the real
finish after the background work is notified normally. The same check guards
the idle reminder.

Installer options: `--settings <file>` (for example `.claude/settings.json` for
project scope), `--dry-run` (show the diff), `--print` (print the JSON fragment
for manual editing), `--uninstall`.

The hook script exits silently when Claude Code is not running inside tmux
(`$TMUX_PANE` unset) and never fails, so it cannot interfere with Claude Code.
`claude --bare` skips all hooks. Background agents (`claude --bg`) have no pane
and are not listed.

### Session history: find any past session and resume it in place

Press `prefix` + <kbd>y</kbd> to search every Claude Code session you ever ran,
not only the running ones:

```
  working   2m   ~/Development/app     Refactor auth middleware       │ refactor the auth middleware | now add tests | ...
  closed    3h   ~/Development/api     Fix flaky integration test     │ fix the flaky integration test | add a retry with ...
  closed    2d   ~/Development/infra   Rotate the staging certs       │ rotate the staging certs
```

Rows come from Claude Code's prompt history (`~/.claude/history.jsonl`), one per
session, newest first. The header line names the columns: `state` (running
state, or `closed`), `age` of the last prompt, `project` directory, the `first
prompt` as title, and then either `»` the matching snippet (deep mode) or `│`
every prompt of the session (prompts mode).

The popup opens in **deep** mode (`deep >`): every keystroke sends the query to
`ripgrep` over the conversation text, so your prompts and Claude's answers both
match, each row ends with the matching snippet, and the preview shows the
matching lines with two lines of context, highlighted, plus where the session
last ran. Results keep the newest-first order. The conversation text comes from
a per-session extract of the transcript (prompts and answers only, no tool
output or JSON) kept under `~/.cache/fuzzmux/claude-text/` and refreshed
whenever a transcript changed, so the first popup after many new sessions takes
a moment longer.

Matching follows fzf's habits: space-separated terms must all occur in the
conversation, in any order; inside a term up to two punctuation or whitespace
characters may separate consecutive query characters, so `wrapupcomplete` finds
"wrapup complete" and "wrapUpComplete" but not unrelated words; a term starting
with `'` must occur exactly. Press <kbd>Ctrl-f</kbd> (the filter key) for
`prompts >` mode, plain fzf filtering over the rows, where the appended prompt
text makes any prompt wording match and the preview lists the session's prompts;
press it again to go back.

Resuming lands you at the end of the conversation: `claude --resume` has no way
to scroll to a given message, which is why the preview shows the hit in context
before you decide.

<kbd>Enter</kbd> on a running session switches to its pane. On a closed one it
resumes the session with `claude --resume <id>` **where it last ran**: a new
pane split into the window it used before, or if that window is gone a new
window in that tmux session, or if that session is gone too a new window in your
current session. The working directory is the session's project directory.
The location comes from a small registry the hook appends to on every prompt
and finished turn (`$XDG_STATE_HOME/fuzzmux/claude-sessions.log`, default
`~/.local/state/...`); sessions from before the hooks were installed fall back
to a new window in the current session.

Options: `@fuzzmux-bind-claude-history` / `-zoom` (default `y` / `Y`),
`@fuzzmux-claude-history-enabled`, `@fuzzmux-claude-history-preview-enabled`,
`@fuzzmux-claude-history-preview-window` (default `up:50%` here, since hits in
context read better across the full width), and `@fuzzmux-claude-command` (the
`claude` binary or wrapper to run, default `claude`). Requires `jq`; deep mode
requires `ripgrep`.

### Status-line summary

`bin/claude_status.sh` prints a compact summary for a `#()` in your status line:

```tmux
set -g status-right '#(~/.tmux/plugins/fuzzmux.tmux/bin/claude_status.sh) %H:%M'
```

Output like `!2 *1 ~3 &1` means two agents need you (permission or question),
one finished a turn you have not looked at, three are working and one has
background work running; nothing is printed when no agent runs. It refreshes with `status-interval`, so a short interval such as `5` keeps
it current. Each group is wrapped in the matching `@fuzzmux-claude-*-style` (see
Colors above). Options: `--no-colors`, `--idle` (also count idle agents as
`.N`), `--prefix=<text>`.

## Custom Commands

### fuzzmux-broadcast-nvim

Broadcast a Neovim command to all active Neovim instances across tmux panes:

```
:fuzzmux-broadcast-nvim
```

When executed, you'll be prompted to enter a Neovim command (e.g., `set number`). The command will be sent via RPC to all Neovim instances that are being tracked by fuzzmux.nvim.

**Example usage:**
- `:fuzzmux-broadcast-nvim` then enter `set number` - Enable line numbers in all Neovim instances
- `:fuzzmux-broadcast-nvim` then enter `Oil` - Open Oil file browser in all Neovim instances
- `:fuzzmux-broadcast-nvim` then enter `vsplit` - Open vertical splits in all Neovim instances
- `:fuzzmux-broadcast-nvim` then enter `wqa` - Save all changes and close all Neovim instances

**Setting a keybinding:**

The broadcast command is bound to `prefix` + <kbd>b</kbd> by default. Override it with the `@fuzzmux-bind-broadcast-nvim` option:

```tmux
# Example: Prefix + Ctrl-B
set -g @fuzzmux-bind-broadcast-nvim 'C-b'

# Example: Alt+X without prefix
set -g @fuzzmux-bind-broadcast-nvim '!M-x'
```

Then when pressing the configured key, you'll be prompted to enter a Neovim command to broadcast.


## Integration with fuzzmux.nvim

To enable Neovim buffer tracking and switching, install [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) in your Neovim configuration. The plugin communicates with Neovim using:

1. **Environment variables** - fuzzmux.nvim sets tmux environment variables with buffer information:
   - `FUZZMUX_OPEN_FILES_<pane_id>` - Colon-separated list of open file paths
   - `FUZZMUX_CURRENT_FILE_<pane_id>` - Currently active file in the pane
   - `FUZZMUX_NVIM_SOCKET_<pane_id>` - Neovim socket path for RPC communication

2. **Neovim RPC** - fuzzmux.tmux uses the socket to send buffer switching commands directly to Neovim

Without fuzzmux.nvim, the buffer switcher (`prefix` + <kbd>f</kbd>) will display a message that no buffers are found.

## Configuration

### Basic Options

Add these to your `~/.tmux.conf` to customize the plugin:

```tmux
# Disable key bindings (if you want to set custom ones with bind-key)
set -g @fuzzmux-enable-bindings '0'

# Disable colorized output (colors are enabled by default)
set -g @fuzzmux-colors-enabled '0'

# Custom color palette (optional - uses terminal colors by default)
set -g @fuzzmux-color-palette '#eb6f92,#f6c177,#9ccfd8,#c4a7e7,#31748f,#ebbcba'
```

**Notes:**
- When `@fuzzmux-enable-bindings` is set to `'0'`, fuzzmux will unbind all its keybindings and clear its internal state. If you had tmux default bindings on those keys (like `prefix + f` for find-window), they won't be automatically restored. To restore tmux defaults, restart tmux or manually rebind them in your `.tmux.conf`.
- When re-enabling bindings (setting back to `'1'`), fuzzmux will bind keys based on your current configuration options.
- If `@fuzzmux-color-palette` is enabled and then removed from `.tmux.conf`, you need to manually unset it from tmux to return to defaults, or add this line to your `.tmux.conf` before loading the plugin:
  ```tmux
  set -gu @fuzzmux-color-palette
  ```

### Feature Toggles

Enable or disable individual features:

```tmux
# Disable specific features (all enabled by default)
set -g @fuzzmux-session-enabled '0'   # Disable session switcher
set -g @fuzzmux-pane-enabled '0'      # Disable pane switcher
set -g @fuzzmux-window-enabled '0'    # Disable window switcher
set -g @fuzzmux-nvim-enabled '0'      # Disable nvim buffer switcher
set -g @fuzzmux-claude-enabled '0'    # Disable Claude Code agent switcher (removes its focus hooks)
set -g @fuzzmux-jumplist-enabled '0'  # Disable pane jumplist (removes its hooks)

# Pane jumplist history cap (default 100)
set -g @fuzzmux-jumplist-max '100'

# Disable preview for specific features (all enabled by default)
set -g @fuzzmux-session-preview-enabled '0'
set -g @fuzzmux-pane-preview-enabled '0'
set -g @fuzzmux-window-preview-enabled '0'
set -g @fuzzmux-nvim-preview-enabled '0'
set -g @fuzzmux-claude-preview-enabled '0'
```

### Popup Appearance

Customize the fzf popup window appearance:

```tmux
# Change popup size (default: 90% for both)
set -g @fuzzmux-popup-width '80%'
set -g @fuzzmux-popup-height '85%'

# Change border style (options: rounded, single, double, heavy, simple, padded, none)
set -g @fuzzmux-popup-border-style 'rounded'

# Change border color (any tmux color name)
set -g @fuzzmux-popup-border-color 'cyan'

# Customize preview window position and size for each feature (default: right:30%)
set -g @fuzzmux-session-preview-window 'right:30%'
set -g @fuzzmux-pane-preview-window 'right:30%'
set -g @fuzzmux-window-preview-window 'right:30%'
set -g @fuzzmux-nvim-preview-window 'right:30%'
set -g @fuzzmux-claude-preview-window 'right:50%' # agent output is wide; give it room
set -g @fuzzmux-claude-history-preview-window 'up:50%' # default for this one: hits in context
```

### Color Customization

Customize the color palette used for session/window identifiers:

```tmux
# Use custom color palette (HTML hex color codes, comma-separated)
# If not set, uses terminal's default color scheme

# Examples:
# Rose Pine colors
set -g @fuzzmux-color-palette '#eb6f92,#f6c177,#9ccfd8,#c4a7e7,#31748f,#ebbcba'

# Catppuccin Mocha colors
set -g @fuzzmux-color-palette '#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#cba6f7,#94e2d5'

# Tokyo Night colors
set -g @fuzzmux-color-palette '#f7768e,#9ece6a,#e0af68,#7aa2f7,#bb9af7,#7dcfff'
```

**Note:** When `@fuzzmux-color-palette` is not set or is empty, fuzzmux uses your terminal's default ANSI colors (red, green, yellow, blue, magenta, cyan), which automatically adapt to your terminal's color scheme.

The Claude Code agent states (`permission`, `waiting`, `working`, `idle`) have their own four `@fuzzmux-claude-*-style` options in tmux style syntax; see [Claude Code Agents](#claude-code-agents).

### Progressive Filtering

Customize the fzf filtering keybinding. Press the key repeatedly to cycle through filter levels:

```tmux
# Change the filtering key (default: ctrl-f)
set -g @fuzzmux-fzf-bind-filtering 'ctrl-f'

# Examples:
set -g @fuzzmux-fzf-bind-filtering 'ctrl-f'
set -g @fuzzmux-fzf-bind-filtering 'alt-f'
```

**How it works:**
- **Window switcher**: Press once to filter by current session, press again to clear
- **Pane switcher**: Press 1st for session filter, 2nd for window filter, 3rd to clear
- **Nvim buffer switcher**: Press 1st for session, 2nd for window, 3rd for pane, 4th to clear
- **Claude Code agent switcher**: Press once to show only agents that need you, press again to clear

### Custom Key Bindings

Customize the default keybindings:

```tmux
# Customize the default bindings (lowercase for normal, uppercase for zoom)
set -g @fuzzmux-bind-session 's'        # prefix + s for sessions
set -g @fuzzmux-bind-session-zoom 'S'   # prefix + S for sessions with zoom
set -g @fuzzmux-bind-pane 'p'           # prefix + p for panes
set -g @fuzzmux-bind-pane-zoom 'P'      # prefix + P for panes with zoom
set -g @fuzzmux-bind-window 'w'         # prefix + w for windows
set -g @fuzzmux-bind-window-zoom 'W'    # prefix + W for windows with zoom
set -g @fuzzmux-bind-nvim 'f'           # prefix + f for nvim buffers
set -g @fuzzmux-bind-nvim-zoom 'F'      # prefix + F for nvim buffers with zoom
set -g @fuzzmux-bind-claude 'a'         # prefix + a for Claude Code agents
set -g @fuzzmux-bind-claude-zoom 'A'    # prefix + A for Claude Code agents with zoom
set -g @fuzzmux-bind-jump-back 'C-h'    # prefix + Ctrl-h to jump back
set -g @fuzzmux-bind-jump-forward 'C-l' # prefix + Ctrl-l to jump forward

# Broadcast-nvim command (default: prefix + b)
set -g @fuzzmux-bind-broadcast-nvim 'b'    # prefix + b for nvim broadcast
set -g @fuzzmux-bind-broadcast-nvim '!M-x' # Alt+x without prefix for nvim broadcast

# Use '!' prefix for bindings without tmux prefix (e.g., Alt+key combinations)
set -g @fuzzmux-bind-session '!M-s'      # Alt+s without prefix for sessions
set -g @fuzzmux-bind-session-zoom '!M-S' # Alt+Shift+s without prefix for sessions with zoom
set -g @fuzzmux-bind-pane '!M-p'         # Alt+p without prefix for panes
set -g @fuzzmux-bind-pane-zoom '!M-P'    # Alt+Shift+p without prefix for panes with zoom
set -g @fuzzmux-bind-window '!M-w'       # Alt+w without prefix for windows
set -g @fuzzmux-bind-window-zoom '!M-W'  # Alt+Shift+w without prefix for windows with zoom
set -g @fuzzmux-bind-nvim '!M-f'         # Alt+f without prefix for nvim buffers
set -g @fuzzmux-bind-nvim-zoom '!M-F'    # Alt+Shift+f without prefix for nvim buffers with zoom
set -g @fuzzmux-bind-claude '!M-c'       # Alt+c without prefix for Claude Code agents
set -g @fuzzmux-bind-claude-zoom '!M-C'  # Alt+Shift+c without prefix for Claude Code agents with zoom
```

Or set up completely custom bindings:

```tmux
# Disable default bindings
set -g @fuzzmux-enable-bindings '0'

# Custom bindings (will **not** use global popup and color settings)
bind-key -n M-s run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_session_switcher.sh"
bind-key -n M-S run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_session_switcher.sh --zoom"
bind-key -n M-p run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_pane_switcher.sh"
bind-key -n M-P run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_pane_switcher.sh --zoom"
bind-key -n M-w run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_window_switcher.sh"
bind-key -n M-W run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_window_switcher.sh --zoom"
bind-key -n M-f run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_nvim_buffer_switcher.sh"
bind-key -n M-F run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_nvim_buffer_switcher.sh --zoom"
bind-key -n M-c run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_claude_switcher.sh"
bind-key -n M-C run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_claude_switcher.sh --zoom"
```

**Note:** When using custom bindings, the scripts **don't respect** global configuration settings (`@fuzzmux-popup-*`, `@fuzzmux-colors-enabled`, `@fuzzmux-<feature>-preview-enabled`) automatically. You need to add the desired options (`--preview`, `--colors`, `--zoom`, etc.) directly to the command.

**Note on `@fuzzmux-bind-broadcast-nvim`:**
- The broadcast-nvim command is bound to `prefix` + <kbd>b</kbd> by default
- Set `@fuzzmux-bind-broadcast-nvim` to override the key
- Examples: `set -g @fuzzmux-bind-broadcast-nvim 'C-b'` or `set -g @fuzzmux-bind-broadcast-nvim '!M-x'`

### Command Line Options

Each script accepts the following options when called manually:

- `--preview` - Enable preview window
- `--colors` - Enable colorized output
- `--zoom` - Automatically zoom the selected pane/window
- `--popup-width=<value>` - Set popup width (default: 90%)
- `--popup-height=<value>` - Set popup height (default: 90%)
- `--popup-border=<style>` - Set border style (default: rounded)
- `--popup-color=<color>` - Set border color (default: white)
- `--color-palette=<colors>` - Set custom color palette (comma-separated hex colors)
- `--preview-window=<position:size>` - Place the fzf preview (default: right:30%)
- `--fzf-bind=<key>` - Key for the in-popup filter (default: ctrl-f)

`bin/claude_status.sh` and `bin/claude_hooks_install.sh` have their own flags, listed in [Claude Code Agents](#claude-code-agents).

Example with custom colors:
```bash
~/.tmux/plugins/fuzzmux.tmux/bin/fzf_session_switcher.sh \
  --colors \
  --preview \
  --color-palette='#ff0000,#00ff00,#0000ff'
```

## Usage Examples

### Session Switcher

Press `prefix` + <kbd>s</kbd> to open the session switcher. You'll see a list like:

```
* @main     windows:3  2025-11-14 09:30  editor,server,logs
  @project  windows:2  2025-11-14 08:15  docker,monitoring
  @test     windows:5  2025-11-13 14:22  main,test,build,docs,debug
```

The `*` in the first column indicates attached sessions (sessions with active clients). With preview enabled, the preview window shows all windows in the session with an arrow (→) indicating the active window.

- Type to fuzzy search
- Use arrow keys to navigate
- Press <kbd>Enter</kbd> to switch to the selected session
- Press <kbd>Esc</kbd> or <kbd>Ctrl-c</kbd> to cancel

**Note:** Session switcher doesn't have filtering since you're already at the session level.

### Window Switcher

Press `prefix` + <kbd>w</kbd> to open the window switcher:

```
* @main #0  nvim      panes:3  zsh,nvim,zsh
  @main #1  server    panes:1  node
  @test #0  database  panes:2  psql,zsh
```

The `*` in the first column indicates the currently active window in the current attached session. With preview enabled, the preview window shows the content of the active pane in the selected window.

**Filtering:** Press <kbd>Ctrl-f</kbd> (default) once to filter windows from the current session only, press again to show all windows.

### Pane Switcher

Press `prefix` + <kbd>p</kbd> to open the pane switcher. You'll see a list like:

```
* @main #0 %0  zsh   title1  ~/Development/project  → README.md
  @main #0 %1  nvim  title2  ~/Development/project  → main.go
  @test #2 %0  zsh   title3  ~/Development/other
```

The `*` in the first column indicates the currently active pane in the current window. The list shows: marker, session, window, pane, command, title, current path, and current Neovim file (if fuzzmux.nvim is installed). With preview enabled, the preview shows pane content (last lines for shells, first lines for other commands).

- Type to fuzzy search
- Use arrow keys to navigate
- Press <kbd>Enter</kbd> to switch to the selected pane
- Press <kbd>Esc</kbd> or <kbd>Ctrl-c</kbd> to cancel

**Filtering:** Press <kbd>Ctrl-f</kbd> (default) to progressively filter:
- 1st press: Show only panes from current session
- 2nd press: Show only panes from current window
- 3rd press: Clear filter (show all panes)

### Neovim Buffer Switcher

Press `prefix` + <kbd>f</kbd> to switch between Neovim buffers across all panes:

```
  @main #0 %1  i:%5  ~/Development/project/main.go
  @main #0 %1  i:%5  ~/Development/project/utils.go
  @test #2 %0  i:%8  ~/Development/other/config.yaml
```

The list shows: session, window, pane, pane ID, and file path. With preview enabled and `bat` installed, the preview shows syntax-highlighted file contents.

When you select a buffer:
1. tmux switches to the correct session, window, and pane
2. fuzzmux.tmux sends a command via Neovim's RPC socket to open the selected buffer
3. The selected buffer is opened in Neovim instantly

**Filtering:** Press <kbd>Ctrl-f</kbd> (default) to progressively filter:
- 1st press: Show only buffers from current session
- 2nd press: Show only buffers from current window
- 3rd press: Show only buffers from current pane
- 4th press: Clear filter (show all buffers)

### Claude Code Agent Switcher

Press `prefix` + <kbd>a</kbd>; the list, states, markers and filtering are
described in [Claude Code Agents](#claude-code-agents).

## Troubleshooting

### "fzf is not installed" error

Install fzf:

```bash
# macOS
brew install fzf

# Ubuntu/Debian
sudo apt install fzf

# Arch Linux
sudo pacman -S fzf
```

### "tmux version 3.2 or higher required" error

Update tmux:

```bash
# macOS
brew upgrade tmux

# Ubuntu/Debian
sudo apt update && sudo apt upgrade tmux
```

### "No nvim buffers found" message

This means either:
1. fuzzmux.nvim is not installed in your Neovim configuration
2. No Neovim instances are currently running in any tmux pane
3. No buffers are open in the running Neovim instances

To fix: Install [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) and ensure Neovim is running.

### "No Claude Code agents found" message

This means one of:
1. No Claude Code instance is running inside a tmux pane (instances started outside tmux have no pane to switch to)
2. `jq` is not installed, so the Claude Code state files cannot be read (only hook-tracked panes are listed then)
3. Your Claude Code version does not write `~/.claude/sessions/<pid>.json` yet (check with `claude agents --json`)
4. You use a custom `$CLAUDE_CONFIG_DIR` that is not visible to tmux's environment

Installing the hooks (see [Claude Code Agents](#claude-code-agents)) makes detection independent of the state files.

### Claude Code notifications do not appear

- Check that the hooks are registered: run `/hooks` inside Claude Code, or `bin/claude_hooks_install.sh --dry-run`
- The message is suppressed while you are looking at the agent's pane; set `@fuzzmux-claude-notify-focused '1'` to see it anyway
- Sessions started before installing the hooks are tracked from their next event; `claude --bare` skips hooks entirely
- `@fuzzmux-claude-notify-bell` only reaches the agent's own session (tmux alert scope); use the status-line summary for other sessions

### Desktop notifications do not appear or do not jump

- Check the tool in the foreground: `terminal-notifier -message test` (macOS) or `notify-send test` (Linux) must show something; the hook runs it in the background, so errors are only visible this way
- macOS: if it prints "Notifications are turned off for this application", the permission prompt was missed or denied (it does not appear when the first launch comes from a background process such as the hook). Allow terminal-notifier in System Settings > Notifications (`open "x-apple.systempreferences:com.apple.Notifications-Settings.extension"` takes you there); the `tccutil reset UserNotification ...` command it suggests fails on recent macOS releases
- Clicking jumps only with terminal-notifier; the `osascript` fallback and `notify-send` show the notification but ignore clicks
- The click activates the app named by `@fuzzmux-claude-notify-desktop-app`, defaulting to the terminal tmux was started from; set it if tmux runs under a different terminal

### Mode column shows only dashes

The permission mode comes from hook payloads. Agents that have had no hook event
since the hooks were installed (or since the plugin was updated) show `-` until
their next prompt, tool call or finished turn.

### Preview not working for files

Install `bat` for better file previews:

```bash
# macOS
brew install bat

# Ubuntu/Debian
sudo apt install bat

# Arch Linux
sudo pacman -S bat
```

## How It Works

### Popup Architecture

Each script follows a two-phase execution pattern:

1. **Phase 1** - Initial call without `--run` flag:
   - Parses configuration options
   - Launches a tmux popup with `display-popup`
   - Re-invokes itself inside the popup with `--run` flag

2. **Phase 2** - Inside the popup with `--run` flag:
   - Gathers data (sessions, windows, panes, or buffers)
   - Formats and displays it in fzf
   - Performs the switch action based on user selection

This architecture allows the scripts to work both as keybindings and as standalone commands while maintaining consistent popup behavior.

### Neovim Integration

fuzzmux.nvim communicates with fuzzmux.tmux through tmux environment variables:

```bash
FUZZMUX_OPEN_FILES_<pane_id>="file1.txt:file2.txt:file3.txt"
FUZZMUX_CURRENT_FILE_<pane_id>="current_file.txt"
FUZZMUX_NVIM_SOCKET_<pane_id>="/path/to/nvim.socket"
```

When switching buffers, fuzzmux.tmux uses Neovim's RPC socket to send buffer switching commands directly, providing instant and reliable buffer switching without relying on tmux send-keys.

### Claude Code Integration

Two sources are merged by `bin/claude_lib.sh`:

1. **Claude Code state files** - `~/.claude/sessions/<pid>.json`, written by Claude Code itself for every running instance. fuzzmux reads `tmux` (`session:@window.%pane`), `status`, `statusUpdatedAt`, `name` and `cwd`, and skips files whose process is dead or whose pane is gone. Status values map as `busy`/`compacting` to `working`, `idle`/`starting` to `idle`, `waiting` to `permission`, and any other value (`shell`, `monitor`, `agent`, ...) to `background` with the value as detail.
2. **Pane user options** - written by `bin/claude_hook.sh` from Claude Code hooks. `$TMUX_PANE` is inherited by the hook from the Claude process, so the state lands on the right pane without any lookup, and disappears with the pane:
   ```
   @fuzzmux-claude-state   permission | question | waiting | working | background | idle
   @fuzzmux-claude-since   epoch seconds when the state was entered
   @fuzzmux-claude-detail  e.g. the tool awaiting permission
   @fuzzmux-claude-mode    permission mode from the last hook payload
   ```

Hook events map to states as follows: `SessionStart` to `idle` (untouched for `compact`, which happens mid-turn); `UserPromptSubmit`, `PostToolUse` and `PostToolUseFailure` to `working`; `PermissionRequest` and `Notification(permission_prompt)` to `permission`; `PreToolUse(AskUserQuestion)` to `question`; `Stop` to `waiting`, or straight to `idle` when the pane is focused; `Notification(idle_prompt)` repeats the reminder for a `waiting` agent and turns a `working` one `idle` (an interrupted turn fires no `Stop`); `SessionEnd` clears the options. The notification is a `display-message -d` on every attached client, followed by `refresh-client -S`.

`bin/claude_focus.sh` runs from the same tmux focus hooks as the jumplist recorder (`pane-focus-in`, `after-select-pane`, `after-select-window`, `client-session-changed`, `session-window-changed`) and flips the focused pane from `waiting` to `idle`. `init.sh` installs and removes both sets of hooks with the same helper, guarded by a global flag so a config reload never duplicates them.

## Related Projects

- [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) - Neovim plugin for buffer tracking
- [fzf](https://github.com/junegunn/fzf) - Command-line fuzzy finder
- [tmux](https://github.com/tmux/tmux) - Terminal multiplexer
- [Claude Code](https://code.claude.com) - The agent the Claude Code switcher tracks; [hooks reference](https://code.claude.com/docs/en/hooks)
