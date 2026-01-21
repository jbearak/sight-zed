using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace SendToStata;

internal static partial class Program
{
    private static readonly bool _logEnabled =
        string.Equals(Environment.GetEnvironmentVariable("SEND_TO_STATA_LOG"), "1", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(Environment.GetEnvironmentVariable("SEND_TO_STATA_LOG"), "true", StringComparison.OrdinalIgnoreCase);

    private static void Log(string message)
    {
        if (!_logEnabled) return;
        Console.Error.WriteLine($"[send-to-stata] {message}");
    }

    private static string FormatHwnd(IntPtr hWnd)
        => hWnd == IntPtr.Zero ? "0x0" : $"0x{hWnd.ToInt64():X}";

    private static string? TryGetProcessNameForWindow(IntPtr hWnd)
    {
        try
        {
            if (hWnd == IntPtr.Zero) return null;
            _ = GetWindowThreadProcessId(hWnd, out uint pid);
            if (pid == 0) return null;
            using var proc = Process.GetProcessById((int)pid);
            return proc.ProcessName;
        }
        catch
        {
            return null;
        }
    }

    private static string DescribeWindow(IntPtr hWnd)
    {
        try
        {
            if (hWnd == IntPtr.Zero) return "HWND=0x0";
            var sb = new StringBuilder(512);
            _ = GetWindowText(hWnd, sb, sb.Capacity);
            var title = sb.ToString();
            var proc = TryGetProcessNameForWindow(hWnd) ?? "?";
            return $"HWND={FormatHwnd(hWnd)} Proc={proc} Title=\"{title}\"";
        }
        catch
        {
            return $"HWND={FormatHwnd(hWnd)}";
        }
    }
    // Exit codes
    private const int EXIT_SUCCESS = 0;
    private const int EXIT_INVALID_ARGS = 1;
    private const int EXIT_FILE_NOT_FOUND = 2;
    private const int EXIT_TEMP_FILE_FAIL = 3;
    private const int EXIT_STATA_NOT_FOUND = 4;
    private const int EXIT_SENDKEYS_FAIL = 5;

    // Default timing (ms)
    private static int _clipPause = 10;
    private static int _winPause = 10;
    private static int _keyPause = 1;

    #region Win32 API imports

    // Window management
    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetForegroundWindow(IntPtr hWnd);

    [LibraryImport("user32.dll")]
    private static partial IntPtr GetForegroundWindow();

    [LibraryImport("user32.dll")]
    private static partial uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    // NOTE: StringBuilder marshalling is not supported by source-generated P/Invokes (SYSLIB1051).
    // Use the classic DllImport for GetWindowText instead.
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsIconic(IntPtr hWnd);

    [LibraryImport("user32.dll")]
    private static partial void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    // Clipboard
    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool OpenClipboard(IntPtr hWndNewOwner);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CloseClipboard();

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool EmptyClipboard();

    [LibraryImport("user32.dll")]
    private static partial IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    // Memory
    [LibraryImport("kernel32.dll")]
    private static partial IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [LibraryImport("kernel32.dll")]
    private static partial IntPtr GlobalLock(IntPtr hMem);

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GlobalUnlock(IntPtr hMem);

    [LibraryImport("kernel32.dll")]
    private static partial IntPtr GlobalFree(IntPtr hMem);

    // Keyboard input
    [LibraryImport("user32.dll", SetLastError = true)]
    private static partial uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    private const int SW_RESTORE = 9;
    private const byte VK_MENU = 0x12;      // Alt key
    private const byte VK_CONTROL = 0x11;   // Ctrl key
    private const byte VK_RETURN = 0x0D;    // Enter key
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE = 0x0002;

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_UNICODE = 0x0004;

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public INPUTUNION u;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)]
        public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    #endregion

    public class ParsedArguments
    {
        public bool Statement { get; set; }
        public bool FileMode { get; set; }
        public bool Include { get; set; }
        public bool ActivateStata { get; set; }
        public bool CDWorkspace { get; set; }
        public bool CDFile { get; set; }
        public bool Upward { get; set; }
        public bool Downward { get; set; }
        public string? File { get; set; }
        public string? Workspace { get; set; }
        public int Row { get; set; }
    }

    public static ParsedArguments ParseArguments(string[] args)
    {
        var result = new ParsedArguments();

        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i].ToLowerInvariant();
            switch (arg)
            {
                case "-statement":
                    result.Statement = true;
                    break;
                case "-filemode":
                    result.FileMode = true;
                    break;
                case "-cdworkspace":
                    result.CDWorkspace = true;
                    break;
                case "-cdfile":
                    result.CDFile = true;
                    break;
                case "-upward":
                    result.Upward = true;
                    break;
                case "-downward":
                    result.Downward = true;
                    break;
                case "-include":
                    result.Include = true;
                    break;
                case "-activatestata":
                    result.ActivateStata = true;
                    break;
                case "-returnfocus":
                    Console.Error.WriteLine("Warning: -ReturnFocus is deprecated and will be removed in a future version. The default behavior is now to return focus to Zed. Use -ActivateStata to keep focus in Stata.");
                    break;
                case "-file":
                    if (i + 1 < args.Length)
                        result.File = args[++i];
                    break;
                case "-workspace":
                    if (i + 1 < args.Length)
                        result.Workspace = args[++i];
                    break;
                case "-row":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int r))
                        result.Row = r;
                    break;
                case "-clippause":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int cp))
                        _clipPause = Math.Max(0, cp);
                    break;
                case "-winpause":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int wp))
                        _winPause = Math.Max(0, wp);
                    break;
                case "-keypause":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int kp))
                        _keyPause = Math.Max(0, kp);
                    break;
            }
        }

        return result;
    }

    [STAThread]
    static int Main(string[] args)
    {
        var parsed = ParseArguments(args);

        // Count how many modes are specified
        int modeCount = (parsed.Statement ? 1 : 0) +
                        (parsed.FileMode ? 1 : 0) +
                        (parsed.CDWorkspace ? 1 : 0) +
                        (parsed.CDFile ? 1 : 0) +
                        (parsed.Upward ? 1 : 0) +
                        (parsed.Downward ? 1 : 0);

        if (modeCount > 1)
        {
            Console.Error.WriteLine("Error: Cannot specify multiple modes (-Statement, -FileMode, -CDWorkspace, -CDFile, -Upward, -Downward)");
            return EXIT_INVALID_ARGS;
        }

        // Handle CD modes
        if (parsed.CDWorkspace)
        {
            if (string.IsNullOrEmpty(parsed.Workspace))
            {
                Console.Error.WriteLine("Error: -Workspace parameter is required for -CDWorkspace mode");
                return EXIT_INVALID_ARGS;
            }

            if (!Directory.Exists(parsed.Workspace))
            {
                Console.Error.WriteLine($"Error: Workspace directory does not exist: {parsed.Workspace}");
                return EXIT_FILE_NOT_FOUND;
            }

            string cdCommand = FormatCdCommand(parsed.Workspace);
            return SendCommandToStataWindow(cdCommand, !parsed.ActivateStata);
        }

        if (parsed.CDFile)
        {
            if (string.IsNullOrEmpty(parsed.File))
            {
                Console.Error.WriteLine("Error: -File parameter is required for -CDFile mode");
                return EXIT_INVALID_ARGS;
            }

            if (!File.Exists(parsed.File))
            {
                Console.Error.WriteLine($"Error: Cannot read file: {parsed.File}");
                return EXIT_FILE_NOT_FOUND;
            }

            string? parentDir = Path.GetDirectoryName(parsed.File);
            if (string.IsNullOrEmpty(parentDir))
            {
                Console.Error.WriteLine($"Error: Cannot determine parent directory for: {parsed.File}");
                return EXIT_INVALID_ARGS;
            }

            string cdCommand = FormatCdCommand(parentDir);
            return SendCommandToStataWindow(cdCommand, !parsed.ActivateStata);
        }

        // Handle Upward mode
        if (parsed.Upward)
        {
            if (string.IsNullOrEmpty(parsed.File))
            {
                Console.Error.WriteLine("Error: -File parameter is required for -Upward mode");
                return EXIT_INVALID_ARGS;
            }

            if (!File.Exists(parsed.File))
            {
                Console.Error.WriteLine($"Error: Cannot read file: {parsed.File}");
                return EXIT_FILE_NOT_FOUND;
            }

            if (parsed.Row <= 0)
            {
                Console.Error.WriteLine("Error: -Row parameter is required for -Upward mode");
                return EXIT_INVALID_ARGS;
            }

            string upwardContent;
            try
            {
                upwardContent = GetUpwardLines(parsed.File, parsed.Row);
            }
            catch (ArgumentOutOfRangeException ex)
            {
                Console.Error.WriteLine($"Error: {ex.Message}");
                return EXIT_INVALID_ARGS;
            }

            string? upwardTempFile = CreateTempDoFile(upwardContent);
            if (upwardTempFile == null)
            {
                Console.Error.WriteLine("Error: Cannot create temp file");
                return EXIT_TEMP_FILE_FAIL;
            }

            return SendToStataWindow(upwardTempFile, parsed.Include, !parsed.ActivateStata);
        }

        // Handle Downward mode
        if (parsed.Downward)
        {
            if (string.IsNullOrEmpty(parsed.File))
            {
                Console.Error.WriteLine("Error: -File parameter is required for -Downward mode");
                return EXIT_INVALID_ARGS;
            }

            if (!File.Exists(parsed.File))
            {
                Console.Error.WriteLine($"Error: Cannot read file: {parsed.File}");
                return EXIT_FILE_NOT_FOUND;
            }

            if (parsed.Row <= 0)
            {
                Console.Error.WriteLine("Error: -Row parameter is required for -Downward mode");
                return EXIT_INVALID_ARGS;
            }

            string downwardContent;
            try
            {
                downwardContent = GetDownwardLines(parsed.File, parsed.Row);
            }
            catch (ArgumentOutOfRangeException ex)
            {
                Console.Error.WriteLine($"Error: {ex.Message}");
                return EXIT_INVALID_ARGS;
            }

            string? downwardTempFile = CreateTempDoFile(downwardContent);
            if (downwardTempFile == null)
            {
                Console.Error.WriteLine("Error: Cannot create temp file");
                return EXIT_TEMP_FILE_FAIL;
            }

            return SendToStataWindow(downwardTempFile, parsed.Include, !parsed.ActivateStata);
        }

        // Original statement/file mode logic
        if (string.IsNullOrEmpty(parsed.File))
        {
            Console.Error.WriteLine("Error: -File parameter is required");
            return EXIT_INVALID_ARGS;
        }

        if (!File.Exists(parsed.File))
        {
            Console.Error.WriteLine($"Error: Cannot read file: {parsed.File}");
            return EXIT_FILE_NOT_FOUND;
        }

        // Determine content to send
        string content;

        // Check for ZED_SELECTED_TEXT environment variable first
        string? selectedText = Environment.GetEnvironmentVariable("ZED_SELECTED_TEXT");
        if (!string.IsNullOrEmpty(selectedText))
        {
            content = selectedText;
        }
        else if (parsed.FileMode)
        {
            content = File.ReadAllText(parsed.File);
        }
        else if (parsed.Row > 0)
        {
            content = GetStatementAtRow(parsed.File, parsed.Row);
        }
        else
        {
            Console.Error.WriteLine("Error: Either -FileMode or -Row must be specified");
            return EXIT_INVALID_ARGS;
        }

        // Create temp file
        string? tempFile = CreateTempDoFile(content);
        if (tempFile == null)
        {
            Console.Error.WriteLine("Error: Cannot create temp file");
            return EXIT_TEMP_FILE_FAIL;
        }

        // Send to Stata - return focus to Zed unless -ActivateStata is specified
        return SendToStataWindow(tempFile, parsed.Include, !parsed.ActivateStata);
    }

    /// <summary>
    /// Gets the statement at the specified row, including multi-line statements with /// continuation markers.
    /// </summary>
    private static string GetStatementAtRow(string filePath, int row)
    {
        string[] lines = File.ReadAllLines(filePath);
        if (lines.Length == 0 || row < 1 || row > lines.Length)
            return string.Empty;

        int start = row;
        int end = row;

        // Regex for /// continuation marker at end of line
        var continuationRegex = ContinuationMarkerRegex();

        // Walk backwards while previous line ends with ///
        while (start > 1 && continuationRegex.IsMatch(lines[start - 2]))
        {
            start--;
        }

        // Walk forwards while current line ends with ///
        while (end < lines.Length && continuationRegex.IsMatch(lines[end - 1]))
        {
            end++;
        }

        // Join lines from start to end (1-indexed to 0-indexed)
        var sb = new StringBuilder();
        for (int i = start - 1; i < end; i++)
        {
            if (i > start - 1)
                sb.AppendLine();
            sb.Append(lines[i]);
        }

        return sb.ToString();
    }

    [GeneratedRegex(@"///\s*$")]
    private static partial Regex ContinuationMarkerRegex();

    /// <summary>
    /// Gets lines from the start of the file to the cursor row (inclusive).
    /// If the cursor row ends with a continuation marker, extends to include the complete statement.
    /// </summary>
    /// <param name="filePath">Path to the Stata file.</param>
    /// <param name="row">Cursor row (1-indexed).</param>
    /// <returns>The extracted lines as a string with preserved line breaks.</returns>
    public static string GetUpwardLines(string filePath, int row)
    {
        string[] lines = File.ReadAllLines(filePath);
        if (lines.Length == 0)
            return string.Empty;

        if (row < 1 || row > lines.Length)
            throw new ArgumentOutOfRangeException(nameof(row),
                $"Row {row} is out of bounds (file has {lines.Length} lines)");

        var continuationRegex = ContinuationMarkerRegex();

        // Start is always line 1 (index 0)
        int startIdx = 0;

        // End at cursor row, extending forward if line has continuation
        int endIdx = row - 1;  // Convert to 0-indexed
        while (endIdx < lines.Length - 1 && continuationRegex.IsMatch(lines[endIdx]))
        {
            endIdx++;
        }

        // Join lines from start to end
        var sb = new StringBuilder();
        for (int i = startIdx; i <= endIdx; i++)
        {
            if (i > startIdx)
                sb.AppendLine();
            sb.Append(lines[i]);
        }

        return sb.ToString();
    }

    /// <summary>
    /// Gets lines from the cursor row to the end of the file (inclusive).
    /// If the cursor is on a continuation line (previous line ends with ///),
    /// extends backward to include the complete statement start.
    /// </summary>
    /// <param name="filePath">Path to the Stata file.</param>
    /// <param name="row">Cursor row (1-indexed).</param>
    /// <returns>The extracted lines as a string with preserved line breaks.</returns>
    public static string GetDownwardLines(string filePath, int row)
    {
        string[] lines = File.ReadAllLines(filePath);
        if (lines.Length == 0)
            return string.Empty;

        if (row < 1 || row > lines.Length)
            throw new ArgumentOutOfRangeException(nameof(row),
                $"Row {row} is out of bounds (file has {lines.Length} lines)");

        var continuationRegex = ContinuationMarkerRegex();

        // Start at cursor row, extending backward if on continuation line
        // A line is a continuation if the PREVIOUS line ends with ///
        int startIdx = row - 1;  // Convert to 0-indexed
        while (startIdx > 0 && continuationRegex.IsMatch(lines[startIdx - 1]))
        {
            startIdx--;
        }

        // End is always the last line
        int endIdx = lines.Length - 1;

        // Join lines from start to end
        var sb = new StringBuilder();
        for (int i = startIdx; i <= endIdx; i++)
        {
            if (i > startIdx)
                sb.AppendLine();
            sb.Append(lines[i]);
        }

        return sb.ToString();
    }

    /// <summary>
    /// Result of escaping a path for Stata's cd command.
    /// </summary>
    /// <param name="Escaped">The path with backslashes doubled.</param>
    /// <param name="UseCompound">True if the path contains double quotes and requires compound string syntax.</param>
    public record PathEscapeResult(string Escaped, bool UseCompound);

    /// <summary>
    /// Escapes a path for use in Stata's cd command.
    /// Doubles backslashes and detects if compound string syntax is needed.
    /// </summary>
    /// <param name="path">The path to escape.</param>
    /// <returns>A PathEscapeResult containing the escaped path and whether compound syntax is needed.</returns>
    public static PathEscapeResult EscapePathForStata(string path)
    {
        // Double all backslashes for Stata compatibility
        var escaped = path.Replace("\\", "\\\\");

        // Check if path contains double quotes
        var useCompound = path.Contains('"');

        return new PathEscapeResult(escaped, useCompound);
    }

    /// <summary>
    /// Formats a cd command for Stata with proper string syntax.
    /// Uses compound string syntax (`"path"') when path contains double quotes,
    /// otherwise uses regular string syntax ("path").
    /// </summary>
    /// <param name="directoryPath">The directory path to cd into.</param>
    /// <returns>The formatted cd command.</returns>
    public static string FormatCdCommand(string directoryPath)
    {
        var result = EscapePathForStata(directoryPath);

        if (result.UseCompound)
        {
            // Use compound string syntax: cd `"path"'
            return $"cd `\"{result.Escaped}\"'";
        }
        else
        {
            // Use regular string syntax: cd "path"
            return $"cd \"{result.Escaped}\"";
        }
    }

    /// <summary>
    /// Creates a temporary .do file with the specified content.
    /// </summary>
    private static string? CreateTempDoFile(string content)
    {
        try
        {
            string tempPath = Path.GetTempPath();
            string fileName = Path.ChangeExtension(Path.GetRandomFileName(), ".do");
            string fullPath = Path.Combine(tempPath, fileName);

            // Write UTF-8 without BOM
            File.WriteAllText(fullPath, content, new UTF8Encoding(false));
            return fullPath;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Finds a running Stata window.
    /// Returns a Process that the caller must dispose.
    /// </summary>
    private static Process? FindStataWindow()
    {
        // All possible Stata process names (regular, 64-bit, and Now variants)
        //
        // On Windows, the actual process name is the executable name without ".exe".
        // For Stata 64-bit installs, Task Manager commonly shows e.g. "StataMP-64.exe",
        // which corresponds to a process name of "StataMP-64".
        //
        // IMPORTANT: This list must include both legacy names (no suffix) and "-64" names.
        string[] processNames = [
            "StataMP", "StataSE", "StataBE", "StataIC", "Stata",
            "StataMP-64", "StataSE-64", "StataBE-64", "StataIC-64", "Stata-64",
            "StataNowMP", "StataNowSE", "StataNowBE", "StataNowIC", "StataNow",
            "StataNowMP-64", "StataNowSE-64", "StataNowBE-64", "StataNowIC-64", "StataNow-64"
        ];
        var titleRegex = StataTitleRegex();

        Log($"FindStataWindow: searching process names: {string.Join(", ", processNames)}");

        foreach (var name in processNames)
        {
            try
            {
                var processes = Process.GetProcessesByName(name);
                Log($"FindStataWindow: found {processes.Length} process(es) for name=\"{name}\"");

                foreach (var proc in processes)
                {
                    try
                    {
                        var title = proc.MainWindowTitle ?? "";
                        var hwnd = proc.MainWindowHandle;

                        Log($"FindStataWindow: candidate PID={proc.Id} Name=\"{proc.ProcessName}\" MainWindowHandle={FormatHwnd(hwnd)} Title=\"{title}\"");

                        // Prefer a real main window handle when possible; some processes may report a title but no HWND.
                        if (hwnd != IntPtr.Zero &&
                            !string.IsNullOrEmpty(title) &&
                            titleRegex.IsMatch(title) &&
                            !title.Contains("Viewer", StringComparison.OrdinalIgnoreCase))
                        {
                            Log($"FindStataWindow: selected PID={proc.Id} Name=\"{proc.ProcessName}\"");
                            return proc; // Caller is responsible for disposal
                        }
                    }
                    catch (Exception ex)
                    {
                        Log($"FindStataWindow: exception inspecting PID={proc.Id}: {ex.GetType().Name}: {ex.Message}");
                        // Process may have exited, continue searching
                    }

                    proc.Dispose();
                }
            }
            catch
            {
                // Ignore access denied errors
            }
        }

        Log("FindStataWindow: no matching Stata main window found.");
        return null;
    }

[GeneratedRegex(@"^(\d+\s*-\s*)?(Stata|StataNow)/(MP|SE|BE|IC)", RegexOptions.IgnoreCase)]
    private static partial Regex StataTitleRegex();

    /// <summary>
    /// Attempts to bring the specified window to the foreground.
    /// Uses the Alt key trick to bypass focus-stealing prevention.
    /// </summary>
    private static bool AcquireFocus(IntPtr windowHandle, int maxRetries = 3)
    {
        if (windowHandle == IntPtr.Zero)
        {
            Log("AcquireFocus: windowHandle is 0x0; cannot focus.");
            return false;
        }

        Log($"AcquireFocus: target={DescribeWindow(windowHandle)} maxRetries={maxRetries}");

        // Restore if minimized
        if (IsIconic(windowHandle))
        {
            Log("AcquireFocus: target is minimized; restoring.");
            ShowWindow(windowHandle, SW_RESTORE);
            Thread.Sleep(_winPause);
        }

        for (int i = 1; i <= maxRetries; i++)
        {
            var before = GetForegroundWindow();
            Log($"AcquireFocus: attempt {i}/{maxRetries}; beforeForeground={DescribeWindow(before)}");

            // Alt key trick to bypass focus-stealing prevention
            keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);                // Alt down
            keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);  // Alt up

            var setOk = SetForegroundWindow(windowHandle);
            Thread.Sleep(_winPause * i);

            var after = GetForegroundWindow();
            var focused = after == windowHandle;

            Log($"AcquireFocus: attempt {i}; SetForegroundWindow={setOk}; afterForeground={DescribeWindow(after)}; success={focused}");

            if (focused)
                return true;
        }

        Log($"AcquireFocus: FAILED to focus target={DescribeWindow(windowHandle)} after {maxRetries} attempts.");
        return false;
    }

    /// <summary>
    /// Sets text on the clipboard using Win32 API.
    /// </summary>
    private static bool SetClipboardText(string text)
    {
        if (!OpenClipboard(IntPtr.Zero))
            return false;

        IntPtr hGlobal = IntPtr.Zero;
        try
        {
            EmptyClipboard();

            // Allocate global memory for the text (Unicode)
            byte[] bytes = Encoding.Unicode.GetBytes(text + "\0");
            hGlobal = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
            if (hGlobal == IntPtr.Zero)
                return false;

            IntPtr pGlobal = GlobalLock(hGlobal);
            if (pGlobal == IntPtr.Zero)
            {
                GlobalFree(hGlobal);
                return false;
            }

            Marshal.Copy(bytes, 0, pGlobal, bytes.Length);
            GlobalUnlock(hGlobal);

            if (SetClipboardData(CF_UNICODETEXT, hGlobal) == IntPtr.Zero)
            {
                GlobalFree(hGlobal);
                return false;
            }

            // Clipboard now owns the memory - do not free hGlobal
            return true;
        }
        finally
        {
            CloseClipboard();
        }
    }

    /// <summary>
    /// Sends a key press using keybd_event (more reliable than SendInput for this use case).
    /// </summary>
    private static void SendKey(byte vk, bool keyUp = false)
    {
        keybd_event(vk, 0, keyUp ? KEYEVENTF_KEYUP : 0, UIntPtr.Zero);
    }

    /// <summary>
    /// Sends Ctrl+Key combination.
    /// </summary>
    private static void SendCtrlKey(byte vk)
    {
        SendKey(VK_CONTROL);        // Ctrl down
        SendKey(vk);                // Key down
        SendKey(vk, true);          // Key up
        SendKey(VK_CONTROL, true);  // Ctrl up
    }

    /// <summary>
    /// Sends the command to Stata via clipboard and keystrokes.
    /// </summary>
    private static int SendToStataWindow(string tempFilePath, bool useInclude, bool returnFocus)
    {
        Log($"SendToStataWindow: tempFilePath=\"{tempFilePath}\" useInclude={useInclude} returnFocus={returnFocus}");

        // Remember the current foreground window so we can return focus if requested
        IntPtr originalWindow = returnFocus ? GetForegroundWindow() : IntPtr.Zero;
        if (returnFocus)
        {
            Log($"SendToStataWindow: captured originalForeground={DescribeWindow(originalWindow)}");
        }

        // Find Stata window
        using var stataProcess = FindStataWindow();
        if (stataProcess == null)
        {
            Console.Error.WriteLine("Error: No running Stata instance found. Start Stata before sending code.");
            Log("SendToStataWindow: FindStataWindow returned null.");
            return EXIT_STATA_NOT_FOUND;
        }

        IntPtr windowHandle = stataProcess.MainWindowHandle;
        Log($"SendToStataWindow: Stata PID={stataProcess.Id} MainWindowHandle={FormatHwnd(windowHandle)}");

        // Acquire focus
        if (!AcquireFocus(windowHandle))
        {
            Console.Error.WriteLine("Error: Failed to activate Stata window after 3 attempts. " +
                "Focus-stealing prevention may be blocking SetForegroundWindow, or Stata may be running as Administrator.");
            Log($"SendToStataWindow: failed to focus Stata windowHandle={DescribeWindow(windowHandle)}");
            return EXIT_SENDKEYS_FAIL;
        }

        // Build command
        string command = useInclude
            ? $"include \"{tempFilePath}\""
            : $"do \"{tempFilePath}\"";

        // Copy to clipboard
        if (!SetClipboardText(command))
        {
            Console.Error.WriteLine("Error: Failed to set clipboard");
            return EXIT_SENDKEYS_FAIL;
        }

        Thread.Sleep(_clipPause);

        // Send keystrokes: Ctrl+1 (focus command window), Ctrl+V (paste), Enter (execute)
        try
        {
            SendCtrlKey(0x31);      // Ctrl+1 (0x31 = '1')
            Thread.Sleep(_winPause);
            SendCtrlKey(0x56);      // Ctrl+V (0x56 = 'V')
            Thread.Sleep(_keyPause);
            SendKey(VK_RETURN);     // Enter
            SendKey(VK_RETURN, true);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: Failed to send keystrokes: {ex.Message}");
            return EXIT_SENDKEYS_FAIL;
        }

        // Return focus to original window if requested
        if (returnFocus && originalWindow != IntPtr.Zero && originalWindow != windowHandle)
        {
            Thread.Sleep(_winPause * 5); // Give Stata time to process before switching back
            Log($"SendToStataWindow: attempting to return focus to originalForeground={DescribeWindow(originalWindow)}");
            var ok = AcquireFocus(originalWindow);
            Log($"SendToStataWindow: return focus result={ok} currentForeground={DescribeWindow(GetForegroundWindow())}");
        }

        return EXIT_SUCCESS;
    }

    /// <summary>
    /// Sends a raw Stata command directly via clipboard and keystrokes (no temp file).
    /// </summary>
    private static int SendCommandToStataWindow(string command, bool returnFocus)
    {
        Log($"SendCommandToStataWindow: command=\"{command}\" returnFocus={returnFocus}");

        // Remember the current foreground window so we can return focus if requested
        IntPtr originalWindow = returnFocus ? GetForegroundWindow() : IntPtr.Zero;
        if (returnFocus)
        {
            Log($"SendCommandToStataWindow: captured originalForeground={DescribeWindow(originalWindow)}");
        }

        // Find Stata window
        using var stataProcess = FindStataWindow();
        if (stataProcess == null)
        {
            Console.Error.WriteLine("Error: No running Stata instance found. Start Stata before sending code.");
            Log("SendCommandToStataWindow: FindStataWindow returned null.");
            return EXIT_STATA_NOT_FOUND;
        }

        IntPtr windowHandle = stataProcess.MainWindowHandle;
        Log($"SendCommandToStataWindow: Stata PID={stataProcess.Id} MainWindowHandle={FormatHwnd(windowHandle)}");

        // Acquire focus
        if (!AcquireFocus(windowHandle))
        {
            Console.Error.WriteLine("Error: Failed to activate Stata window after 3 attempts. " +
                "Focus-stealing prevention may be blocking SetForegroundWindow, or Stata may be running as Administrator.");
            Log($"SendCommandToStataWindow: failed to focus Stata windowHandle={DescribeWindow(windowHandle)}");
            return EXIT_SENDKEYS_FAIL;
        }

        // Copy to clipboard
        if (!SetClipboardText(command))
        {
            Console.Error.WriteLine("Error: Failed to set clipboard");
            return EXIT_SENDKEYS_FAIL;
        }

        Thread.Sleep(_clipPause);

        // Send keystrokes: Ctrl+1 (focus command window), Ctrl+V (paste), Enter (execute)
        try
        {
            SendCtrlKey(0x31);      // Ctrl+1 (0x31 = '1')
            Thread.Sleep(_winPause);
            SendCtrlKey(0x56);      // Ctrl+V (0x56 = 'V')
            Thread.Sleep(_keyPause);
            SendKey(VK_RETURN);     // Enter
            SendKey(VK_RETURN, true);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: Failed to send keystrokes: {ex.Message}");
            return EXIT_SENDKEYS_FAIL;
        }

        // Return focus to original window if requested
        if (returnFocus && originalWindow != IntPtr.Zero && originalWindow != windowHandle)
        {
            Thread.Sleep(_winPause * 5); // Give Stata time to process before switching back
            Log($"SendCommandToStataWindow: attempting to return focus to originalForeground={DescribeWindow(originalWindow)}");
            var ok = AcquireFocus(originalWindow);
            Log($"SendCommandToStataWindow: return focus result={ok} currentForeground={DescribeWindow(GetForegroundWindow())}");
        }

        return EXIT_SUCCESS;
    }
}
