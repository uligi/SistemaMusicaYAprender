using MusicaAprender.Modules.Security.Infrastructure.Credentials;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class PasswordPolicyTests
{
    [Fact]
    public void ValidateAcceptsSpacesUnicodeAndNoCompositionRule()
    {
        var result = PasswordPolicy.Validate("frase 日本語 larga y tranquila");

        Assert.True(result.IsValid);
        Assert.Equal(PasswordValidationError.None, result.Error);
        Assert.Equal("frase 日本語 larga y tranquila", result.NormalizedPassword);
    }

    [Theory]
    [InlineData("short", PasswordValidationError.TooShort)]
    [InlineData("correcthorsebatterystaple", PasswordValidationError.Blocked)]
    public void ValidateRejectsLengthAndBlockedValues(
        string candidate,
        PasswordValidationError expectedError)
    {
        var result = PasswordPolicy.Validate(candidate);

        Assert.False(result.IsValid);
        Assert.Equal(expectedError, result.Error);
        Assert.Null(result.NormalizedPassword);
    }

    [Fact]
    public void ValidateCountsUnicodeCodePointsAndNormalizesToNfc()
    {
        var decomposed = "cafe\u0301 con espacio seguro 2026";

        var result = PasswordPolicy.Validate(decomposed);

        Assert.True(result.IsValid);
        Assert.Equal("café con espacio seguro 2026", result.NormalizedPassword);
    }

    [Fact]
    public void ValidateRejectsMoreThanOneHundredTwentyEightCodePoints()
    {
        var result = PasswordPolicy.Validate(new string('a', PasswordPolicy.MaximumLength + 1));

        Assert.False(result.IsValid);
        Assert.Equal(PasswordValidationError.TooLong, result.Error);
    }
}
