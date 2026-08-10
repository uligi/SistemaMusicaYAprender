using System.Security.Cryptography;
using MusicaAprender.Modules.Security.Infrastructure.Authentication;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class SecuritySessionTokenServiceTests
{
    [Fact]
    public void CreateTokenUsesOpaqueBase64UrlMaterial()
    {
        var first = SecuritySessionTokenService.CreateToken();
        var second = SecuritySessionTokenService.CreateToken();

        Assert.Equal(SecuritySessionTokenService.EncodedTokenLength, first.Length);
        Assert.Matches("^[A-Za-z0-9_-]+$", first);
        Assert.NotEqual(first, second);
    }

    [Fact]
    public void TryHashTokenIsDeterministicWithoutPersistingTheToken()
    {
        var token = SecuritySessionTokenService.CreateToken();

        Assert.True(SecuritySessionTokenService.TryHashToken(token, out var firstHash));
        Assert.True(SecuritySessionTokenService.TryHashToken(token, out var secondHash));

        try
        {
            Assert.Equal(32, firstHash.Length);
            Assert.Equal(firstHash, secondHash);
            Assert.DoesNotContain(token, Convert.ToHexString(firstHash), StringComparison.Ordinal);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(firstHash);
            CryptographicOperations.ZeroMemory(secondHash);
        }
    }

    [Theory]
    [InlineData("")]
    [InlineData("not-base64url")]
    [InlineData("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa+")]
    public void TryHashTokenRejectsMalformedMaterial(string token)
    {
        Assert.False(SecuritySessionTokenService.TryHashToken(token, out var hash));
        Assert.Empty(hash);
    }
}
