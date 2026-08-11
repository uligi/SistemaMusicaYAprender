using System.Security.Cryptography;
using MusicaAprender.Modules.Security.Infrastructure.Mfa;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class TotpServiceTests
{
    [Fact]
    public void Base32RoundTripPreservesSecret()
    {
        var secret = Enumerable.Range(1, 20)
            .Select(static value => (byte)value)
            .ToArray();

        var encoded = TotpService.EncodeBase32(secret);
        var decoded = TotpService.DecodeBase32(encoded);

        try
        {
            Assert.Equal(secret, decoded);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
            CryptographicOperations.ZeroMemory(decoded);
        }
    }

    [Fact]
    public void GenerateCodeMatchesRfc6238Sha1VectorAtSixDigits()
    {
        var secret =
            System.Text.Encoding.ASCII.GetBytes(
                "12345678901234567890");

        try
        {
            var code = TotpService.GenerateCode(
                secret,
                DateTimeOffset.FromUnixTimeSeconds(59));

            Assert.Equal("287082", code);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
        }
    }

    [Fact]
    public void VerifyAcceptsCurrentCodeAndRejectsDifferentCode()
    {
        var secret = Enumerable.Range(11, 20)
            .Select(static value => (byte)value)
            .ToArray();

        try
        {
            var now = DateTimeOffset.FromUnixTimeSeconds(1_756_000_000);
            var code = TotpService.GenerateCode(secret, now);

            Assert.True(TotpService.Verify(secret, code, now).Valid);

            var different =
                code == "000000"
                    ? "000001"
                    : "000000";

            Assert.False(
                TotpService.Verify(secret, different, now).Valid);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
        }
    }

    [Fact]
    public void VerifyAllowsOnlyConfiguredClockTolerance()
    {
        var secret = Enumerable.Range(21, 20)
            .Select(static value => (byte)value)
            .ToArray();

        try
        {
            var now = DateTimeOffset.FromUnixTimeSeconds(1_756_000_000);
            var previousCode = TotpService.GenerateCode(
                secret,
                now.AddSeconds(-TotpService.PeriodSeconds));

            Assert.True(
                TotpService.Verify(secret, previousCode, now).Valid);

            var oldCode = TotpService.GenerateCode(
                secret,
                now.AddSeconds(-TotpService.PeriodSeconds * 2));

            Assert.False(
                TotpService.Verify(secret, oldCode, now).Valid);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
        }
    }
}
