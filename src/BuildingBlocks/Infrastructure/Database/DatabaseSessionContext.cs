namespace MusicaAprender.BuildingBlocks.Infrastructure.Database;

public sealed record DatabaseSessionContext
{
    private DatabaseSessionContext(
        Guid accountId,
        string roleCode,
        string correlationId)
    {
        AccountId = accountId;
        RoleCode = roleCode;
        CorrelationId = correlationId;
    }

    public Guid AccountId { get; }

    public string RoleCode { get; }

    public string CorrelationId { get; }

    public static DatabaseSessionContext Create(
        Guid accountId,
        string roleCode,
        string correlationId)
    {
        if (accountId == Guid.Empty)
        {
            throw new ArgumentException(
                "AccountId no puede ser Guid.Empty.",
                nameof(accountId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(roleCode);
        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);

        var normalizedRole = roleCode.Trim();
        var normalizedCorrelation = correlationId.Trim();

        if (!IsSafeRoleCode(normalizedRole))
        {
            throw new ArgumentException(
                "RoleCode debe usar 1-64 caracteres ASCII en formato [A-Z0-9][A-Z0-9._-]*.",
                nameof(roleCode));
        }

        if (!IsSafeCorrelationId(normalizedCorrelation))
        {
            throw new ArgumentException(
                "CorrelationId debe usar 8-64 caracteres ASCII alfanumericos, '-' o '_'.",
                nameof(correlationId));
        }

        return new DatabaseSessionContext(
            accountId,
            normalizedRole,
            normalizedCorrelation);
    }

    private static bool IsSafeRoleCode(string value)
    {
        if (value.Length is < 1 or > 64)
        {
            return false;
        }

        if (!IsUpperAsciiLetterOrDigit(value[0]))
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

    private static bool IsSafeCorrelationId(string value)
    {
        if (value.Length is < 8 or > 64)
        {
            return false;
        }

        return value.All(static character =>
            char.IsAsciiLetterOrDigit(character)
            || character is '-' or '_');
    }

    private static bool IsUpperAsciiLetterOrDigit(char character)
    {
        return character is >= 'A' and <= 'Z'
            || char.IsAsciiDigit(character);
    }
}
