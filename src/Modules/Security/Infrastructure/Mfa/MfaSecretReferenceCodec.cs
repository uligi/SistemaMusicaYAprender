using System.Security.Cryptography;
using System.Text.Json;
using MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;

namespace MusicaAprender.Modules.Security.Infrastructure.Mfa;

internal static class MfaSecretReferenceCodec
{
    private const string Prefix = "maobj1:";
    private const string OwnerModule = "M18";
    private const string PurposeCode = "MFA_TOTP_SECRET";
    private const string MediaType = "application/octet-stream";
    private const string StatusCode = "ACTIVE";
    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);

    public static string Encode(StoredObjectDescriptor descriptor)
    {
        ArgumentNullException.ThrowIfNull(descriptor);

        if (!string.Equals(descriptor.OwnerModule, OwnerModule, StringComparison.Ordinal)
            || !string.Equals(descriptor.PurposeCode, PurposeCode, StringComparison.Ordinal)
            || !string.Equals(descriptor.MediaType, MediaType, StringComparison.Ordinal)
            || !string.Equals(descriptor.StatusCode, StatusCode, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "El descriptor del secreto MFA no pertenece al módulo/finalidad esperados.");
        }

        var payload = new SecretReferencePayload(
            descriptor.ObjectId.ToString("N"),
            descriptor.StorageKey,
            descriptor.SizeBytes,
            Base64UrlEncode(descriptor.Checksum),
            descriptor.EncryptionKeyReference,
            descriptor.CreatedAt.ToUnixTimeSeconds(),
            descriptor.RetentionUntil?.ToUnixTimeSeconds());

        var json = JsonSerializer.SerializeToUtf8Bytes(payload, JsonOptions);
        try
        {
            var reference = Prefix + Base64UrlEncode(json);
            if (reference.Length > 512)
            {
                throw new InvalidOperationException(
                    "La referencia opaca del secreto MFA excede security.mfa_method.secret_ref.");
            }

            return reference;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(json);
        }
    }

    public static bool TryDecode(
        string? reference,
        out StoredObjectDescriptor? descriptor)
    {
        descriptor = null;

        if (string.IsNullOrWhiteSpace(reference)
            || !reference.StartsWith(Prefix, StringComparison.Ordinal)
            || reference.Length > 512)
        {
            return false;
        }

        byte[] payloadBytes;
        try
        {
            payloadBytes = Base64UrlDecode(reference[Prefix.Length..]);
        }
        catch (FormatException)
        {
            return false;
        }

        try
        {
            var payload = JsonSerializer.Deserialize<SecretReferencePayload>(
                payloadBytes,
                JsonOptions);

            if (payload is null
                || !Guid.TryParseExact(payload.I, "N", out var objectId)
                || objectId == Guid.Empty
                || string.IsNullOrWhiteSpace(payload.K)
                || payload.K.Length > 512
                || payload.S <= 0
                || string.IsNullOrWhiteSpace(payload.C)
                || string.IsNullOrWhiteSpace(payload.E)
                || payload.E.Length > 512)
            {
                return false;
            }

            byte[] checksum;
            try
            {
                checksum = Base64UrlDecode(payload.C);
            }
            catch (FormatException)
            {
                return false;
            }

            if (checksum.Length != 32)
            {
                CryptographicOperations.ZeroMemory(checksum);
                return false;
            }

            descriptor = new StoredObjectDescriptor(
                objectId,
                OwnerModule,
                PurposeCode,
                payload.K,
                MediaType,
                payload.S,
                checksum,
                payload.E,
                DateTimeOffset.FromUnixTimeSeconds(payload.T),
                payload.R is null
                    ? null
                    : DateTimeOffset.FromUnixTimeSeconds(payload.R.Value),
                StatusCode);

            return true;
        }
        catch (JsonException)
        {
            return false;
        }
        catch (ArgumentOutOfRangeException)
        {
            return false;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(payloadBytes);
        }
    }

    public static ObjectStoreAccessContext AccessContext =>
        new(OwnerModule, PurposeCode);

    public static ObjectStoreWriteRequest CreateWriteRequest(Stream content) =>
        new(
            OwnerModule,
            PurposeCode,
            MediaType,
            content,
            RetentionUntil: null);

    private static string Base64UrlEncode(ReadOnlySpan<byte> value) =>
        Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    private static byte[] Base64UrlDecode(string value)
    {
        var normalized = value
            .Replace('-', '+')
            .Replace('_', '/');

        normalized += (normalized.Length % 4) switch
        {
            0 => string.Empty,
            2 => "==",
            3 => "=",
            _ => throw new FormatException("Base64Url inválido.")
        };

        return Convert.FromBase64String(normalized);
    }

    private sealed record SecretReferencePayload(
        string I,
        string K,
        long S,
        string C,
        string E,
        long T,
        long? R);
}
