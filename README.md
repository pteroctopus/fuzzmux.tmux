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

- **tmux** >= 3.2 (required for `display-popup`)
- **fzf** (required) - [Installation instructions](https://github.com/junegunn/fzf#installation)
- **bat** (optional) - For enhanced file previews in Neovim buffer switcher
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
run-shell ~/.tmux/plugins/fuzzmux.tmux/scripts/init.sh
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
# Disable the plugin entirely
set -g @fuzzmux-enabled '0'

# Disable default key bindings (if you want to set custom ones)
set -g @fuzzmux-default-bindings '0'

# Disable preview windows
set -g @fuzzmux-preview-enabled '0'

# Disable colorized output
set -g @fuzzmux-colors-enabled '0'
```

**Note:** When disabling the plugin or default bindings, fuzzmux will unbind its keybindings. If you had tmux default bindings on those keys (like `prefix + f` for find-window), they won't be automatically restored. To restore tmux defaults, restart tmux or manually rebind them in your `.tmux.conf`.

### Feature Toggles

Enable or disable individual features:

```tmux
# Disable specific features (all enabled by default)
set -g @fuzzmux-session-enabled '0'   # Disable session switcher
set -g @fuzzmux-pane-enabled '0'      # Disable pane switcher
set -g @fuzzmux-window-enabled '0'    # Disable window switcher
set -g @fuzzmux-nvim-enabled '0'      # Disable nvim buffer switcher
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

If you want different keybindings, you can customize them:

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
```

Or set up completely custom bindings:

```tmux
# Disable default bindings
set -g @fuzzmux-default-bindings '0'

# Custom bindings with specific options
bind-key -n M-s run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_session_switcher.sh --preview --colors"
bind-key -n M-S run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_session_switcher.sh --preview --colors --zoom"
bind-key -n M-p run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_pane_switcher.sh --preview --colors"
bind-key -n M-P run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_pane_switcher.sh --preview --colors --zoom"
bind-key -n M-w run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_window_switcher.sh --preview --colors"
bind-key -n M-W run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_window_switcher.sh --preview --colors --zoom"
bind-key -n M-f run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_nvim_files.sh --preview --colors"
bind-key -n M-F run-shell "~/.tmux/plugins/fuzzmux.tmux/bin/fzf_nvim_files.sh --preview --colors --zoom"
```

### Command Line Options

Each script accepts the following options:

- `--preview` - Enable preview window
- `--colors` - Enable colorized output
- `--zoom` - Automatically zoom the selected pane/window

## Integration with fuzzmux.nvim

To enable Neovim buffer tracking and switching, install [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) in your Neovim configuration. The plugin will automatically detect and use the environment variables set by fuzzmux.nvim.

Without fuzzmux.nvim, the buffer switcher (`prefix` + <kbd>f</kbd>) will display a message that no buffers are found.

## Usage Examples

### Session Switcher

Press `prefix` + <kbd>s</kbd> to open the session switcher. You'll see a list like:

```
s0        3 windows  2025-11-14 09:30  editor,server,logs    *
s1        2 windows  2025-11-14 08:15  docker,monitoring
sproject  5 windows  2025-11-13 14:22  main,test,build,docs,debug
```

The `*` indicates the currently attached session. The preview window shows all windows in the session.

- Type to fuzzy search
- Use arrow keys to navigate
- Press <kbd>Enter</kbd> to switch to the selected session
- Press <kbd>Esc</kbd> or <kbd>Ctrl-c</kbd> to cancel

### Pane Switcher

Press `prefix` + <kbd>p</kbd> to open the pane switcher. You'll see a list like:

```
s0 w0 p0  zsh      ~              ~/Development/project
s0 w0 p1  nvim     main.go        ~/Development/project
s1 w2 p0  zsh      docker-comp... ~/Development/other
```

- Type to fuzzy search
- Use arrow keys to navigate
- Press <kbd>Enter</kbd> to switch to the selected pane
- Press <kbd>Esc</kbd> or <kbd>Ctrl-c</kbd> to cancel

### Window Switcher

Press `prefix` + <kbd>w</kbd> to open the window switcher:

```
s0 w0  editor    (3 panes)  zsh,nvim,zsh  *
s0 w1  server    (1 panes)  node
s1 w0  database  (2 panes)  psql,zsh
```

The `*` indicates the currently active window.

### Neovim Buffer Switcher

Press `prefix` + <kbd>f</kbd> to switch between Neovim buffers across all panes:

```
s0 w0 p1  ~/Development/project/main.go
s0 w0 p1  ~/Development/project/utils.go
s1 w2 p0  ~/Development/other/config.yaml
```

When you select a buffer:
1. tmux switches to the correct session, window, and pane
2. If Neovim is suspended, it's automatically resumed
3. The selected buffer is opened in Neovim

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

### Environment Variables

fuzzmux.nvim sets global tmux environment variables with information about open buffers:

```bash
FUZZMUX_OPEN_FILES_<session>_<window>_<pane>="file1.txt:file2.txt:file3.txt"
FUZZMUX_CURRENT_FILE_<session>_<window>_<pane>="current_file.txt"
```

fuzzmux.tmux reads these variables to display and switch between buffers.

### Popup Windows

The plugin uses tmux's `display-popup` feature to show an interactive fzf interface without disrupting your current layout.

## Related Projects

- [fuzzmux.nvim](https://github.com/pteroctopus/fuzzmux.nvim) - Neovim plugin for buffer tracking
- [fzf](https://github.com/junegunn/fzf) - Command-line fuzzy finder
- [tmux](https://github.com/tmux/tmux) - Terminal multiplexer
