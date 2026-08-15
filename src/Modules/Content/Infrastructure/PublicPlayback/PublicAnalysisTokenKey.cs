using System.Security.Cryptography;
using System.Text;

namespace MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

internal static class PublicAnalysisTokenKey
{
    internal const int Length = 20;
    private const string Salt = ":public-analysis-token-v1";

    internal static string FromTokenId(Guid tokenId)
    {
        if (tokenId == Guid.Empty)
        {
            throw new ArgumentException(
                "El token canónico es obligatorio.",
                nameof(tokenId));
        }

        var payload = Encoding.UTF8.GetBytes($"{tokenId:D}{Salt}");
        return Convert.ToHexString(SHA256.HashData(payload))[..Length];
    }

    internal static string Normalize(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length != Length
            || normalized.Any(static character =>
                character is not (>= '0' and <= '9')
                && character is not (>= 'A' and <= 'F')))
        {
            throw new ArgumentException(
                $"La referencia pública de análisis debe contener {Length} caracteres hexadecimales.",
                nameof(value));
        }

        return normalized;
    }
}
