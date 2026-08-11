using System.Net;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;

namespace MusicaAprender.Modules.Security.Infrastructure.Authentication;

public sealed class LoginAbuseFingerprintService
{
    private const string KeyConfiguration = "IdentityProtection:LoginAbuseKey";
    private const int KeySize = 32;
    private static readonly byte[] AccountPurpose =
        Encoding.ASCII.GetBytes("MusicaAprender.LoginAbuse.Account.v1\0");
    private static readonly byte[] ClientPurpose =
        Encoding.ASCII.GetBytes("MusicaAprender.LoginAbuse.Client.v1\0");

    private readonly byte[] _key;

    public LoginAbuseFingerprintService(ReadOnlySpan<byte> key)
    {
        if (key.Length != KeySize)
        {
            throw new ArgumentException(
                "La clave de control de abuso debe tener exactamente 32 bytes.",
                nameof(key));
        }

        _key = key.ToArray();
    }

    public static LoginAbuseFingerprintService FromConfiguration(
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
                $"La clave configurada en '{KeyConfiguration}' no es hexadecimal válida.",
                exception);
        }

        try
        {
            return new LoginAbuseFingerprintService(key);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    public byte[] CreateAccountFingerprint(ReadOnlySpan<byte> emailLookupHash)
    {
        if (emailLookupHash.Length != 32)
        {
            throw new ArgumentException(
                "El hash de búsqueda de correo debe contener 32 bytes.",
                nameof(emailLookupHash));
        }

        var input = new byte[AccountPurpose.Length + emailLookupHash.Length];
        try
        {
            AccountPurpose.CopyTo(input, 0);
            emailLookupHash.CopyTo(input.AsSpan(AccountPurpose.Length));
            return HMACSHA256.HashData(_key, input);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(input);
        }
    }

    public byte[] CreateClientFingerprint(string? clientAddress)
    {
        var canonical = CanonicalizeClientAddress(clientAddress);
        var addressBytes = Encoding.UTF8.GetBytes(canonical);
        var input = new byte[ClientPurpose.Length + addressBytes.Length];

        try
        {
            ClientPurpose.CopyTo(input, 0);
            addressBytes.CopyTo(input, ClientPurpose.Length);
            return HMACSHA256.HashData(_key, input);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(addressBytes);
            CryptographicOperations.ZeroMemory(input);
        }
    }

    private static string CanonicalizeClientAddress(string? clientAddress)
    {
        if (string.IsNullOrWhiteSpace(clientAddress)
            || !IPAddress.TryParse(clientAddress.Trim(), out var address))
        {
            return "unavailable";
        }

        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        return address.ToString();
    }
}
