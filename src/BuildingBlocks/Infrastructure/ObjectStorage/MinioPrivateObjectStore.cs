using System.Security.Cryptography;
using Minio;
using Minio.DataModel.Args;
using MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;

namespace MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage;

public sealed class MinioPrivateObjectStore : IObjectStore
{
    private readonly IMinioClient _minioClient;
    private readonly ObjectStoreOptions _options;
    private readonly ChunkedAesGcmObjectCipher _cipher;
    private readonly Lazy<Task> _bucketInitialization;

    public MinioPrivateObjectStore(
        IMinioClient minioClient,
        ObjectStoreOptions options)
    {
        ArgumentNullException.ThrowIfNull(minioClient);
        ArgumentNullException.ThrowIfNull(options);

        _minioClient = minioClient;
        _options = options;

        var key = options.CopyEncryptionKey();

        try
        {
            _cipher = new ChunkedAesGcmObjectCipher(key);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }

        _bucketInitialization = new Lazy<Task>(
            EnsurePrivateBucketCoreAsync,
            LazyThreadSafetyMode.ExecutionAndPublication);
    }

    public async Task<StoredObjectDescriptor> StoreAsync(
        ObjectStoreWriteRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(request.Content);

        var ownerModule = ObjectStoreValueGuard.RequireCode(
            request.OwnerModule,
            nameof(request.OwnerModule));
        var purposeCode = ObjectStoreValueGuard.RequireCode(
            request.PurposeCode,
            nameof(request.PurposeCode));
        var mediaType = ObjectStoreValueGuard.RequireMediaType(
            request.MediaType,
            nameof(request.MediaType));

        if (!request.Content.CanRead)
        {
            throw new ArgumentException(
                "El contenido del objeto debe ser legible.",
                nameof(request));
        }

        var createdAt = DateTimeOffset.UtcNow;

        if (request.RetentionUntil is { } retentionUntil &&
            retentionUntil < createdAt)
        {
            throw new ArgumentException(
                "RetentionUntil no puede ser anterior a la creacion del objeto.",
                nameof(request));
        }

        await EnsurePrivateBucketAsync(cancellationToken);

        var objectId = Guid.CreateVersion7();
        var storageKey = $"objects/{objectId:N}.mae1";
        var encryptedPath = CreateTemporaryPath();

        try
        {
            var cipherResult = await _cipher.EncryptToFileAsync(
                request.Content,
                encryptedPath,
                cancellationToken);

            await using (var encryptedStream = new FileStream(
                encryptedPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                81920,
                FileOptions.Asynchronous | FileOptions.SequentialScan))
            {
                var putArgs = new PutObjectArgs()
                    .WithBucket(_options.Bucket)
                    .WithObject(storageKey)
                    .WithStreamData(encryptedStream)
                    .WithObjectSize(encryptedStream.Length)
                    .WithContentType("application/octet-stream");

                await _minioClient.PutObjectAsync(
                    putArgs,
                    cancellationToken);
            }

            return new StoredObjectDescriptor(
                objectId,
                ownerModule,
                purposeCode,
                storageKey,
                mediaType,
                cipherResult.PlaintextSize,
                (byte[])cipherResult.Checksum.Clone(),
                _options.EncryptionKeyReference,
                createdAt,
                request.RetentionUntil,
                "ACTIVE");
        }
        finally
        {
            DeleteTemporaryFile(encryptedPath);
        }
    }

    public async Task ReadAsync(
        StoredObjectDescriptor descriptor,
        ObjectStoreAccessContext access,
        Stream destination,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(descriptor);
        ArgumentNullException.ThrowIfNull(access);
        ArgumentNullException.ThrowIfNull(destination);

        Authorize(descriptor, access);

        if (!destination.CanWrite)
        {
            throw new ArgumentException(
                "El stream de destino debe ser escribible.",
                nameof(destination));
        }

        if (!string.Equals(
                descriptor.EncryptionKeyReference,
                _options.EncryptionKeyReference,
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "La clave requerida por el objeto no esta disponible en esta instancia.");
        }

        if (string.Equals(descriptor.StatusCode, "DELETED", StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "El objeto fue marcado como eliminado.");
        }

        var encryptedPath = CreateTemporaryPath();

        try
        {
            var getArgs = new GetObjectArgs()
                .WithBucket(_options.Bucket)
                .WithObject(descriptor.StorageKey)
                .WithCallbackStream(
                    async source =>
                    {
                        await using var file = new FileStream(
                            encryptedPath,
                            FileMode.CreateNew,
                            FileAccess.Write,
                            FileShare.None,
                            81920,
                            FileOptions.Asynchronous | FileOptions.SequentialScan);

                        await source.CopyToAsync(file, cancellationToken);
                        await file.FlushAsync(cancellationToken);
                    });

            await _minioClient.GetObjectAsync(
                getArgs,
                cancellationToken);

            var cipherResult = await _cipher.DecryptFromFileAsync(
                encryptedPath,
                destination,
                cancellationToken);

            if (cipherResult.PlaintextSize != descriptor.SizeBytes)
            {
                throw new InvalidDataException(
                    "El tamano descifrado no coincide con stored_object.");
            }

            if (!CryptographicOperations.FixedTimeEquals(
                    cipherResult.Checksum,
                    descriptor.Checksum))
            {
                throw new InvalidDataException(
                    "El checksum descifrado no coincide con stored_object.");
            }
        }
        finally
        {
            DeleteTemporaryFile(encryptedPath);
        }
    }

    public async Task DeleteAsync(
        StoredObjectDescriptor descriptor,
        ObjectStoreAccessContext access,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(descriptor);
        ArgumentNullException.ThrowIfNull(access);

        Authorize(descriptor, access);

        var removeArgs = new RemoveObjectArgs()
            .WithBucket(_options.Bucket)
            .WithObject(descriptor.StorageKey);

        await _minioClient.RemoveObjectAsync(
            removeArgs,
            cancellationToken);
    }

    private async Task EnsurePrivateBucketAsync(
        CancellationToken cancellationToken)
    {
        await _bucketInitialization.Value.WaitAsync(cancellationToken);
    }

    private async Task EnsurePrivateBucketCoreAsync()
    {
        var existsArgs = new BucketExistsArgs()
            .WithBucket(_options.Bucket);

        var exists = await _minioClient.BucketExistsAsync(
            existsArgs,
            CancellationToken.None);

        if (exists)
        {
            return;
        }

        var makeArgs = new MakeBucketArgs()
            .WithBucket(_options.Bucket);

        await _minioClient.MakeBucketAsync(
            makeArgs,
            CancellationToken.None);
    }

    private static void Authorize(
        StoredObjectDescriptor descriptor,
        ObjectStoreAccessContext access)
    {
        var ownerModule = ObjectStoreValueGuard.RequireCode(
            access.OwnerModule,
            nameof(access.OwnerModule));
        var purposeCode = ObjectStoreValueGuard.RequireCode(
            access.PurposeCode,
            nameof(access.PurposeCode));

        if (!string.Equals(
                descriptor.OwnerModule,
                ownerModule,
                StringComparison.Ordinal) ||
            !string.Equals(
                descriptor.PurposeCode,
                purposeCode,
                StringComparison.Ordinal))
        {
            throw new UnauthorizedAccessException(
                "El contexto solicitado no autoriza acceso a este objeto privado.");
        }
    }

    private static string CreateTemporaryPath()
    {
        return Path.Combine(
            Path.GetTempPath(),
            $"musica-aprender-object-{Guid.NewGuid():N}.tmp");
    }

    private static void DeleteTemporaryFile(string path)
    {
        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }
}
