# Send Code to Stata

Send Stata code from Zed editor to the Stata GUI application for execution.

## Prerequisites

- **macOS** (required for AppleScript)
- **Stata** installed in `/Applications/Stata/` (StataMP, StataSE, StataIC, or Stata)
- **jq** for JSON manipulation (`brew install jq`)
- **Zed** editor

## Quick Start

```bash
git clone https://github.com/jbearak/sight-zed
cd sight-zed
./install-send-to-stata.sh
```

The installer will:
1. Copy `send-to-stata.sh` to `~/.local/bin/`
2. Add Zed tasks to `~/.config/zed/tasks.json`
3. Add keybindings to `~/.config/zed/keymap.json`
4. Detect your installed Stata variant

## Keybindings

In `.do` files:

| Shortcut | Action |
|----------|--------|
| `cmd-enter` | Send current statement (or selection) to Stata |
| `shift-cmd-enter` | Send entire file to Stata |

### Statement Detection

When no text is selected, `cmd-enter` sends the current statement:
- Single-line statements are sent as-is
- Multi-line statements using `///` continuation markers are detected automatically
- The cursor can be on any line of a multi-line statement

## Configuration

### Stata Variant

The script auto-detects your Stata installation by checking `/Applications/Stata/` for:
1. StataMP
2. StataSE
3. StataIC
4. Stata

To override, set the `STATA_APP` environment variable:

```bash
# Add to ~/.zshrc or ~/.bashrc
export STATA_APP="StataSE"
```

### PATH Setup

If `~/.local/bin` is not in your PATH, add it:

```bash
# Add to ~/.zshrc or ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
```

## Manual Installation

If you prefer not to use the installer:

1. Copy the script:
   ```bash
   mkdir -p ~/.local/bin
   cp send-to-stata.sh ~/.local/bin/
   chmod +x ~/.local/bin/send-to-stata.sh
   ```

2. Add tasks to `~/.config/zed/tasks.json`:
   ```json
   [
     {
       "label": "Stata: Send Statement",
       "command": "send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\" --text \"${ZED_SELECTED_TEXT:}\"",
       "use_new_terminal": false,
       "allow_concurrent_runs": true,
       "reveal": "never"
     },
     {
       "label": "Stata: Send File",
       "command": "send-to-stata.sh --file --file \"$ZED_FILE\"",
       "use_new_terminal": false,
       "allow_concurrent_runs": true,
       "reveal": "never"
     }
   ]
   ```

3. Add keybindings to `~/.config/zed/keymap.json`:
   ```json
   [
     {
       "context": "Editor && extension == do",
       "bindings": {
         "cmd-enter": ["task::Spawn", { "task_name": "Stata: Send Statement" }],
         "shift-cmd-enter": ["task::Spawn", { "task_name": "Stata: Send File" }]
       }
     }
   ]
   ```

## Troubleshooting

### "No Stata installation found"

- Verify Stata is installed in `/Applications/Stata/`
- Or set `STATA_APP` environment variable to your Stata application name

### "jq is required but not installed"

Install jq with Homebrew:
```bash
brew install jq
```

### "command not found: send-to-stata.sh"

Add `~/.local/bin` to your PATH (see Configuration section above), then restart your terminal.

### Code doesn't execute in Stata

- Ensure Stata is running before sending code
- Check that the correct Stata variant is detected (or set `STATA_APP`)

## Uninstall

```bash
./install-send-to-stata.sh --uninstall
```

This removes:
- `~/.local/bin/send-to-stata.sh`
- Stata tasks from `~/.config/zed/tasks.json`
- Stata keybindings from `~/.config/zed/keymap.json`

## Temp File Cleanup

The script creates temporary `.do` files in your system temp directory (`$TMPDIR`). These files are not automatically deleted because Stata needs time to read them.

To clean up old temp files:

```bash
# View temp files
ls -la $TMPDIR/stata_send_*.do

# Remove all temp files
rm $TMPDIR/stata_send_*.do
```

Consider adding periodic cleanup to your shell config or using a cron job.
