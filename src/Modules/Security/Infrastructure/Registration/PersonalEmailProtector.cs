using System.Globalization;
using System.Net.Mail;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;

namespace MusicaAprender.Modules.Security.Infrastructure.Registration;

public sealed class PersonalEmailProtector
{
    private const string LookupKeyConfiguration = "IdentityProtection:EmailLookupKey";
    private const string EncryptionKeyConfiguration = "IdentityProtection:EmailEncryptionKey";
    private const int KeySize = 32;
    private const int NonceSize = 12;
    private const int TagSize = 16;
    private const byte CipherVersion = 1;

    private readonly byte[] _lookupKey;
    private readonly byte[] _encryptionKey;

    public PersonalEmailProtector(
        ReadOnlySpan<byte> lookupKey,
        ReadOnlySpan<byte> encryptionKey)
    {
        if (lookupKey.Length != KeySize)
        {
            throw new ArgumentException(
                "La clave de busqueda de correo debe tener exactamente 32 bytes.",
                nameof(lookupKey));
        }

        if (encryptionKey.Length != KeySize)
        {
            throw new ArgumentException(
                "La clave de cifrado de correo debe tener exactamente 32 bytes.",
                nameof(encryptionKey));
        }

        _lookupKey = lookupKey.ToArray();
        _encryptionKey = encryptionKey.ToArray();
    }

    public static PersonalEmailProtector FromConfiguration(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var lookupKey = ReadHexKey(configuration, LookupKeyConfiguration);
        var encryptionKey = ReadHexKey(configuration, EncryptionKeyConfiguration);

        try
        {
            return new PersonalEmailProtector(lookupKey, encryptionKey);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(lookupKey);
            CryptographicOperations.ZeroMemory(encryptionKey);
        }
    }

    public bool TryProtect(string? email, out ProtectedEmail? protectedEmail)
    {
        if (!TryNormalize(email, out var normalized))
        {
            protectedEmail = null;
            return false;
        }

        var plaintext = Encoding.UTF8.GetBytes(normalized);

        try
        {
            var lookupHash = HMACSHA256.HashData(_lookupKey, plaintext);
            var nonce = RandomNumberGenerator.GetBytes(NonceSize);
            var ciphertext = new byte[1 + NonceSize + TagSize + plaintext.Length];
            ciphertext[0] = CipherVersion;
            nonce.CopyTo(ciphertext.AsSpan(1, NonceSize));

            using var aes = new AesGcm(_encryptionKey, TagSize);
            aes.Encrypt(
                nonce,
                plaintext,
                ciphertext.AsSpan(1 + NonceSize + TagSize),
                ciphertext.AsSpan(1 + NonceSize, TagSize),
                [CipherVersion]);

            protectedEmail = new ProtectedEmail(lookupHash, ciphertext);
            return true;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);
        }
    }

    private static bool TryNormalize(string? value, out string normalized)
    {
        normalized = string.Empty;

        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var candidate = value.Trim();
        if (candidate.Length > 254 || candidate.Any(char.IsControl))
        {
            return false;
        }

        MailAddress parsed;
        try
        {
            parsed = new MailAddress(candidate);
        }
        catch (FormatException)
        {
            return false;
        }

        if (parsed.DisplayName.Length > 0
            || !string.Equals(parsed.Address, candidate, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var separator = candidate.LastIndexOf('@');
        if (separator is < 1 or > 64 || separator == candidate.Length - 1)
        {
            return false;
        }

        var localPart = candidate[..separator].Normalize(NormalizationForm.FormC);
        var domain = candidate[(separator + 1)..].Normalize(NormalizationForm.FormC);

        try
        {
            domain = new IdnMapping().GetAscii(domain);
        }
        catch (ArgumentException)
        {
            return false;
        }

        normalized = string.Concat(
            localPart.ToUpperInvariant(),
            "@",
            domain.ToUpperInvariant());

        return Encoding.UTF8.GetByteCount(normalized) <= 320;
    }

    private static byte[] ReadHexKey(
        IConfiguration configuration,
        string configurationKey)
    {
        var value = configuration[configurationKey];
        if (string.IsNullOrWhiteSpace(value) || value.Length != KeySize * 2)
        {
            throw new InvalidOperationException(
                $"Falta una clave de 32 bytes en '{configurationKey}'.");
        }

        try
        {
            return Convert.FromHexString(value);
        }
        catch (FormatException exception)
        {
            throw new InvalidOperationException(
                $"La clave configurada en '{configurationKey}' no es hexadecimal valida.",
                exception);
        }
    }
}
