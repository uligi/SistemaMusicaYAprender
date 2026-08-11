using MusicaAprender.Modules.Security.Infrastructure.Authorization;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Security;

public sealed class AuthorizationScopeMatcherTests
{
    [Fact]
    public void UnscopedAssignmentGrantsGlobalModuleAndTargetScopes()
    {
        Assert.True(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.Global,
            null,
            null,
            null));

        Assert.True(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.ForModule("EDITORIAL"),
            null,
            null,
            null));

        Assert.True(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.ForObject(
                "EDITORIAL",
                Guid.NewGuid()),
            null,
            null,
            null));
    }

    [Fact]
    public void ModuleAssignmentIsNotGlobal()
    {
        Assert.False(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.Global,
            "MODULE",
            "EDITORIAL",
            null));
    }

    [Fact]
    public void ModuleAssignmentGrantsOnlyItsModuleAndTargets()
    {
        var objectId = Guid.NewGuid();

        Assert.True(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.ForModule("EDITORIAL"),
            "MODULE",
            "EDITORIAL",
            null));

        Assert.True(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.ForObject(
                "EDITORIAL",
                objectId),
            "MODULE",
            "EDITORIAL",
            null));

        Assert.False(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.ForObject(
                "CONTENT",
                objectId),
            "MODULE",
            "EDITORIAL",
            null));
    }

    [Fact]
    public void TargetAssignmentRequiresExactTarget()
    {
        var allowed = Guid.NewGuid();
        var other = Guid.NewGuid();

        Assert.True(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.ForObject(
                "EDITORIAL",
                allowed),
            "OBJECT",
            "EDITORIAL",
            allowed));

        Assert.False(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.ForObject(
                "EDITORIAL",
                other),
            "OBJECT",
            "EDITORIAL",
            allowed));
    }

    [Fact]
    public void UnknownOrMalformedScopeFailsClosed()
    {
        Assert.False(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.ForModule("EDITORIAL"),
            "EXPRESSION",
            "EDITORIAL",
            null));

        Assert.False(AuthorizationScopeMatcher.Matches(
            AuthorizationScope.Global,
            "GLOBAL",
            "EDITORIAL",
            null));
    }
}
