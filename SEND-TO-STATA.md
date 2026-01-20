# Send Code to Stata

Send Stata code from Zed editor to Stata for execution. Supports two modes:
- **Stata application** (macOS/Windows): Uses AppleScript (macOS) or clipboard+SendKeys (Windows) to send code to the Stata app
- **Terminal sessions**: Pastes code into the active terminal (works with SSH, multiple sessions)

## Prerequisites

### macOS
- **Stata** installed in `/Applications/Stata/` (StataMP, StataSE, StataIC, or Stata)
- **jq** for JSON manipulation (`brew install jq`)
- **python3** (used to safely handle shell metacharacters in selections)
- **Zed** editor

### Windows
- **PowerShell 7+** (`pwsh`) — install with `winget install Microsoft.PowerShell` if needed
- **Stata** installed in standard location (auto-detected)
- **Zed** editor

## Quick Start

### macOS

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/install-send-to-stata.sh)"
```

Or install from a local clone:

```bash
git clone https://github.com/jbearak/sight-zed
cd sight-zed
./install-send-to-stata.sh
```

### Windows

```powershell
irm https://raw.githubusercontent.com/jbearak/sight-zed/main/install-send-to-stata.ps1 | iex
```

Or install from a local clone:

```powershell
git clone https://github.com/jbearak/sight-zed
cd sight-zed
pwsh -File .\install-send-to-stata.ps1
```

> [TIP]
> The installer prompts whether to return focus to Zed after sending code to Stata. For non-interactive installs, pass `-ReturnFocus true` or `-ReturnFocus false`.

The installer will:
1. Copy the send-to-stata script to the appropriate location
2. Add Zed tasks to your tasks.json
3. Add keybindings to your keymap.json
4. Detect your installed Stata variant
5. (Windows) Optionally register Stata's Automation type library

## Keybindings

In `.do` files:

| Mac                   | Windows                | Action                                 |
|-----------------------|------------------------|----------------------------------------|
| `cmd-enter`           | `ctrl-enter`           | Send statement to Stata app            |
| `shift-cmd-enter`     | `shift-ctrl-enter`     | Send file to Stata app                 |
| `opt-cmd-enter`       | `alt-ctrl-enter`       | Include statement (preserves locals)   |
| `opt-shift-cmd-enter` | `alt-shift-ctrl-enter` | Include file (preserves locals)        |
| `shift-enter`         | `shift-enter`          | Paste selection to terminal            |
| `opt-enter`           | `alt-enter`            | Paste current line to terminal         |

### Quick Terminal Shortcuts

The `shift-enter` and `opt-enter` shortcuts use Zed's `SendKeystrokes` to paste code into the active terminal panel:

- **`shift-enter`**: Copies the current selection, switches to the terminal (`ctrl-``), pastes, and executes
- **`opt-enter`**: Selects the current line, copies it, switches to the terminal, pastes, and executes (functionally equivalent to selecting a line and pressing `shift-enter`)

Both shortcuts copy the selected text to your Mac's clipboard. After execution, focus remains in the terminal—any subsequent keystrokes go to the terminal, not the editor. Press `ctrl-`` to return focus to the editor.

These shortcuts paste directly into whatever terminal is active in Zed. To use them with Stata, open a terminal panel and launch the Stata CLI (e.g., `stata`, or `stata-mp`). This is particularly useful for:

- **Remote sessions**: When working over SSH, the application shortcuts control your local Stata. These terminal shortcuts send code to the remote Stata session in your terminal.
- **Multiple sessions**: You can have multiple terminal tabs running different Stata instances and send code to whichever is active. The application shortcuts always target the single Stata app.

Note that `opt-enter` sends only the current line—it doesn't detect multi-line statements with `///` continuations like the application shortcuts do. For multi-line statements, select the text and use `shift-enter`. The two separate shortcuts exist due to a Zed limitation (SendKeystrokes can't conditionally check for a selection).

**Important**: You cannot use `shift-enter` or `opt-enter` to send statements with `///` continuation lines. Stata's console does not accept continuation syntax when code is pasted directly—it will print an error. For multi-line statements with continuations, use `cmd-enter` instead, which writes the code to a temp file and executes it via `do`.

There's no "send file to terminal" shortcut because Zed's SendKeystrokes doesn't have access to the file path. The application shortcuts can send files because they invoke tasks, which can run scripts with access to `$ZED_FILE`—but there's no way to get script output back into a SendKeystrokes sequence.

### do vs include

The default keybindings use Stata's `do` command, which isolates local macros to the executed code. The `opt` variants use `include` instead, which preserves local macros in the calling context—useful for debugging when you need to inspect locals after running code.

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

### Stdin Size Limit

When sending a selection via stdin (`--stdin`), the script enforces a size limit to avoid accidental huge payloads.

- Default: 10MB
- Configure via:

```bash
export STATA_STDIN_MAX_BYTES=10485760
```

### Cleanup on AppleScript Failure

By default, temp `.do` files are kept even if AppleScript fails (useful for debugging). To delete the temp file when AppleScript fails:

```bash
export STATA_CLEANUP_ON_ERROR=1
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
       "command": "python3 -c 'import os,sys; sys.exit(0 if os.environ.get(\\\"ZED_SELECTED_TEXT\\\", \\\"\\\") else 1)' && python3 -c 'import os,sys; sys.stdout.write(os.environ.get(\\\"ZED_SELECTED_TEXT\\\", \\\"\\\"))' | send-to-stata.sh --statement --stdin --file \"$ZED_FILE\" || send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\"",
       "use_new_terminal": false,
       "allow_concurrent_runs": true,
       "reveal": "never",
       "hide": "on_success"
     },
     {
       "label": "Stata: Send File",
       "command": "send-to-stata.sh --file-mode --file \"$ZED_FILE\"",
       "use_new_terminal": false,
       "allow_concurrent_runs": true,
       "reveal": "never",
       "hide": "on_success"
     },
     {
       "label": "Stata: Include Statement",
       "command": "python3 -c 'import os,sys; sys.exit(0 if os.environ.get(\\\"ZED_SELECTED_TEXT\\\", \\\"\\\") else 1)' && python3 -c 'import os,sys; sys.stdout.write(os.environ.get(\\\"ZED_SELECTED_TEXT\\\", \\\"\\\"))' | send-to-stata.sh --statement --include --stdin --file \"$ZED_FILE\" || send-to-stata.sh --statement --include --file \"$ZED_FILE\" --row \"$ZED_ROW\"",
       "use_new_terminal": false,
       "allow_concurrent_runs": true,
       "reveal": "never",
       "hide": "on_success"
     },
     {
       "label": "Stata: Include File",
       "command": "send-to-stata.sh --file-mode --include --file \"$ZED_FILE\"",
       "use_new_terminal": false,
       "allow_concurrent_runs": true,
       "reveal": "never",
       "hide": "on_success"
     }
   ]
   ```
   > **Note**: The "Send Statement" and "Include Statement" tasks use stdin mode (`--stdin`) to handle Stata compound strings (e.g., `` `"text"' ``) and other shell metacharacters correctly. The command must not inline the selection into the zsh command line; use an environment read (e.g. via `python3`) rather than Zed interpolation to avoid parse errors when the selection contains backticks.

3. Add keybindings to `~/.config/zed/keymap.json`:
   ```json
   [
     {
       "context": "Editor && extension == do",
       "bindings": {
         "cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send Statement"}]]],
         "shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send File"}]]],
         "alt-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include Statement"}]]],
         "alt-shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include File"}]]],
         "shift-enter": ["workspace::SendKeystrokes", "cmd-c ctrl-` cmd-v enter"],
         "alt-enter": ["workspace::SendKeystrokes", "cmd-left shift-cmd-right cmd-c ctrl-` cmd-v enter"]
       }
     }
   ]
   ```

   > **Note**: The keybindings use `action::Sequence` to save the file before sending to Stata, ensuring the latest changes are executed. The `shift-enter` and `opt-enter` shortcuts use `SendKeystrokes` for quick terminal interaction without saving.

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

### macOS

```bash
./install-send-to-stata.sh --uninstall
```

This removes:
- `~/.local/bin/send-to-stata.sh`
- Stata tasks from `~/.config/zed/tasks.json`
- Stata keybindings from `~/.config/zed/keymap.json`

### Windows

```powershell
.\install-send-to-stata.ps1 -Uninstall
```

This removes:
- `%APPDATA%\Zed\stata\` directory
- Stata tasks from `%APPDATA%\Zed\tasks.json`
- Stata keybindings from `%APPDATA%\Zed\keymap.json`

## Temp File Cleanup

The script creates temporary `.do` files in your system temp directory. These files are not automatically deleted because Stata needs time to read them.

### macOS

```bash
# View temp files
ls -la $TMPDIR/stata_send_*.do

# Remove all temp files
rm $TMPDIR/stata_send_*.do
```

### Windows

```powershell
# View temp files
Get-ChildItem $env:TEMP\*.do

# Remove all temp files
Remove-Item $env:TEMP\*.do
```

Consider adding periodic cleanup to your shell config or using a scheduled task.

---

## Windows-Specific Information

### How It Works

On Windows, the script uses clipboard and SendKeys automation:
1. Writes your code to a temp `.do` file
2. Copies the `do` or `include` command to the clipboard
3. Activates the Stata window
4. Sends Ctrl+1 (focus Command window), Ctrl+V (paste), Enter (execute)

### Stata Installation Detection

The script searches for Stata in these locations (versions 19 down to 13):
- `C:\Program Files\Stata{version}\`
- `C:\Program Files (x86)\Stata{version}\`
- `C:\Stata{version}\`
- StataNow variants in the same locations
- Fallback: `C:\Stata\`

To override, set the `STATA_PATH` environment variable:

```powershell
$env:STATA_PATH = "D:\Custom\Stata\StataSE-64.exe"
```

### Stata Automation Registration

The installer may prompt to register Stata's Automation type library. This is a one-time setup that requires administrator privileges.

To manually register:
1. Open PowerShell as Administrator
2. Run: `& "C:\Program Files\Stata18\StataSE-64.exe" /Register`

Installer flags:
- `-RegisterAutomation`: Force registration
- `-SkipAutomationCheck`: Skip the registration check

If send-to-stata stops working after upgrading Stata, re-run the installer to update the registration.

### Timing Configuration

The script uses hardcoded timing values that work on most systems:

```powershell
$clipPause = 10   # ms after clipboard copy
$winPause  = 10   # ms between window operations
$keyPause  = 1    # ms between keystrokes
```

If the script fails intermittently on slower machines, increase these values by editing `send-to-stata.ps1` in `%APPDATA%\Zed\stata\`.

### Important: Stata Must Not Run as Administrator

Due to Windows User Interface Privilege Isolation (UIPI), the script cannot send keystrokes to an elevated Stata process. If you see "Failed to activate Stata window", ensure Stata is running as a normal user (not "Run as Administrator").

### Terminal Shortcuts Limitations

The `shift-enter` and `alt-enter` shortcuts paste code directly to the terminal:
- `alt-enter` sends only the current line—it doesn't detect multi-line statements with `///` continuations
- `///` continuation syntax cannot be pasted directly to Stata's console; use `ctrl-enter` for multi-line statements
