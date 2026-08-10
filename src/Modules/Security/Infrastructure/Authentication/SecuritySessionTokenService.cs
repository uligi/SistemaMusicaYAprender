using System.Security.Cryptography;
using System.Text;

namespace MusicaAprender.Modules.Security.Infrastructure.Authentication;

public static class SecuritySessionTokenService
{
    public const int TokenSize = 32;
    public const int EncodedTokenLength = 43;

    public static string CreateToken()
    {
        var bytes = RandomNumberGenerator.GetBytes(TokenSize);
        try
        {
            return Convert.ToBase64String(bytes)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
        }
    }

    public static bool TryHashToken(string? token, out byte[] hash)
    {
        hash = [];

        if (token is null
            || token.Length != EncodedTokenLength
            || token.Any(static character =>
                !(char.IsAsciiLetterOrDigit(character) || character is '-' or '_')))
        {
            return false;
        }

        var tokenBytes = Encoding.ASCII.GetBytes(token);
        try
        {
            hash = SHA256.HashData(tokenBytes);
            return true;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(tokenBytes);
        }
    }
}
