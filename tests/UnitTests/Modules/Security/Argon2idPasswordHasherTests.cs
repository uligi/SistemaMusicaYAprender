using MusicaAprender.Modules.Security.Infrastructure.Credentials;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class Argon2idPasswordHasherTests
{
    private static readonly Argon2idPasswordHashingOptions TestOptions =
        new(19 * 1024, 2, 1, 16, 32);

    [Fact]
    public void CreateCredentialUsesUniqueSaltAndVersionedParameters()
    {
        var hasher = new Argon2idPasswordHasher(TestOptions);

        var first = hasher.CreateCredential("Brisa japonesa segura 2026");
        var second = hasher.CreateCredential("Brisa japonesa segura 2026");

        Assert.Equal(Argon2idPasswordHasher.Algorithm, first.Algorithm);
        Assert.NotEqual(first.Hash, second.Hash);
        Assert.NotEqual(first.Parameters, second.Parameters);
        Assert.Contains("\"v\":19", first.Parameters, StringComparison.Ordinal);
        Assert.Contains("\"policy\":\"PASSWORD_V1_2026-08-10\"", first.Parameters, StringComparison.Ordinal);
        Assert.DoesNotContain("Brisa", first.Hash, StringComparison.Ordinal);
        Assert.DoesNotContain("Brisa", first.Parameters, StringComparison.Ordinal);
    }

    [Fact]
    public void VerifyAcceptsCanonicalEquivalentAndRejectsWrongValue()
    {
        var hasher = new Argon2idPasswordHasher(TestOptions);
        var credential = hasher.CreateCredential("café con espacio seguro 2026");

        var valid = Argon2idPasswordHasher.Verify(
            "cafe\u0301 con espacio seguro 2026",
            credential.Algorithm,
            credential.Hash,
            credential.Parameters);
        var invalid = Argon2idPasswordHasher.Verify(
            "otra contraseña segura 2026",
            credential.Algorithm,
            credential.Hash,
            credential.Parameters);

        Assert.True(valid);
        Assert.False(invalid);
    }

    [Fact]
    public void VerifyRejectsUnsupportedOrMalformedStoredMaterial()
    {
        Assert.False(Argon2idPasswordHasher.Verify(
            "Brisa japonesa segura 2026",
            "PBKDF2",
            "bad",
            "{}"));
        Assert.False(Argon2idPasswordHasher.Verify(
            "Brisa japonesa segura 2026",
            "ARGON2ID",
            "bad",
            "{}"));
    }

    [Fact]
    public void ConstructorRejectsParametersBelowApprovedFloor()
    {
        Assert.Throws<ArgumentOutOfRangeException>(
            () => new Argon2idPasswordHasher(new Argon2idPasswordHashingOptions(1024, 1)));
    }
}
