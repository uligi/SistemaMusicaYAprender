using MusicaAprender.Modules.Security.Infrastructure.Audit;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class PrimaryAuditCorrelationTests
{
    [Fact]
    public void ResolvePreservesUuidCorrelation()
    {
        var expected = Guid.Parse(
            "1ee97d77-8a55-47ff-8f24-d2655e71864f");

        var actual = PrimaryAuditCorrelation.Resolve(
            expected.ToString("D"));

        Assert.Equal(expected, actual);
    }

    [Fact]
    public void ResolveHashesNonUuidCorrelationDeterministically()
    {
        const string value = "01J-audit-correlation-safe";

        var first = PrimaryAuditCorrelation.Resolve(value);
        var second = PrimaryAuditCorrelation.Resolve(value);

        Assert.NotEqual(Guid.Empty, first);
        Assert.Equal(first, second);
    }

    [Fact]
    public void ResolveObjectIdSeparatesCanonicalObjects()
    {
        var global = PrimaryAuditCorrelation.ResolveObjectId(
            "AUTHORIZATION_SCOPE|Global|GLOBAL|-");
        var module = PrimaryAuditCorrelation.ResolveObjectId(
            "AUTHORIZATION_SCOPE|Module|M18|-");

        Assert.NotEqual(Guid.Empty, global);
        Assert.NotEqual(Guid.Empty, module);
        Assert.NotEqual(global, module);
    }
}
