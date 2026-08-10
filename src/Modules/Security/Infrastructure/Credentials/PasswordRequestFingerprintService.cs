using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;

namespace MusicaAprender.Modules.Security.Infrastructure.Credentials;

public sealed class PasswordRequestFingerprintService
{
    private const string KeyConfiguration = "IdentityProtection:PasswordFingerprintKey";
    private const int KeySize = 32;
    private static readonly byte[] Purpose =
        Encoding.ASCII.GetBytes("MusicaAprender.PasswordRequestFingerprint.v1\0");

    private readonly byte[] _key;

    public PasswordRequestFingerprintService(ReadOnlySpan<byte> key)
    {
        if (key.Length != KeySize)
        {
            throw new ArgumentException(
                "La clave de huella de solicitud debe tener exactamente 32 bytes.",
                nameof(key));
        }

        _key = key.ToArray();
    }

    public static PasswordRequestFingerprintService FromConfiguration(
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
            return new PasswordRequestFingerprintService(key);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    public byte[] CreateFingerprint(string normalizedPassword)
    {
        ArgumentNullException.ThrowIfNull(normalizedPassword);

        var passwordBytes = Encoding.UTF8.GetBytes(normalizedPassword);
        var input = new byte[Purpose.Length + passwordBytes.Length];

        try
        {
            Purpose.CopyTo(input, 0);
            passwordBytes.CopyTo(input, Purpose.Length);
            return HMACSHA256.HashData(_key, input);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(passwordBytes);
            CryptographicOperations.ZeroMemory(input);
        }
    }
}
