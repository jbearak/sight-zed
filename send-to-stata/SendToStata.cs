using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace SendToStata;

internal static partial class Program
{
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

    [STAThread]
    static int Main(string[] args)
    {
        // Parse arguments
        bool statement = false;
        bool fileMode = false;
        bool include = false;
        bool returnFocus = false;
        string? file = null;
        int row = 0;

        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i].ToLowerInvariant();
            switch (arg)
            {
                case "-statement":
                    statement = true;
                    break;
                case "-filemode":
                    fileMode = true;
                    break;
                case "-include":
                    include = true;
                    break;
                case "-returnfocus":
                    returnFocus = true;
                    break;
                case "-file":
                    if (i + 1 < args.Length)
                        file = args[++i];
                    break;
                case "-row":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int r))
                        row = r;
                    break;
                case "-clippause":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int cp))
                        _clipPause = cp;
                    break;
                case "-winpause":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int wp))
                        _winPause = wp;
                    break;
                case "-keypause":
                    if (i + 1 < args.Length && int.TryParse(args[++i], out int kp))
                        _keyPause = kp;
                    break;
            }
        }

        // Validate arguments
        if (statement && fileMode)
        {
            Console.Error.WriteLine("Error: Cannot specify both -Statement and -FileMode");
            return EXIT_INVALID_ARGS;
        }

        if (string.IsNullOrEmpty(file))
        {
            Console.Error.WriteLine("Error: -File parameter is required");
            return EXIT_INVALID_ARGS;
        }

        if (!File.Exists(file))
        {
            Console.Error.WriteLine($"Error: Cannot read file: {file}");
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
        else if (fileMode)
        {
            content = File.ReadAllText(file);
        }
        else if (row > 0)
        {
            content = GetStatementAtRow(file, row);
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

        // Send to Stata
        return SendToStataWindow(tempFile, include, returnFocus);
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
        // All possible Stata process names (regular and Now variants)
        string[] processNames = ["StataMP", "StataSE", "StataBE", "StataIC", "Stata",
                                 "StataNowMP", "StataNowSE", "StataNowBE", "StataNowIC", "StataNow"];
        var titleRegex = StataTitleRegex();

        foreach (var name in processNames)
        {
            try
            {
                var processes = Process.GetProcessesByName(name);
                foreach (var proc in processes)
                {
                    try
                    {
                        if (!string.IsNullOrEmpty(proc.MainWindowTitle) &&
                            titleRegex.IsMatch(proc.MainWindowTitle) &&
                            !proc.MainWindowTitle.Contains("Viewer"))
                        {
                            return proc; // Caller is responsible for disposal
                        }
                    }
                    catch
                    {
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

        return null;
    }

    [GeneratedRegex(@"^(Stata|StataNow)/(MP|SE|BE|IC)", RegexOptions.IgnoreCase)]
    private static partial Regex StataTitleRegex();

    /// <summary>
    /// Finds the Zed editor window.
    /// </summary>
    private static IntPtr FindZedWindow()
    {
        try
        {
            var processes = Process.GetProcessesByName("Zed");
            foreach (var proc in processes)
            {
                try
                {
                    if (proc.MainWindowHandle != IntPtr.Zero)
                    {
                        return proc.MainWindowHandle;
                    }
                }
                finally
                {
                    proc.Dispose();
                }
            }
        }
        catch
        {
            // Ignore errors
        }

        return IntPtr.Zero;
    }

    /// <summary>
    /// Attempts to bring the specified window to the foreground.
    /// Uses the Alt key trick to bypass focus-stealing prevention.
    /// </summary>
    private static bool AcquireFocus(IntPtr windowHandle, int maxRetries = 3)
    {
        // Restore if minimized
        if (IsIconic(windowHandle))
        {
            ShowWindow(windowHandle, SW_RESTORE);
            Thread.Sleep(_winPause);
        }

        for (int i = 1; i <= maxRetries; i++)
        {
            // Alt key trick to bypass focus-stealing prevention
            keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);           // Alt down
            keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); // Alt up

            SetForegroundWindow(windowHandle);
            Thread.Sleep(_winPause * i);

            if (GetForegroundWindow() == windowHandle)
                return true;
        }

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
        // Remember the current foreground window so we can return focus if requested
        IntPtr originalWindow = returnFocus ? GetForegroundWindow() : IntPtr.Zero;

        // Find Stata window
        using var stataProcess = FindStataWindow();
        if (stataProcess == null)
        {
            Console.Error.WriteLine("Error: No running Stata instance found. Start Stata before sending code.");
            return EXIT_STATA_NOT_FOUND;
        }

        IntPtr windowHandle = stataProcess.MainWindowHandle;

        // Acquire focus
        if (!AcquireFocus(windowHandle))
        {
            Console.Error.WriteLine("Error: Failed to activate Stata window after 3 attempts. " +
                "Focus-stealing prevention may be blocking SetForegroundWindow, or Stata may be running as Administrator.");
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
        if (returnFocus)
        {
            Thread.Sleep(_winPause * 5); // Give Stata time to process before switching back

            // Try to find Zed window by process name
            var zedWindow = FindZedWindow();
            if (zedWindow != IntPtr.Zero)
            {
                AcquireFocus(zedWindow);
            }
            else if (originalWindow != IntPtr.Zero && originalWindow != windowHandle)
            {
                // Fall back to original foreground window
                AcquireFocus(originalWindow);
            }
        }

        return EXIT_SUCCESS;
    }
}
