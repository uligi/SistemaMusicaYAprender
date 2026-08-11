using System.Security.Cryptography;
using MusicaAprender.Modules.Security.Infrastructure.Authentication;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class LoginAbuseFingerprintServiceTests
{
    [Fact]
    public void FingerprintsAreDeterministicAndPurposeSeparated()
    {
        var key = Enumerable.Range(0, 32).Select(static value => (byte)value).ToArray();
        var emailLookupHash = SHA256.HashData("student@example.test"u8);
        var service = new LoginAbuseFingerprintService(key);

        var firstAccount = service.CreateAccountFingerprint(emailLookupHash);
        var secondAccount = service.CreateAccountFingerprint(emailLookupHash);
        var client = service.CreateClientFingerprint("192.0.2.10");

        Assert.Equal(32, firstAccount.Length);
        Assert.Equal(firstAccount, secondAccount);
        Assert.NotEqual(firstAccount, client);
    }

    [Fact]
    public void ClientFingerprintCanonicalizesMappedIpv4()
    {
        var service = new LoginAbuseFingerprintService(new byte[32]);

        var ipv4 = service.CreateClientFingerprint("192.0.2.25");
        var mapped = service.CreateClientFingerprint("::ffff:192.0.2.25");

        Assert.Equal(ipv4, mapped);
    }
}
