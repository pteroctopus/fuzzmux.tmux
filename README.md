# fuzzmux.tmux

Created to solve the problem of quickly navigating between tmux panes, windows, and Neovim buffers using fuzzy finding.

A tmux plugin that provides fuzzy-finding capabilities for tmux panes, windows, and Neovim buffers using [fzf](https://github.com/junegunn/fzf).
Works with [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) to track and switch between Neovim buffers across tmux panes.

## Features

- **Fuzzy find tmux sessions** - Quickly switch between sessions with attached session markers
- **Fuzzy find tmux panes** - Quickly switch between panes across all sessions with active pane markers
- **Fuzzy find tmux windows** - Jump to any window with ease with active window markers
- **Fuzzy find Neovim buffers** - Switch to Neovim buffers across different panes **(requires [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim))**
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
- **fuzzmux.nvim** (optional but HIGHLY recommended) - Required for Neovim buffer tracking functionality

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
run-shell ~/.tmux/plugins/fuzzmux.tmux/plugin.tmux
```

Reload tmux config:

```bash
tmux source-file ~/.tmux.conf
```

## Default Key Bindings

With default settings, the following keybindings are available (after pressing your tmux prefix key):

**Normal (without zoom):**
- `prefix` + <kbd>s</kbd> - Fuzzy find and switch to a session
- `prefix` + <kbd>p</kbd> - Fuzzy find and switch to a pane
- `prefix` + <kbd>w</kbd> - Fuzzy find and switch to a window
- `prefix` + <kbd>f</kbd> - Fuzzy find and switch to a Neovim buffer (needs fuzzmax.nvim plugin)

**With zoom (uppercase keys):**
- `prefix` + <kbd>S</kbd> - Fuzzy find and switch to a session (with zoom)
- `prefix` + <kbd>P</kbd> - Fuzzy find and switch to a pane (with zoom)
- `prefix` + <kbd>W</kbd> - Fuzzy find and switch to a window (with zoom)
- `prefix` + <kbd>F</kbd> - Fuzzy find and switch to a Neovim buffer (with zoom) (needs fuzzmax.nvim plugin)

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

# Disable preview for specific features (all enabled by default)
set -g @fuzzmux-session-preview-enabled '0'
set -g @fuzzmux-pane-preview-enabled '0'
set -g @fuzzmux-window-preview-enabled '0'
set -g @fuzzmux-nvim-preview-enabled '0'
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

# Use '!' prefix for bindings without tmux prefix (e.g., Alt+key combinations)
set -g @fuzzmux-bind-session '!M-s'      # Alt+s without prefix for sessions
set -g @fuzzmux-bind-session-zoom '!M-S' # Alt+Shift+s without prefix for sessions with zoom
set -g @fuzzmux-bind-pane '!M-p'         # Alt+p without prefix for panes
set -g @fuzzmux-bind-pane-zoom '!M-P'    # Alt+Shift+p without prefix for panes with zoom
set -g @fuzzmux-bind-window '!M-w'       # Alt+w without prefix for windows
set -g @fuzzmux-bind-window-zoom '!M-W'  # Alt+Shift+w without prefix for windows with zoom
set -g @fuzzmux-bind-nvim '!M-f'         # Alt+f without prefix for nvim buffers
set -g @fuzzmux-bind-nvim-zoom '!M-F'    # Alt+Shift+f without prefix for nvim buffers with zoom
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
```

**Note:** When using custom bindings, the scripts **don't respect** global configuration settings (`@fuzzmux-popup-*`, `@fuzzmux-colors-enabled`, `@fuzzmux-<feature>-preview-enabled`) automatically. You need to add the desired options (`--preview`, `--colors`, `--zoom`, etc.) directly to the command.

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

## Related Projects

- [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) - Neovim plugin for buffer tracking
- [fzf](https://github.com/junegunn/fzf) - Command-line fuzzy finder
- [tmux](https://github.com/tmux/tmux) - Terminal multiplexer
