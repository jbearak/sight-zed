using FsCheck;
using FsCheck.Xunit;
using SendToStata;
using Xunit;

namespace SendToStata.Tests;

/// <summary>
/// Property-based tests for line extraction functions.
/// 
/// Property 4: Upward Bounds Extraction
/// Property 5: Downward Bounds Extraction
/// 
/// **Validates: Requirements 3.1, 3.2, 3.5, 4.1, 4.2, 4.5**
/// </summary>
public class LineExtractionTests : IDisposable
{
    private readonly string _tempDir;
    private readonly List<string> _tempFiles = new();
    private static readonly System.Random _random = new();

    public LineExtractionTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"LineExtractionTests_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        foreach (var file in _tempFiles)
        {
            try { File.Delete(file); } catch { }
        }
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    private string CreateTempFile(string[] lines)
    {
        var path = Path.Combine(_tempDir, $"test_{Guid.NewGuid():N}.do");
        File.WriteAllLines(path, lines);
        _tempFiles.Add(path);
        return path;
    }

    private string CreateTempFile(string content)
    {
        var path = Path.Combine(_tempDir, $"test_{Guid.NewGuid():N}.do");
        File.WriteAllText(path, content);
        _tempFiles.Add(path);
        return path;
    }

    // ============================================================================
    // Property 4: Upward Bounds Extraction
    // For any valid file and row number, the GetUpwardLines function SHALL return
    // bounds where:
    // - start_line equals 1
    // - end_line is greater than or equal to the input row
    // - If the line at input row ends with ///, end_line extends to include the
    //   complete statement
    // **Validates: Requirements 3.1, 3.2, 3.5**
    // ============================================================================

    /// <summary>
    /// Feature: stata-zed-tasks, Property 4: Upward Bounds Extraction
    /// Upward lines always start from line 1.
    /// </summary>
    [Property(MaxTest = 100)]
    public Property UpwardLinesAlwaysStartFromLine1()
    {
        return Prop.ForAll(
            Arb.From<PositiveInt>().Filter(n => n.Get >= 3 && n.Get <= 12),
            numLines =>
            {
                var lines = Enumerable.Range(1, numLines.Get)
                    .Select(i => $"display \"line {i}\"")
                    .ToArray();
                var file = CreateTempFile(lines);
                var row = _random.Next(1, numLines.Get + 1);

                var output = Program.GetUpwardLines(file, row);
                var firstLine = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();

                return (firstLine == lines[0])
                    .Label($"Row: {row}, First output line: {firstLine}, Expected: {lines[0]}");
            });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 4: Upward includes at least up to cursor row
    /// </summary>
    [Property(MaxTest = 100)]
    public Property UpwardLinesIncludeAtLeastUpToCursorRow()
    {
        return Prop.ForAll(
            Arb.From<PositiveInt>().Filter(n => n.Get >= 3 && n.Get <= 12),
            numLines =>
            {
                var lines = Enumerable.Range(1, numLines.Get)
                    .Select(i => $"display \"line {i}\"")
                    .ToArray();
                var file = CreateTempFile(lines);
                var row = _random.Next(1, numLines.Get + 1);

                var output = Program.GetUpwardLines(file, row);
                var outputLines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).Length;

                return (outputLines >= row)
                    .Label($"Row: {row}, Output lines: {outputLines}");
            });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 4: Upward extends forward for continuations
    /// </summary>
    [Property(MaxTest = 100)]
    public Property UpwardExtendsForwardForContinuations()
    {
        return Prop.ForAll(
            Arb.From<PositiveInt>().Filter(n => n.Get >= 2 && n.Get <= 4),
            contLength =>
            {
                // Create file with continuation at line 2
                var lines = new List<string> { "display \"line 1\"" };
                for (int i = 0; i < contLength.Get - 1; i++)
                {
                    lines.Add($"local x{i} = {i} ///");
                }
                lines.Add($"local x{contLength.Get - 1} = {contLength.Get - 1}");
                lines.Add("display \"last\"");

                var file = CreateTempFile(lines.ToArray());
                var row = 2; // First line of continuation

                var output = Program.GetUpwardLines(file, row);
                var outputLines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).Length;

                // Should include all continuation lines (1 + contLength)
                var expectedMin = 1 + contLength.Get;
                return (outputLines >= expectedMin)
                    .Label($"Continuation length: {contLength.Get}, Output lines: {outputLines}, Expected min: {expectedMin}");
            });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 4: Upward preserves line breaks
    /// </summary>
    [Property(MaxTest = 100)]
    public Property UpwardPreservesLineBreaks()
    {
        return Prop.ForAll(
            Arb.From<PositiveInt>().Filter(n => n.Get >= 3 && n.Get <= 10),
            numLines =>
            {
                var lines = Enumerable.Range(1, numLines.Get)
                    .Select(i => $"display \"line {i}\"")
                    .ToArray();
                var file = CreateTempFile(lines);
                var row = numLines.Get; // Get all lines

                var output = Program.GetUpwardLines(file, row);
                var outputLines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

                var allMatch = outputLines.Length == lines.Length &&
                    outputLines.Zip(lines, (a, b) => a == b).All(x => x);

                return allMatch.Label($"Lines match: {allMatch}");
            });
    }

    // ============================================================================
    // Property 5: Downward Bounds Extraction
    // For any valid file and row number, the GetDownwardLines function SHALL return
    // bounds where:
    // - start_line is less than or equal to the input row
    // - end_line equals the last line of the file
    // - If the line before input row ends with ///, start_line is adjusted to the
    //   statement start
    // **Validates: Requirements 4.1, 4.2, 4.5**
    // ============================================================================

    /// <summary>
    /// Feature: stata-zed-tasks, Property 5: Downward Bounds Extraction
    /// Downward lines always end at last line.
    /// </summary>
    [Property(MaxTest = 100)]
    public Property DownwardLinesAlwaysEndAtLastLine()
    {
        return Prop.ForAll(
            Arb.From<PositiveInt>().Filter(n => n.Get >= 3 && n.Get <= 12),
            numLines =>
            {
                var lines = Enumerable.Range(1, numLines.Get)
                    .Select(i => $"display \"line {i}\"")
                    .ToArray();
                var file = CreateTempFile(lines);
                var row = _random.Next(1, numLines.Get + 1);

                var output = Program.GetDownwardLines(file, row);
                var lastLine = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).LastOrDefault();

                return (lastLine == lines[^1])
                    .Label($"Row: {row}, Last output line: {lastLine}, Expected: {lines[^1]}");
            });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 5: Downward starts at or before cursor row
    /// </summary>
    [Property(MaxTest = 100)]
    public Property DownwardLinesStartAtOrBeforeCursorRow()
    {
        return Prop.ForAll(
            Arb.From<PositiveInt>().Filter(n => n.Get >= 3 && n.Get <= 12),
            numLines =>
            {
                var lines = Enumerable.Range(1, numLines.Get)
                    .Select(i => $"display \"line {i}\"")
                    .ToArray();
                var file = CreateTempFile(lines);
                var row = _random.Next(1, numLines.Get + 1);

                var output = Program.GetDownwardLines(file, row);
                var outputLines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).Length;

                // Output should have at least (total_lines - row + 1) lines
                var expectedMin = numLines.Get - row + 1;
                return (outputLines >= expectedMin)
                    .Label($"Row: {row}, Total: {numLines.Get}, Output lines: {outputLines}, Expected min: {expectedMin}");
            });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 5: Downward extends backward for continuations
    /// </summary>
    [Property(MaxTest = 100)]
    public Property DownwardExtendsBackwardForContinuations()
    {
        return Prop.ForAll(
            Arb.From<PositiveInt>().Filter(n => n.Get >= 2 && n.Get <= 4),
            contLength =>
            {
                // Create file with continuation starting at line 2
                var lines = new List<string> { "display \"line 1\"" };
                for (int i = 0; i < contLength.Get - 1; i++)
                {
                    lines.Add($"local x{i} = {i} ///");
                }
                lines.Add($"local x{contLength.Get - 1} = {contLength.Get - 1}");
                lines.Add("display \"last\"");

                var file = CreateTempFile(lines.ToArray());
                var row = 1 + contLength.Get; // Last line of continuation

                var output = Program.GetDownwardLines(file, row);
                var firstLine = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();

                // Should start from line 2 (first line of continuation)
                return (firstLine == lines[1])
                    .Label($"Row: {row}, First output line: {firstLine}, Expected: {lines[1]}");
            });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 5: Downward preserves line breaks
    /// </summary>
    [Property(MaxTest = 100)]
    public Property DownwardPreservesLineBreaks()
    {
        return Prop.ForAll(
            Arb.From<PositiveInt>().Filter(n => n.Get >= 3 && n.Get <= 10),
            numLines =>
            {
                var lines = Enumerable.Range(1, numLines.Get)
                    .Select(i => $"display \"line {i}\"")
                    .ToArray();
                var file = CreateTempFile(lines);
                var row = 1; // Get all lines

                var output = Program.GetDownwardLines(file, row);
                var outputLines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

                var allMatch = outputLines.Length == lines.Length &&
                    outputLines.Zip(lines, (a, b) => a == b).All(x => x);

                return allMatch.Label($"Lines match: {allMatch}");
            });
    }

    // ============================================================================
    // Unit Tests for Edge Cases
    // ============================================================================

    [Fact]
    public void GetUpwardLines_SingleLineFile()
    {
        var file = CreateTempFile(new[] { "display 1" });
        var output = Program.GetUpwardLines(file, 1);
        Assert.Equal("display 1", output);
    }

    [Fact]
    public void GetUpwardLines_CursorOnFirstLine()
    {
        var file = CreateTempFile(new[] { "line 1", "line 2", "line 3" });
        var output = Program.GetUpwardLines(file, 1);
        Assert.Equal("line 1", output);
    }

    [Fact]
    public void GetUpwardLines_CursorOnLastLine()
    {
        var file = CreateTempFile(new[] { "line 1", "line 2", "line 3" });
        var output = Program.GetUpwardLines(file, 3);
        var expected = "line 1" + Environment.NewLine + "line 2" + Environment.NewLine + "line 3";
        Assert.Equal(expected, output);
    }

    [Fact]
    public void GetUpwardLines_ExtendsThroughContinuation()
    {
        var file = CreateTempFile(new[] { "line 1", "local x = 1 ///", "    + 2 ///", "    + 3", "line 5" });
        var output = Program.GetUpwardLines(file, 2);
        var outputLines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal(4, outputLines.Length);
    }

    [Fact]
    public void GetUpwardLines_RowOutOfBounds()
    {
        var file = CreateTempFile(new[] { "line 1", "line 2" });
        Assert.Throws<ArgumentOutOfRangeException>(() => Program.GetUpwardLines(file, 5));
    }

    [Fact]
    public void GetUpwardLines_FileNotFound()
    {
        Assert.Throws<FileNotFoundException>(() => Program.GetUpwardLines("/nonexistent/file.do", 1));
    }

    [Fact]
    public void GetDownwardLines_SingleLineFile()
    {
        var file = CreateTempFile(new[] { "display 1" });
        var output = Program.GetDownwardLines(file, 1);
        Assert.Equal("display 1", output);
    }

    [Fact]
    public void GetDownwardLines_CursorOnFirstLine()
    {
        var file = CreateTempFile(new[] { "line 1", "line 2", "line 3" });
        var output = Program.GetDownwardLines(file, 1);
        var expected = "line 1" + Environment.NewLine + "line 2" + Environment.NewLine + "line 3";
        Assert.Equal(expected, output);
    }

    [Fact]
    public void GetDownwardLines_CursorOnLastLine()
    {
        var file = CreateTempFile(new[] { "line 1", "line 2", "line 3" });
        var output = Program.GetDownwardLines(file, 3);
        Assert.Equal("line 3", output);
    }

    [Fact]
    public void GetDownwardLines_ExtendsBackwardThroughContinuation()
    {
        var file = CreateTempFile(new[] { "line 1", "local x = 1 ///", "    + 2 ///", "    + 3", "line 5" });
        var output = Program.GetDownwardLines(file, 4);
        var outputLines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal(4, outputLines.Length);
        Assert.Equal("local x = 1 ///", outputLines[0]);
    }

    [Fact]
    public void GetDownwardLines_RowOutOfBounds()
    {
        var file = CreateTempFile(new[] { "line 1", "line 2" });
        Assert.Throws<ArgumentOutOfRangeException>(() => Program.GetDownwardLines(file, 5));
    }

    [Fact]
    public void GetDownwardLines_FileNotFound()
    {
        Assert.Throws<FileNotFoundException>(() => Program.GetDownwardLines("/nonexistent/file.do", 1));
    }
}
