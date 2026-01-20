using FsCheck;
using FsCheck.Xunit;
using SendToStata;
using Xunit;

namespace SendToStata.Tests;

/// <summary>
/// Property-based tests for path escaping functions.
/// 
/// Property 1: Backslash Doubling
/// Property 2: Quote Detection Sets Compound Flag
/// Property 3: CD Command Formatting
/// 
/// **Validates: Requirements 1.2, 1.3, 2.2, 2.3, 5.1-5.5**
/// </summary>
public class PathEscapingTests
{
    // ============================================================================
    // Property 1: Backslash Doubling
    // For any path string containing backslash characters, the EscapePathForStata
    // function SHALL return an escaped string where every backslash is doubled.
    // **Validates: Requirements 1.3, 2.3, 5.3**
    // ============================================================================

    /// <summary>
    /// Feature: stata-zed-tasks, Property 1: Backslash Doubling
    /// For any path, the number of backslashes in the escaped output should be
    /// exactly double the number in the input.
    /// </summary>
    [Property(MaxTest = 100)]
    public Property BackslashesAreDoubled()
    {
        return Prop.ForAll(Arb.From<NonNull<string>>(), path =>
        {
            var input = path.Get;
            var result = Program.EscapePathForStata(input);
            
            var originalCount = input.Count(c => c == '\\');
            var escapedCount = result.Escaped.Count(c => c == '\\');
            
            return (escapedCount == originalCount * 2)
                .Label($"Input backslashes: {originalCount}, Escaped backslashes: {escapedCount}");
        });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 1: Single backslash becomes double
    /// </summary>
    [Property(MaxTest = 100)]
    public Property SingleBackslashBecomesDouble()
    {
        return Prop.ForAll(
            Arb.From<NonEmptyString>(),
            Arb.From<NonEmptyString>(),
            (prefix, suffix) =>
            {
                var input = $"{prefix.Get}\\{suffix.Get}";
                var result = Program.EscapePathForStata(input);
                
                return result.Escaped.Contains("\\\\")
                    .Label($"Input: {input}, Escaped: {result.Escaped}");
            });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 1: Path without backslashes is unchanged
    /// </summary>
    [Property(MaxTest = 100)]
    public Property PathWithoutBackslashesUnchanged()
    {
        var pathWithoutBackslashes = Arb.From<NonNull<string>>()
            .Filter(s => !s.Get.Contains('\\'));
        
        return Prop.ForAll(pathWithoutBackslashes, path =>
        {
            var result = Program.EscapePathForStata(path.Get);
            return (result.Escaped == path.Get)
                .Label($"Input: {path.Get}, Escaped: {result.Escaped}");
        });
    }

    // ============================================================================
    // Property 2: Quote Detection Sets Compound Flag
    // For any path string, the EscapePathForStata function SHALL set
    // UseCompound = true if and only if the path contains at least one double quote.
    // **Validates: Requirements 1.2, 2.2, 5.2**
    // ============================================================================

    /// <summary>
    /// Feature: stata-zed-tasks, Property 2: Quote Detection Sets Compound Flag
    /// Paths with quotes should set UseCompound to true.
    /// </summary>
    [Property(MaxTest = 100)]
    public Property PathsWithQuotesSetUseCompoundTrue()
    {
        var pathWithQuotes = Arb.From<NonNull<string>>()
            .Filter(s => s.Get.Contains('"'));
        
        return Prop.ForAll(pathWithQuotes, path =>
        {
            var result = Program.EscapePathForStata(path.Get);
            return result.UseCompound
                .Label($"Path with quote: {path.Get}, UseCompound: {result.UseCompound}");
        });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 2: Paths without quotes set UseCompound to false
    /// </summary>
    [Property(MaxTest = 100)]
    public Property PathsWithoutQuotesSetUseCompoundFalse()
    {
        var pathWithoutQuotes = Arb.From<NonNull<string>>()
            .Filter(s => !s.Get.Contains('"'));
        
        return Prop.ForAll(pathWithoutQuotes, path =>
        {
            var result = Program.EscapePathForStata(path.Get);
            return (!result.UseCompound)
                .Label($"Path without quote: {path.Get}, UseCompound: {result.UseCompound}");
        });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 2: Quote detection is independent of backslashes
    /// </summary>
    [Property(MaxTest = 100)]
    public Property QuoteDetectionWorksWithBackslashesPresent()
    {
        return Prop.ForAll(
            Arb.From<NonEmptyString>(),
            Arb.From<PositiveInt>(),
            (segment, num) =>
            {
                // Create path with both backslashes and quotes
                var input = $"C:\\Users\\test\"{num.Get}\\data";
                var result = Program.EscapePathForStata(input);
                
                return result.UseCompound
                    .Label($"Path with both: {input}, UseCompound: {result.UseCompound}");
            });
    }

    // ============================================================================
    // Property 3: CD Command Formatting
    // For any directory path, the FormatCdCommand function SHALL:
    // - Return cd `"<escaped_path>"' when the path contains double quotes
    // - Return cd "<escaped_path>" when the path does not contain double quotes
    // **Validates: Requirements 5.4, 5.5**
    // ============================================================================

    /// <summary>
    /// Feature: stata-zed-tasks, Property 3: CD Command Formatting
    /// Paths with quotes should use compound string syntax.
    /// </summary>
    [Property(MaxTest = 100)]
    public Property PathsWithQuotesUseCompoundStringSyntax()
    {
        var pathWithQuotes = Arb.From<NonNull<string>>()
            .Filter(s => s.Get.Contains('"') && !s.Get.Contains('\n') && !s.Get.Contains('\r'));
        
        return Prop.ForAll(pathWithQuotes, path =>
        {
            var cmd = Program.FormatCdCommand(path.Get);
            
            // Should start with cd `" and end with "'
            var startsCorrectly = cmd.StartsWith("cd `\"");
            var endsCorrectly = cmd.EndsWith("\"'");
            
            return (startsCorrectly && endsCorrectly)
                .Label($"Path: {path.Get}, Command: {cmd}");
        });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 3: Paths without quotes use regular syntax
    /// </summary>
    [Property(MaxTest = 100)]
    public Property PathsWithoutQuotesUseRegularStringSyntax()
    {
        var pathWithoutQuotes = Arb.From<NonNull<string>>()
            .Filter(s => !s.Get.Contains('"') && !s.Get.Contains('\n') && !s.Get.Contains('\r'));
        
        return Prop.ForAll(pathWithoutQuotes, path =>
        {
            var cmd = Program.FormatCdCommand(path.Get);
            
            // Should start with cd " and end with "
            // Should NOT contain backtick
            var startsCorrectly = cmd.StartsWith("cd \"");
            var endsCorrectly = cmd.EndsWith("\"");
            var noBacktick = !cmd.Contains('`');
            var noSingleQuoteAtEnd = !cmd.EndsWith("'");
            
            return (startsCorrectly && endsCorrectly && noBacktick && noSingleQuoteAtEnd)
                .Label($"Path: {path.Get}, Command: {cmd}");
        });
    }

    /// <summary>
    /// Feature: stata-zed-tasks, Property 3: Backslashes are doubled in cd command
    /// </summary>
    [Property(MaxTest = 100)]
    public Property BackslashesAreDoubledInCdCommand()
    {
        var pathWithBackslashes = Arb.From<NonNull<string>>()
            .Filter(s => s.Get.Contains('\\') && !s.Get.Contains('\n') && !s.Get.Contains('\r'));
        
        return Prop.ForAll(pathWithBackslashes, path =>
        {
            var originalCount = path.Get.Count(c => c == '\\');
            var cmd = Program.FormatCdCommand(path.Get);
            var cmdCount = cmd.Count(c => c == '\\');
            
            return (cmdCount == originalCount * 2)
                .Label($"Path backslashes: {originalCount}, Command backslashes: {cmdCount}");
        });
    }

    // ============================================================================
    // Unit Tests for Edge Cases
    // ============================================================================

    [Fact]
    public void EscapePathForStata_EmptyPath()
    {
        var result = Program.EscapePathForStata("");
        Assert.Equal("", result.Escaped);
        Assert.False(result.UseCompound);
    }

    [Fact]
    public void EscapePathForStata_PathWithOnlyBackslashes()
    {
        var result = Program.EscapePathForStata("\\\\");
        Assert.Equal("\\\\\\\\", result.Escaped);
        Assert.False(result.UseCompound);
    }

    [Fact]
    public void EscapePathForStata_PathWithOnlyQuotes()
    {
        var result = Program.EscapePathForStata("\"\"");
        Assert.Equal("\"\"", result.Escaped);
        Assert.True(result.UseCompound);
    }

    [Fact]
    public void FormatCdCommand_SimpleWindowsPath()
    {
        var cmd = Program.FormatCdCommand("C:\\Users\\test");
        Assert.Equal("cd \"C:\\\\Users\\\\test\"", cmd);
    }

    [Fact]
    public void FormatCdCommand_PathWithDoubleQuote()
    {
        var cmd = Program.FormatCdCommand("C:\\Users\\test\"dir");
        Assert.Equal("cd `\"C:\\\\Users\\\\test\"dir\"'", cmd);
    }

    [Fact]
    public void FormatCdCommand_PathWithSpaces()
    {
        var cmd = Program.FormatCdCommand("C:\\My Documents\\data");
        Assert.Equal("cd \"C:\\\\My Documents\\\\data\"", cmd);
    }

    [Fact]
    public void FormatCdCommand_UnixPath()
    {
        var cmd = Program.FormatCdCommand("/Users/test/data");
        Assert.Equal("cd \"/Users/test/data\"", cmd);
    }
}
