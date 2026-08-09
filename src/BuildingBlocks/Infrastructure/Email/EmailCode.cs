namespace MusicaAprender.BuildingBlocks.Infrastructure.Email;

internal static class EmailCode
{
    public static string RequireCode(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);

        var normalized = value.Trim();

        if (normalized.Length is < 1 or > 64
            || !IsUpperAsciiLetterOrDigit(normalized[0]))
        {
            throw new ArgumentException(
                "El codigo debe usar 1-64 caracteres en formato [A-Z0-9][A-Z0-9._-]*.",
                parameterName);
        }

        for (var index = 1; index < normalized.Length; index++)
        {
            var character = normalized[index];

            if (!(IsUpperAsciiLetterOrDigit(character)
                  || character is '.' or '_' or '-'))
            {
                throw new ArgumentException(
                    "El codigo debe usar 1-64 caracteres en formato [A-Z0-9][A-Z0-9._-]*.",
                    parameterName);
            }
        }

        return normalized;
    }

    public static string RequireLanguageTag(
        string value,
        string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);

        var normalized = value.Trim();

        if (normalized.Length is < 2 or > 35)
        {
            throw new ArgumentException(
                "LanguageTag debe contener un identificador BCP-47 corto y no vacio.",
                parameterName);
        }

        foreach (var character in normalized)
        {
            if (!(char.IsAsciiLetterOrDigit(character) || character == '-'))
            {
                throw new ArgumentException(
                    "LanguageTag solo puede contener letras ASCII, digitos y guion.",
                    parameterName);
            }
        }

        return normalized;
    }

    private static bool IsUpperAsciiLetterOrDigit(char character)
    {
        return character is >= 'A' and <= 'Z'
            || char.IsAsciiDigit(character);
    }
}
