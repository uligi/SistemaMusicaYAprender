namespace MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage;

internal static class ObjectStoreValueGuard
{
    public static string RequireCode(string? value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("El codigo no puede estar vacio.", parameterName);
        }

        var code = value.Trim();

        if (code.Length > 64 || !char.IsAsciiLetterOrDigit(code[0]))
        {
            throw new ArgumentException("El codigo no cumple el formato permitido.", parameterName);
        }

        foreach (var character in code)
        {
            if (!(char.IsAsciiLetterOrDigit(character) || character is '.' or '_' or '-'))
            {
                throw new ArgumentException("El codigo no cumple el formato permitido.", parameterName);
            }

            if (char.IsAsciiLetter(character) && char.IsLower(character))
            {
                throw new ArgumentException("Los codigos de object storage deben estar en mayusculas.", parameterName);
            }
        }

        return code;
    }

    public static string RequireMediaType(string? value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("El media type no puede estar vacio.", parameterName);
        }

        var mediaType = value.Trim();

        if (mediaType.Length > 255)
        {
            throw new ArgumentException("El media type excede 255 caracteres.", parameterName);
        }

        foreach (var character in mediaType)
        {
            if (char.IsControl(character))
            {
                throw new ArgumentException("El media type contiene caracteres de control.", parameterName);
            }
        }

        return mediaType;
    }
}
