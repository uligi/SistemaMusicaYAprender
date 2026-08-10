using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;

namespace MusicaAprender.Modules.Security.Infrastructure.Verification;

public sealed class AccountVerificationTokenService
{
    private const string KeyConfiguration = "IdentityProtection:VerificationTokenKey";
    private const int KeySize = 32;
    private const int IdentifierSize = 16;
    private const int PayloadSize = IdentifierSize * 2;
    private const int SignatureSize = 32;
    private const int TokenMaterialSize = PayloadSize + SignatureSize;
    private static readonly byte[] Purpose =
        Encoding.ASCII.GetBytes("MusicaAprender.AccountVerification.v1\0");

    private readonly byte[] _key;

    public AccountVerificationTokenService(ReadOnlySpan<byte> key)
    {
        if (key.Length != KeySize)
        {
            throw new ArgumentException(
                "La clave de verificacion debe tener exactamente 32 bytes.",
                nameof(key));
        }

        _key = key.ToArray();
    }

    public static AccountVerificationTokenService FromConfiguration(
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var value = configuration[KeyConfiguration];
        if (string.IsNullOrWhiteSpace(value) || value.Length != KeySize * 2)
        {
            throw new InvalidOperationException(
                $"Falta una clave de 32 bytes en '{KeyConfiguration}'.");
        }

        byte[] key;
        try
        {
            key = Convert.FromHexString(value);
        }
        catch (FormatException exception)
        {
            throw new InvalidOperationException(
                $"La clave configurada en '{KeyConfiguration}' no es hexadecimal valida.",
                exception);
        }

        try
        {
            return new AccountVerificationTokenService(key);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    public string CreateToken(Guid accountId, Guid verificationId)
    {
        ValidateIdentifiers(accountId, verificationId);

        var payload = CreatePayload(accountId, verificationId);
        var signatureInput = new byte[Purpose.Length + payload.Length];
        var material = new byte[TokenMaterialSize];

        try
        {
            Purpose.CopyTo(signatureInput, 0);
            payload.CopyTo(signatureInput, Purpose.Length);
            payload.CopyTo(material, 0);

            var signature = HMACSHA256.HashData(_key, signatureInput);
            try
            {
                signature.CopyTo(material, PayloadSize);
                return EncodeBase64Url(material);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(signature);
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(payload);
            CryptographicOperations.ZeroMemory(signatureInput);
            CryptographicOperations.ZeroMemory(material);
        }
    }

    public byte[] CreateTokenHash(Guid accountId, Guid verificationId)
    {
        var token = CreateToken(accountId, verificationId);
        return SHA256.HashData(Encoding.ASCII.GetBytes(token));
    }

    public bool TryReadToken(
        string? token,
        out AccountVerificationTokenClaims? claims)
    {
        claims = null;

        if (string.IsNullOrWhiteSpace(token)
            || token.Length > 128
            || token.Any(static character =>
                !(char.IsAsciiLetterOrDigit(character) || character is '-' or '_')))
        {
            return false;
        }

        byte[] material;
        try
        {
            material = DecodeBase64Url(token);
        }
        catch (FormatException)
        {
            return false;
        }

        try
        {
            if (material.Length != TokenMaterialSize
                || !string.Equals(
                    token,
                    EncodeBase64Url(material),
                    StringComparison.Ordinal))
            {
                return false;
            }

            var payload = material.AsSpan(0, PayloadSize);
            var suppliedSignature = material.AsSpan(PayloadSize, SignatureSize);
            var signatureInput = new byte[Purpose.Length + PayloadSize];

            try
            {
                Purpose.CopyTo(signatureInput, 0);
                payload.CopyTo(signatureInput.AsSpan(Purpose.Length));
                var expectedSignature = HMACSHA256.HashData(_key, signatureInput);

                try
                {
                    if (!CryptographicOperations.FixedTimeEquals(
                            suppliedSignature,
                            expectedSignature))
                    {
                        return false;
                    }

                    var accountId = ParseIdentifier(payload[..IdentifierSize]);
                    var verificationId = ParseIdentifier(payload[IdentifierSize..PayloadSize]);
                    if (accountId == Guid.Empty || verificationId == Guid.Empty)
                    {
                        return false;
                    }

                    claims = new AccountVerificationTokenClaims(
                        accountId,
                        verificationId,
                        SHA256.HashData(Encoding.ASCII.GetBytes(token)));
                    return true;
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(expectedSignature);
                }
            }
            finally
            {
                CryptographicOperations.ZeroMemory(signatureInput);
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(material);
        }
    }

    private static byte[] CreatePayload(Guid accountId, Guid verificationId)
    {
        return Convert.FromHexString(
            string.Concat(
                accountId.ToString("N"),
                verificationId.ToString("N")));
    }

    private static Guid ParseIdentifier(ReadOnlySpan<byte> value)
    {
        return Guid.ParseExact(Convert.ToHexString(value), "N");
    }

    private static string EncodeBase64Url(ReadOnlySpan<byte> value)
    {
        return Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    private static byte[] DecodeBase64Url(string value)
    {
        var base64 = value.Replace('-', '+').Replace('_', '/');
        var padding = base64.Length % 4;
        if (padding != 0)
        {
            base64 = base64.PadRight(base64.Length + (4 - padding), '=');
        }

        return Convert.FromBase64String(base64);
    }

    private static void ValidateIdentifiers(Guid accountId, Guid verificationId)
    {
        if (accountId == Guid.Empty)
        {
            throw new ArgumentException("AccountId no puede ser Guid.Empty.", nameof(accountId));
        }

        if (verificationId == Guid.Empty)
        {
            throw new ArgumentException(
                "VerificationId no puede ser Guid.Empty.",
                nameof(verificationId));
        }
    }
}

public sealed record AccountVerificationTokenClaims(
    Guid AccountId,
    Guid VerificationId,
    ReadOnlyMemory<byte> TokenHash);
