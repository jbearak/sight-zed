using System;
using System.IO;
using Xunit;
using SendToStata;

namespace SendToStata.Tests;

public class ArgumentParsingTests
{
    [Fact]
    public void ParseArguments_ActivateStataFlag_SetsActivateStataTrue()
    {
        var args = new[] { "-ActivateStata" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.ActivateStata);
    }

    [Fact]
    public void ParseArguments_ReturnFocusFlag_PrintsDeprecationWarning()
    {
        var originalError = Console.Error;
        using var stringWriter = new StringWriter();
        Console.SetError(stringWriter);
        
        try
        {
            var args = new[] { "-ReturnFocus" };
            Program.ParseArguments(args);
            
            var output = stringWriter.ToString();
            Assert.Contains("Warning: -ReturnFocus is deprecated", output);
        }
        finally
        {
            Console.SetError(originalError);
        }
    }

    [Theory]
    [InlineData("-ReturnFocus", "-ActivateStata")]
    [InlineData("-ActivateStata", "-ReturnFocus")]
    public void ParseArguments_BothFlags_ActivateStataTakesPrecedence(string first, string second)
    {
        var originalError = Console.Error;
        using var stringWriter = new StringWriter();
        Console.SetError(stringWriter);
        
        try
        {
            var args = new[] { first, second };
            var result = Program.ParseArguments(args);
            
            Assert.True(result.ActivateStata);
            var output = stringWriter.ToString();
            Assert.Contains("Warning: -ReturnFocus is deprecated", output);
        }
        finally
        {
            Console.SetError(originalError);
        }
    }

    [Fact]
    public void ParseArguments_NoFlags_DefaultBehaviorReturnsToZed()
    {
        var args = new string[] { };
        var result = Program.ParseArguments(args);
        
        // Default behavior: ActivateStata should be false, meaning focus returns to Zed
        Assert.False(result.ActivateStata);
    }
}


/// <summary>
/// Tests for CD command mode argument parsing.
/// **Validates: Requirements 1.1, 1.4, 1.5, 2.1, 2.4, 2.5**
/// </summary>
public class CDModeArgumentParsingTests
{
    [Fact]
    public void ParseArguments_CDWorkspaceFlag_SetsCDWorkspaceTrue()
    {
        var args = new[] { "-CDWorkspace", "-Workspace", "/tmp/test" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.CDWorkspace);
        Assert.Equal("/tmp/test", result.Workspace);
    }

    [Fact]
    public void ParseArguments_CDFileFlag_SetsCDFileTrue()
    {
        var args = new[] { "-CDFile", "-File", "/tmp/test.do" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.CDFile);
        Assert.Equal("/tmp/test.do", result.File);
    }

    [Fact]
    public void ParseArguments_WorkspaceParameter_ParsesPath()
    {
        var args = new[] { "-Workspace", "C:\\Users\\test\\project" };
        var result = Program.ParseArguments(args);
        
        Assert.Equal("C:\\Users\\test\\project", result.Workspace);
    }

    [Fact]
    public void ParseArguments_CDWorkspaceWithActivateStata_BothFlagsSet()
    {
        var args = new[] { "-CDWorkspace", "-Workspace", "/tmp", "-ActivateStata" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.CDWorkspace);
        Assert.True(result.ActivateStata);
    }

    [Fact]
    public void ParseArguments_CDFileWithActivateStata_BothFlagsSet()
    {
        var args = new[] { "-CDFile", "-File", "/tmp/test.do", "-ActivateStata" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.CDFile);
        Assert.True(result.ActivateStata);
    }

    [Fact]
    public void ParseArguments_CaseInsensitive_CDWorkspace()
    {
        var args = new[] { "-cdworkspace", "-workspace", "/tmp" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.CDWorkspace);
        Assert.Equal("/tmp", result.Workspace);
    }

    [Fact]
    public void ParseArguments_CaseInsensitive_CDFile()
    {
        var args = new[] { "-cdfile", "-file", "/tmp/test.do" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.CDFile);
        Assert.Equal("/tmp/test.do", result.File);
    }
}


/// <summary>
/// Tests for Upward/Downward mode argument parsing.
/// **Validates: Requirements 3.1, 3.4, 4.1, 4.4**
/// </summary>
public class UpwardDownwardModeArgumentParsingTests
{
    [Fact]
    public void ParseArguments_UpwardFlag_SetsUpwardTrue()
    {
        var args = new[] { "-Upward", "-File", "/tmp/test.do", "-Row", "5" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.Upward);
        Assert.Equal("/tmp/test.do", result.File);
        Assert.Equal(5, result.Row);
    }

    [Fact]
    public void ParseArguments_DownwardFlag_SetsDownwardTrue()
    {
        var args = new[] { "-Downward", "-File", "/tmp/test.do", "-Row", "10" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.Downward);
        Assert.Equal("/tmp/test.do", result.File);
        Assert.Equal(10, result.Row);
    }

    [Fact]
    public void ParseArguments_UpwardWithActivateStata_BothFlagsSet()
    {
        var args = new[] { "-Upward", "-File", "/tmp/test.do", "-Row", "5", "-ActivateStata" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.Upward);
        Assert.True(result.ActivateStata);
    }

    [Fact]
    public void ParseArguments_DownwardWithActivateStata_BothFlagsSet()
    {
        var args = new[] { "-Downward", "-File", "/tmp/test.do", "-Row", "10", "-ActivateStata" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.Downward);
        Assert.True(result.ActivateStata);
    }

    [Fact]
    public void ParseArguments_CaseInsensitive_Upward()
    {
        var args = new[] { "-upward", "-file", "/tmp/test.do", "-row", "5" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.Upward);
        Assert.Equal("/tmp/test.do", result.File);
        Assert.Equal(5, result.Row);
    }

    [Fact]
    public void ParseArguments_CaseInsensitive_Downward()
    {
        var args = new[] { "-downward", "-file", "/tmp/test.do", "-row", "10" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.Downward);
        Assert.Equal("/tmp/test.do", result.File);
        Assert.Equal(10, result.Row);
    }

    [Fact]
    public void ParseArguments_UpwardWithInclude_BothFlagsSet()
    {
        var args = new[] { "-Upward", "-File", "/tmp/test.do", "-Row", "5", "-Include" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.Upward);
        Assert.True(result.Include);
    }

    [Fact]
    public void ParseArguments_DownwardWithInclude_BothFlagsSet()
    {
        var args = new[] { "-Downward", "-File", "/tmp/test.do", "-Row", "10", "-Include" };
        var result = Program.ParseArguments(args);
        
        Assert.True(result.Downward);
        Assert.True(result.Include);
    }
}
