using System.Security.Cryptography;
using System.Text;
using MusicaAprender.Modules.Security.Infrastructure.Verification;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class AccountVerificationTokenServiceTests
{
    private static readonly byte[] Key =
        Convert.FromHexString("00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF");

    [Fact]
    public void CreateTokenRoundTripsSignedIdentifiersAndHash()
    {
        var service = new AccountVerificationTokenService(Key);
        var accountId = Guid.Parse("0198a987-13bb-7efc-8acf-1d562537bc53");
        var verificationId = Guid.Parse("0198a987-14cc-7451-a1b4-4ea04ff77aae");

        var token = service.CreateToken(accountId, verificationId);
        var parsed = service.TryReadToken(token, out var claims);

        Assert.True(parsed);
        Assert.NotNull(claims);
        Assert.Equal(86, token.Length);
        Assert.Matches("^[A-Za-z0-9_-]+$", token);
        Assert.Equal(accountId, claims.AccountId);
        Assert.Equal(verificationId, claims.VerificationId);
        Assert.Equal(SHA256.HashData(Encoding.ASCII.GetBytes(token)), claims.TokenHash.ToArray());
    }

    [Fact]
    public void TryReadTokenRejectsTamperedMaterial()
    {
        var service = new AccountVerificationTokenService(Key);
        var token = service.CreateToken(Guid.CreateVersion7(), Guid.CreateVersion7());
        var replacement = token[^1] == 'A' ? 'B' : 'A';
        var tampered = token[..^1] + replacement;

        var parsed = service.TryReadToken(tampered, out var claims);

        Assert.False(parsed);
        Assert.Null(claims);
    }

    [Fact]
    public void ConstructorRejectsKeysWithUnexpectedLength()
    {
        Assert.Throws<ArgumentException>(
            () => new AccountVerificationTokenService(new byte[31]));
    }
}
