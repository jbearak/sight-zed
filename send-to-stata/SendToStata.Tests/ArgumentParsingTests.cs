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

