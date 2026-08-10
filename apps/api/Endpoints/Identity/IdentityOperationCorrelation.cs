using System.Security.Cryptography;
using System.Text;

namespace MusicaAprender.Api.Endpoints.Identity;

internal static class IdentityOperationCorrelation
{
    public static Guid ToGuid(string correlationId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);

        if (Guid.TryParse(correlationId, out var parsed)
            && parsed != Guid.Empty)
        {
            return parsed;
        }

        var digest = SHA256.HashData(Encoding.ASCII.GetBytes(correlationId));
        try
        {
            return new Guid(digest.AsSpan(0, 16));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(digest);
        }
    }
}
