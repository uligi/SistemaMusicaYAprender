namespace MusicaAprender.Modules.Security.Infrastructure.Authorization;

public static class AuthorizationScopeMatcher
{
    public static bool Matches(
        AuthorizationScope required,
        string? storedScopeType,
        string? storedModuleCode,
        Guid? storedObjectId)
    {
        ArgumentNullException.ThrowIfNull(required);

        if (storedScopeType is null)
        {
            return true;
        }

        var scopeType = storedScopeType.Trim().ToUpperInvariant();
        var moduleCode = storedModuleCode?.Trim().ToUpperInvariant();

        return scopeType switch
        {
            "GLOBAL" =>
                moduleCode is null
                && storedObjectId is null,

            "MODULE" =>
                storedObjectId is null
                && moduleCode is not null
                && AuthorizationCode.IsValid(moduleCode)
                && required.Kind is AuthorizationScopeKind.Module
                    or AuthorizationScopeKind.Target
                && string.Equals(
                    moduleCode,
                    required.ModuleCode,
                    StringComparison.Ordinal),

            "OBJECT" =>
                storedObjectId is { } objectId
                && objectId != Guid.Empty
                && required.Kind == AuthorizationScopeKind.Target
                && required.ObjectId == objectId
                && (moduleCode is null
                    || AuthorizationCode.IsValid(moduleCode)
                    && string.Equals(
                        moduleCode,
                        required.ModuleCode,
                        StringComparison.Ordinal)),

            _ => false
        };
    }
}
