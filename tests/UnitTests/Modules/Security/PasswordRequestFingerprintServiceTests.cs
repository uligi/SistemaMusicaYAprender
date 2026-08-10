using System.Security.Cryptography;
using System.Text;
using MusicaAprender.Modules.Security.Infrastructure.Credentials;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class PasswordRequestFingerprintServiceTests
{
    private static readonly byte[] Key = SHA256.HashData(
        Encoding.ASCII.GetBytes("BL-MVP-028 unit-test key"));

    [Fact]
    public void CreateFingerprintIsStableKeyedAndDoesNotExposePlaintext()
    {
        var service = new PasswordRequestFingerprintService(Key);

        var first = service.CreateFingerprint("Brisa japonesa segura 2026");
        var replay = service.CreateFingerprint("Brisa japonesa segura 2026");
        var changed = service.CreateFingerprint("Brisa japonesa segura 2027");

        Assert.Equal(first, replay);
        Assert.NotEqual(first, changed);
        Assert.Equal(32, first.Length);
        Assert.DoesNotContain(
            "Brisa",
            Convert.ToHexString(first),
            StringComparison.OrdinalIgnoreCase);
    }
}
