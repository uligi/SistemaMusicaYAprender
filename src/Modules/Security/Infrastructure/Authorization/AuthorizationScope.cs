namespace MusicaAprender.Modules.Security.Infrastructure.Authorization;

public enum AuthorizationScopeKind
{
    Global,
    Module,
    Target
}

public sealed record AuthorizationScope
{
    private AuthorizationScope(
        AuthorizationScopeKind kind,
        string? moduleCode,
        Guid? objectId)
    {
        Kind = kind;
        ModuleCode = moduleCode;
        ObjectId = objectId;
    }

    public AuthorizationScopeKind Kind { get; }

    public string? ModuleCode { get; }

    public Guid? ObjectId { get; }

    public static AuthorizationScope Global { get; } =
        new(AuthorizationScopeKind.Global, null, null);

    public static AuthorizationScope ForModule(string moduleCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(moduleCode);

        var normalized = moduleCode.Trim().ToUpperInvariant();
        if (!AuthorizationCode.IsValid(normalized))
        {
            throw new ArgumentException(
                "ModuleCode debe usar el formato seguro [A-Z0-9][A-Z0-9._-]*.",
                nameof(moduleCode));
        }

        return new AuthorizationScope(
            AuthorizationScopeKind.Module,
            normalized,
            null);
    }

    public static AuthorizationScope ForObject(
        string moduleCode,
        Guid objectId)
    {
        if (objectId == Guid.Empty)
        {
            throw new ArgumentException(
                "ObjectId no puede ser Guid.Empty.",
                nameof(objectId));
        }

        var module = ForModule(moduleCode);
        return new AuthorizationScope(
            AuthorizationScopeKind.Target,
            module.ModuleCode,
            objectId);
    }
}

internal static class AuthorizationCode
{
    public static bool IsValid(string value)
    {
        if (value.Length is < 1 or > 64
            || !IsUpperAsciiLetterOrDigit(value[0]))
        {
            return false;
        }

        for (var index = 1; index < value.Length; index++)
        {
            var character = value[index];
            if (!(IsUpperAsciiLetterOrDigit(character)
                  || character is '.' or '_' or '-'))
            {
                return false;
            }
        }

        return true;
    }

    private static bool IsUpperAsciiLetterOrDigit(char character) =>
        character is >= 'A' and <= 'Z'
        || char.IsAsciiDigit(character);
}
