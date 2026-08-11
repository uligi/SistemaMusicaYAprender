using System.Security.Cryptography;
using System.Text;
using Minio;
using Minio.DataModel.Args;
using MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;
using MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage;
using Npgsql;

namespace MusicaAprender.ObjectStoreVerifier;

internal static class ObjectStoreChecks
{
    private const string OwnerModule = "M15";
    private const string PurposeCode = "RIGHTS_EVIDENCE";

    public static async Task RunAsync(
        ObjectStoreVerificationOptions verificationOptions)
    {
        ArgumentNullException.ThrowIfNull(verificationOptions);

        var storeOptions = verificationOptions.CreateObjectStoreOptions();
        var minioClient = CreateClient(storeOptions);
        var objectStore = new MinioPrivateObjectStore(
            minioClient,
            storeOptions);

        var payload = BuildPayload();
        var expectedChecksum = SHA256.HashData(payload);
        StoredObjectDescriptor? descriptor = null;
        var rowInserted = false;

        try
        {
            await using var source = new MemoryStream(
                payload,
                writable: false);

            descriptor = await objectStore.StoreAsync(
                new ObjectStoreWriteRequest(
                    OwnerModule,
                    PurposeCode,
                    "application/octet-stream",
                    source,
                    DateTimeOffset.UtcNow.AddHours(1)));

            ValidateDescriptor(
                descriptor,
                payload.LongLength,
                expectedChecksum,
                ObjectStoreVerificationOptions.EncryptionKeyReference);

            await InsertStoredObjectAsync(
                verificationOptions,
                descriptor);
            rowInserted = true;

            await VerifyStoredObjectMetadataAsync(
                verificationOptions,
                descriptor);

            Console.WriteLine(
                "OK: stored_object conserva clave, metadatos, tamano, checksum, retencion y referencia de cifrado.");

            await VerifyDeniedScopeAsync(
                objectStore,
                descriptor);

            Console.WriteLine(
                "OK: un contexto de modulo/finalidad distinto no puede leer el objeto.");

            await VerifyAnonymousDirectUrlDeniedAsync(
                storeOptions,
                descriptor,
                payload);

            Console.WriteLine(
                "OK: la URL directa anonima del bucket privado no sirve el recurso.");

            await VerifyCiphertextAtRestAsync(
                minioClient,
                storeOptions,
                descriptor,
                payload);

            Console.WriteLine(
                "OK: MinIO conserva ciphertext MAOBJ001; el plaintext no se almacena directamente.");

            await VerifyAuthorizedRoundTripAsync(
                objectStore,
                descriptor,
                payload);

            Console.WriteLine(
                "OK: lectura autorizada descifra y reconcilia checksum/tamano.");

            await objectStore.DeleteAsync(
                descriptor,
                new ObjectStoreAccessContext(
                    OwnerModule,
                    PurposeCode));

            await MarkDeletedAsync(
                verificationOptions,
                descriptor.ObjectId);

            Console.WriteLine(
                "OK: eliminacion autorizada y estado logico DELETED comprobados.");
        }
        finally
        {
            if (descriptor is not null)
            {
                await objectStore.DeleteAsync(
                    descriptor,
                    new ObjectStoreAccessContext(
                        OwnerModule,
                        PurposeCode));

                if (rowInserted)
                {
                    await DeleteRowAsync(
                        verificationOptions,
                        descriptor.ObjectId);
                }
            }

            CryptographicOperations.ZeroMemory(payload);
            CryptographicOperations.ZeroMemory(expectedChecksum);
        }
    }

    private static IMinioClient CreateClient(
        ObjectStoreOptions options)
    {
        return new MinioClient()
            .WithEndpoint(options.Endpoint.Authority)
            .WithCredentials(options.AccessKey, options.SecretKey)
            .WithSSL(options.Endpoint.Scheme == Uri.UriSchemeHttps)
            .Build();
    }

    private static byte[] BuildPayload()
    {
        var prefix = Encoding.UTF8.GetBytes(
            "BL-MVP-016 private object - contenido sintetico.\n");
        var random = RandomNumberGenerator.GetBytes(8192);
        var payload = new byte[prefix.Length + random.Length];

        Buffer.BlockCopy(
            prefix,
            0,
            payload,
            0,
            prefix.Length);
        Buffer.BlockCopy(
            random,
            0,
            payload,
            prefix.Length,
            random.Length);

        CryptographicOperations.ZeroMemory(random);
        return payload;
    }

    private static void ValidateDescriptor(
        StoredObjectDescriptor descriptor,
        long expectedSize,
        byte[] expectedChecksum,
        string expectedKeyReference)
    {
        if (descriptor.ObjectId == Guid.Empty ||
            descriptor.OwnerModule != OwnerModule ||
            descriptor.PurposeCode != PurposeCode ||
            descriptor.MediaType != "application/octet-stream" ||
            descriptor.SizeBytes != expectedSize ||
            descriptor.StatusCode != "ACTIVE" ||
            !descriptor.StorageKey.StartsWith(
                "objects/",
                StringComparison.Ordinal) ||
            !descriptor.StorageKey.EndsWith(
                ".mae1",
                StringComparison.Ordinal) ||
            !string.Equals(
                descriptor.EncryptionKeyReference,
                expectedKeyReference,
                StringComparison.Ordinal) ||
            !CryptographicOperations.FixedTimeEquals(
                descriptor.Checksum,
                expectedChecksum))
        {
            throw new InvalidOperationException(
                "El descriptor generado por IObjectStore no conserva los metadatos esperados.");
        }
    }

    private static async Task VerifyDeniedScopeAsync(
        MinioPrivateObjectStore objectStore,
        StoredObjectDescriptor descriptor)
    {
        await using var destination = new MemoryStream();

        try
        {
            await objectStore.ReadAsync(
                descriptor,
                new ObjectStoreAccessContext(
                    "M18",
                    PurposeCode),
                destination);

            throw new InvalidOperationException(
                "IObjectStore permitio acceso con owner_module incorrecto.");
        }
        catch (UnauthorizedAccessException)
        {
            // Resultado esperado.
        }
    }

    private static async Task VerifyAnonymousDirectUrlDeniedAsync(
        ObjectStoreOptions options,
        StoredObjectDescriptor descriptor,
        byte[] plaintext)
    {
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(10)
        };

        var directUri = new Uri(
            options.Endpoint,
            $"{options.Bucket}/{descriptor.StorageKey}");

        using var response = await client.GetAsync(directUri);
        var responseBytes = await response.Content.ReadAsByteArrayAsync();

        if ((int)response.StatusCode is >= 200 and < 300)
        {
            throw new InvalidOperationException(
                "El objeto privado fue servido por URL directa anonima.");
        }

        if (responseBytes.AsSpan().IndexOf(plaintext) >= 0)
        {
            throw new InvalidOperationException(
                "La respuesta anonima expuso el contenido privado.");
        }
    }

    private static async Task VerifyCiphertextAtRestAsync(
        IMinioClient minioClient,
        ObjectStoreOptions options,
        StoredObjectDescriptor descriptor,
        byte[] plaintext)
    {
        await using var raw = new MemoryStream();

        var args = new GetObjectArgs()
            .WithBucket(options.Bucket)
            .WithObject(descriptor.StorageKey)
            .WithCallbackStream(
                (stream, cancellationToken) =>
                    stream.CopyToAsync(raw, cancellationToken));

        await minioClient.GetObjectAsync(args);

        var ciphertext = raw.ToArray();

        if (ciphertext.AsSpan().SequenceEqual(plaintext) ||
            ciphertext.AsSpan().IndexOf(plaintext) >= 0)
        {
            throw new InvalidOperationException(
                "El backend contiene plaintext en lugar del formato cifrado.");
        }

        var magic = Encoding.ASCII.GetBytes("MAOBJ001");

        if (!ciphertext.AsSpan().StartsWith(magic))
        {
            throw new InvalidOperationException(
                "El objeto no contiene la cabecera de cifrado MAOBJ001.");
        }
    }

    private static async Task VerifyAuthorizedRoundTripAsync(
        MinioPrivateObjectStore objectStore,
        StoredObjectDescriptor descriptor,
        byte[] plaintext)
    {
        for (var attempt = 1; attempt <= 2; attempt++)
        {
            await using var destination = new MemoryStream();

            await objectStore.ReadAsync(
                descriptor,
                new ObjectStoreAccessContext(
                    OwnerModule,
                    PurposeCode),
                destination);

            var restored = destination.ToArray();

            try
            {
                if (!restored.AsSpan().SequenceEqual(plaintext))
                {
                    throw new InvalidOperationException(
                        $"La lectura autorizada repetida {attempt} no devolvio exactamente el plaintext original.");
                }
            }
            finally
            {
                CryptographicOperations.ZeroMemory(restored);
            }
        }
    }

    private static async Task InsertStoredObjectAsync(
        ObjectStoreVerificationOptions options,
        StoredObjectDescriptor descriptor)
    {
        await using var connection = new NpgsqlConnection(
            options.CreateWorkerConnectionString());
        await connection.OpenAsync();

        await using var command = connection.CreateCommand();
        command.CommandText =
            """
            INSERT INTO ops.stored_object
                (object_id,
                 owner_module,
                 purpose_code,
                 storage_key,
                 media_type,
                 size_bytes,
                 checksum,
                 encryption_key_ref,
                 created_at,
                 retention_until,
                 status_code)
            VALUES
                (@object_id,
                 @owner_module,
                 @purpose_code,
                 @storage_key,
                 @media_type,
                 @size_bytes,
                 @checksum,
                 @encryption_key_ref,
                 @created_at,
                 @retention_until,
                 @status_code);
            """;

        command.Parameters.AddWithValue(
            "object_id",
            descriptor.ObjectId);
        command.Parameters.AddWithValue(
            "owner_module",
            descriptor.OwnerModule);
        command.Parameters.AddWithValue(
            "purpose_code",
            descriptor.PurposeCode);
        command.Parameters.AddWithValue(
            "storage_key",
            descriptor.StorageKey);
        command.Parameters.AddWithValue(
            "media_type",
            descriptor.MediaType);
        command.Parameters.AddWithValue(
            "size_bytes",
            descriptor.SizeBytes);
        command.Parameters.AddWithValue(
            "checksum",
            descriptor.Checksum);
        command.Parameters.AddWithValue(
            "encryption_key_ref",
            descriptor.EncryptionKeyReference);
        command.Parameters.AddWithValue(
            "created_at",
            descriptor.CreatedAt.UtcDateTime);
        command.Parameters.AddWithValue(
            "retention_until",
            descriptor.RetentionUntil?.UtcDateTime
                ?? (object)DBNull.Value);
        command.Parameters.AddWithValue(
            "status_code",
            descriptor.StatusCode);

        var affected = await command.ExecuteNonQueryAsync();

        if (affected != 1)
        {
            throw new InvalidOperationException(
                "No se inserto exactamente un stored_object.");
        }
    }

    private static async Task VerifyStoredObjectMetadataAsync(
        ObjectStoreVerificationOptions options,
        StoredObjectDescriptor descriptor)
    {
        await using var connection = new NpgsqlConnection(
            options.CreateWorkerConnectionString());
        await connection.OpenAsync();

        await using var command = connection.CreateCommand();
        command.CommandText =
            """
            SELECT
                owner_module,
                purpose_code,
                storage_key,
                media_type,
                size_bytes,
                checksum,
                encryption_key_ref,
                retention_until,
                status_code
            FROM ops.stored_object
            WHERE object_id = @object_id;
            """;
        command.Parameters.AddWithValue(
            "object_id",
            descriptor.ObjectId);

        await using var reader = await command.ExecuteReaderAsync();

        if (!await reader.ReadAsync())
        {
            throw new InvalidOperationException(
                "No se encontro stored_object despues de insertarlo.");
        }

        var checksum = reader.GetFieldValue<byte[]>(5);
        var retention = reader.IsDBNull(7)
            ? (DateTime?)null
            : reader.GetDateTime(7);

        var matches =
            reader.GetString(0) == descriptor.OwnerModule &&
            reader.GetString(1) == descriptor.PurposeCode &&
            reader.GetString(2) == descriptor.StorageKey &&
            reader.GetString(3) == descriptor.MediaType &&
            reader.GetInt64(4) == descriptor.SizeBytes &&
            CryptographicOperations.FixedTimeEquals(
                checksum,
                descriptor.Checksum) &&
            reader.GetString(6) == descriptor.EncryptionKeyReference &&
            retention is not null &&
            reader.GetString(8) == descriptor.StatusCode;

        if (!matches)
        {
            throw new InvalidOperationException(
                "Los metadatos persistidos no coinciden con el descriptor del objeto.");
        }
    }

    private static async Task MarkDeletedAsync(
        ObjectStoreVerificationOptions options,
        Guid objectId)
    {
        await using var connection = new NpgsqlConnection(
            options.CreateWorkerConnectionString());
        await connection.OpenAsync();

        await using var command = connection.CreateCommand();
        command.CommandText =
            """
            UPDATE ops.stored_object
            SET status_code = 'DELETED'
            WHERE object_id = @object_id;
            """;
        command.Parameters.AddWithValue(
            "object_id",
            objectId);

        var affected = await command.ExecuteNonQueryAsync();

        if (affected != 1)
        {
            throw new InvalidOperationException(
                "No se pudo marcar stored_object como DELETED.");
        }
    }

    private static async Task DeleteRowAsync(
        ObjectStoreVerificationOptions options,
        Guid objectId)
    {
        await using var connection = new NpgsqlConnection(
            options.CreateWorkerConnectionString());
        await connection.OpenAsync();

        await using var command = connection.CreateCommand();
        command.CommandText =
            "DELETE FROM ops.stored_object WHERE object_id = @object_id;";
        command.Parameters.AddWithValue(
            "object_id",
            objectId);

        await command.ExecuteNonQueryAsync();
    }
}
