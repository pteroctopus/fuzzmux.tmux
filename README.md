# fuzzmux.tmux

Created to solve the problem of quickly navigating between tmux panes, windows, and Neovim buffers using fuzzy finding.

A tmux plugin that provides fuzzy-finding capabilities for tmux panes, windows, and Neovim buffers using [fzf](https://github.com/junegunn/fzf).
Works with [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) to track and switch between Neovim buffers across tmux panes.

## Features

- **Fuzzy find tmux sessions** - Quickly switch between sessions
- **Fuzzy find tmux panes** - Quickly switch between panes across all sessions
- **Fuzzy find tmux windows** - Jump to any window with ease
- **Fuzzy find Neovim buffers** - Switch to Neovim buffers across different panes **(requires [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim))**
- **Colorized output** - Color-coded session/window identifiers for better visibility
- **Live previews** - Preview pane/window content or file contents before switching
- **Zoom support** - Optionally zoom into selected pane/window
- **Configurable** - Customize keybindings and behavior
- **Feature toggles** - Enable/disable individual features as needed

https://github.com/user-attachments/assets/76bac81f-d7ae-45ee-8a54-c00b87e01103

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

## Configuration

### Basic Options

Add these to your `~/.tmux.conf` to customize the plugin:

```tmux
# Disable key bindings (if you want to set custom ones with bind-key)
set -g @fuzzmux-enable-bindings '0'

# Disable colorized output
set -g @fuzzmux-colors-enabled '0'
```

**Note:** When disabling default bindings, fuzzmux will unbind its keybindings. If you had tmux default bindings on those keys (like `prefix + f` for find-window), they won't be automatically restored. To restore tmux defaults, restart tmux or manually rebind them in your `.tmux.conf`.

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
```

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

# Custom bindings (will use global popup and color settings)
bind-key -n M-s run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_session_switcher.sh"
bind-key -n M-S run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_session_switcher.sh --zoom"
bind-key -n M-p run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_pane_switcher.sh"
bind-key -n M-P run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_pane_switcher.sh --zoom"
bind-key -n M-w run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_window_switcher.sh"
bind-key -n M-W run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_window_switcher.sh --zoom"
bind-key -n M-f run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_nvim_files.sh"
bind-key -n M-F run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_nvim_files.sh --zoom"
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
- `--popup-color=<color>` - Set border color (default: green)

## Integration with fuzzmux.nvim

To enable Neovim buffer tracking and switching, install [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) in your Neovim configuration. The plugin communicates with Neovim using:

1. **Environment variables** - fuzzmux.nvim sets tmux environment variables with buffer information:
   - `FUZZMUX_OPEN_FILES_<pane_id>` - Colon-separated list of open file paths
   - `FUZZMUX_CURRENT_FILE_<pane_id>` - Currently active file in the pane
   - `FUZZMUX_NVIM_SOCKET_<pane_id>` - Neovim socket path for RPC communication

2. **Neovim RPC** - fuzzmux.tmux uses the socket to send buffer switching commands directly to Neovim

Without fuzzmux.nvim, the buffer switcher (`prefix` + <kbd>f</kbd>) will display a message that no buffers are found.

## Usage Examples

### Session Switcher

Press `prefix` + <kbd>s</kbd> to open the session switcher. You'll see a list like:

```
@0        windows:3  2025-11-14 09:30  editor,server,logs    *
@1        windows:2  2025-11-14 08:15  docker,monitoring
@project  windows:5  2025-11-13 14:22  main,test,build,docs,debug
```

The `*` indicates the currently attached session. With preview enabled, the preview window shows all windows in the session with an arrow (→) indicating the active window.

- Type to fuzzy search
- Use arrow keys to navigate
- Press <kbd>Enter</kbd> to switch to the selected session
- Press <kbd>Esc</kbd> or <kbd>Ctrl-c</kbd> to cancel

### Window Switcher

Press `prefix` + <kbd>w</kbd> to open the window switcher:

```
@0 #0  nvim      panes:3  zsh,nvim,zsh  *
@0 #1  server    panes:1  node
@1 #0  database  panes:2  psql,zsh
```

The `*` indicates the currently active window. With preview enabled, the preview window shows the content of the active pane in the selected window.

### Pane Switcher

Press `prefix` + <kbd>p</kbd> to open the pane switcher. You'll see a list like:

```
@0 #0 %0  zsh      title1    ~/Development/project       ~/Development/project/README.md
@0 #0 %1  nvim     title2    ~/Development/project       ~/Development/project/main.go
@1 #2 %0  zsh      title3    ~/Development/other         ~/Development/other/config.yml
```

The list shows: session, window, pane, command, title, current path, and current Neovim file (if fuzzmux.nvim is installed). With preview enabled, the preview shows pane content (last lines for shells, first lines for other commands).

- Type to fuzzy search
- Use arrow keys to navigate
- Press <kbd>Enter</kbd> to switch to the selected pane
- Press <kbd>Esc</kbd> or <kbd>Ctrl-c</kbd> to cancel

### Neovim Buffer Switcher

Press `prefix` + <kbd>f</kbd> to switch between Neovim buffers across all panes:

```
@0 #0 %1  i:%5  ~/Development/project/main.go
@0 #0 %1  i:%5  ~/Development/project/utils.go
@1 #2 %0  i:%8  ~/Development/other/config.yaml
```

The list shows: session, window, pane and file path. With preview enabled and `bat` installed, the preview shows syntax-highlighted file contents.

When you select a buffer:
1. tmux switches to the correct session, window, and pane
2. fuzzmux.tmux sends a command via Neovim's RPC socket to open the selected buffer
3. The selected buffer is opened in Neovim instantly

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
