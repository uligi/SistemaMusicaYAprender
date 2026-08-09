using Microsoft.Extensions.Configuration;

namespace MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage;

public sealed class ObjectStoreOptions
{
    private readonly byte[] _encryptionKey;

    public ObjectStoreOptions(
        Uri endpoint,
        string bucket,
        string accessKey,
        string secretKey,
        string encryptionKeyHex,
        string encryptionKeyReference)
    {
        ArgumentNullException.ThrowIfNull(endpoint);

        if (!endpoint.IsAbsoluteUri ||
            (endpoint.Scheme != Uri.UriSchemeHttp &&
             endpoint.Scheme != Uri.UriSchemeHttps) ||
            endpoint.AbsolutePath != "/")
        {
            throw new ArgumentException(
                "ObjectStore:Endpoint debe ser una URL absoluta HTTP/HTTPS sin path.",
                nameof(endpoint));
        }

        if (!IsValidBucketName(bucket))
        {
            throw new ArgumentException(
                "ObjectStore:Bucket no cumple el formato S3 permitido por el MVP.",
                nameof(bucket));
        }

        if (string.IsNullOrWhiteSpace(accessKey) || accessKey.Length > 256)
        {
            throw new ArgumentException(
                "ObjectStore:AccessKey no cumple el formato esperado.",
                nameof(accessKey));
        }

        if (string.IsNullOrWhiteSpace(secretKey) || secretKey.Length > 4096)
        {
            throw new ArgumentException(
                "ObjectStore:SecretKey no cumple el formato esperado.",
                nameof(secretKey));
        }

        if (string.IsNullOrWhiteSpace(encryptionKeyReference) ||
            encryptionKeyReference.Length > 512)
        {
            throw new ArgumentException(
                "ObjectStore:EncryptionKeyReference debe identificar la clave sin contenerla.",
                nameof(encryptionKeyReference));
        }

        if (string.IsNullOrWhiteSpace(encryptionKeyHex) ||
            encryptionKeyHex.Length != 64)
        {
            throw new ArgumentException(
                "ObjectStore:EncryptionKey debe representar exactamente 32 bytes en hexadecimal.",
                nameof(encryptionKeyHex));
        }

        try
        {
            _encryptionKey = Convert.FromHexString(encryptionKeyHex);
        }
        catch (FormatException exception)
        {
            throw new ArgumentException(
                "ObjectStore:EncryptionKey no es hexadecimal valido.",
                nameof(encryptionKeyHex),
                exception);
        }

        Endpoint = endpoint;
        Bucket = bucket;
        AccessKey = accessKey;
        SecretKey = secretKey;
        EncryptionKeyReference = encryptionKeyReference;
    }

    public Uri Endpoint { get; }

    public string Bucket { get; }

    public string AccessKey { get; }

    public string SecretKey { get; }

    public string EncryptionKeyReference { get; }

    internal byte[] CopyEncryptionKey()
    {
        return (byte[])_encryptionKey.Clone();
    }

    public static ObjectStoreOptions FromConfiguration(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var endpointValue = Require(configuration, "ObjectStore:Endpoint");

        if (!Uri.TryCreate(endpointValue, UriKind.Absolute, out var endpoint))
        {
            throw new InvalidOperationException(
                "ObjectStore:Endpoint no contiene una URL absoluta valida.");
        }

        return new ObjectStoreOptions(
            endpoint,
            Require(configuration, "ObjectStore:Bucket"),
            Require(configuration, "ObjectStore:AccessKey"),
            Require(configuration, "ObjectStore:SecretKey"),
            Require(configuration, "ObjectStore:EncryptionKey"),
            Require(configuration, "ObjectStore:EncryptionKeyReference"));
    }

    private static string Require(IConfiguration configuration, string key)
    {
        var value = configuration[key];

        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException(
                $"Falta la configuracion requerida '{key}'.");
        }

        return value.Trim();
    }

    private static bool IsValidBucketName(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var bucket = value.Trim();

        if (bucket.Length is < 3 or > 63 ||
            !char.IsAsciiLetterOrDigit(bucket[0]) ||
            !char.IsAsciiLetterOrDigit(bucket[^1]) ||
            bucket.Contains("..", StringComparison.Ordinal))
        {
            return false;
        }

        foreach (var character in bucket)
        {
            if (!(char.IsAsciiLetterOrDigit(character) || character is '-' or '.'))
            {
                return false;
            }

            if (char.IsAsciiLetter(character) && char.IsUpper(character))
            {
                return false;
            }
        }

        return true;
    }
}
