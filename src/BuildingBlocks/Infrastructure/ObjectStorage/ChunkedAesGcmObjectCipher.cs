using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage;

internal sealed class ChunkedAesGcmObjectCipher
{
    private const int ChunkSize = 1024 * 1024;
    private const int TagSize = 16;
    private const int NoncePrefixSize = 8;
    private const int NonceSize = 12;

    private static readonly byte[] Magic = Encoding.ASCII.GetBytes("MAOBJ001");

    private readonly byte[] _key;

    public ChunkedAesGcmObjectCipher(byte[] key)
    {
        ArgumentNullException.ThrowIfNull(key);

        if (key.Length != 32)
        {
            throw new ArgumentException(
                "La clave de cifrado de objetos debe tener 32 bytes.",
                nameof(key));
        }

        _key = (byte[])key.Clone();
    }

    public async Task<ObjectCipherResult> EncryptToFileAsync(
        Stream plaintext,
        string destinationPath,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(plaintext);

        if (!plaintext.CanRead)
        {
            throw new ArgumentException(
                "El stream de entrada debe ser legible.",
                nameof(plaintext));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(destinationPath);

        var plaintextBuffer = new byte[ChunkSize];
        var ciphertextBuffer = new byte[ChunkSize];
        var tag = new byte[TagSize];
        var noncePrefix = RandomNumberGenerator.GetBytes(NoncePrefixSize);
        var nonce = new byte[NonceSize];
        var aad = new byte[16];
        var lengthBuffer = new byte[sizeof(int)];
        long totalPlaintext = 0;
        uint chunkIndex = 0;

        using var checksum = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        using var aes = new AesGcm(_key, TagSize);

        try
        {
            await using var destination = new FileStream(
                destinationPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                81920,
                FileOptions.Asynchronous | FileOptions.SequentialScan);

            await destination.WriteAsync(Magic, cancellationToken);
            BinaryPrimitives.WriteInt32BigEndian(lengthBuffer, ChunkSize);
            await destination.WriteAsync(lengthBuffer, cancellationToken);
            await destination.WriteAsync(noncePrefix, cancellationToken);

            while (true)
            {
                var read = await plaintext.ReadAsync(
                    plaintextBuffer.AsMemory(0, ChunkSize),
                    cancellationToken);

                if (read == 0)
                {
                    break;
                }

                if (chunkIndex == uint.MaxValue)
                {
                    throw new InvalidDataException(
                        "El objeto excede el numero maximo de chunks soportado.");
                }

                BuildNonce(noncePrefix, chunkIndex, nonce);
                BuildAdditionalData(chunkIndex, read, aad);

                aes.Encrypt(
                    nonce,
                    plaintextBuffer.AsSpan(0, read),
                    ciphertextBuffer.AsSpan(0, read),
                    tag,
                    aad);

                BinaryPrimitives.WriteInt32BigEndian(lengthBuffer, read);
                await destination.WriteAsync(lengthBuffer, cancellationToken);
                await destination.WriteAsync(
                    ciphertextBuffer.AsMemory(0, read),
                    cancellationToken);
                await destination.WriteAsync(tag, cancellationToken);

                checksum.AppendData(plaintextBuffer, 0, read);
                totalPlaintext = checked(totalPlaintext + read);
                chunkIndex++;
            }

            BinaryPrimitives.WriteInt32BigEndian(lengthBuffer, 0);
            await destination.WriteAsync(lengthBuffer, cancellationToken);
            await destination.FlushAsync(cancellationToken);

            return new ObjectCipherResult(
                totalPlaintext,
                checksum.GetHashAndReset());
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintextBuffer);
            CryptographicOperations.ZeroMemory(ciphertextBuffer);
            CryptographicOperations.ZeroMemory(tag);
            CryptographicOperations.ZeroMemory(nonce);
            CryptographicOperations.ZeroMemory(aad);
        }
    }

    public async Task<ObjectCipherResult> DecryptFromFileAsync(
        string sourcePath,
        Stream plaintextDestination,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        ArgumentNullException.ThrowIfNull(plaintextDestination);

        if (!plaintextDestination.CanWrite)
        {
            throw new ArgumentException(
                "El stream de destino debe ser escribible.",
                nameof(plaintextDestination));
        }

        var headerMagic = new byte[Magic.Length];
        var lengthBuffer = new byte[sizeof(int)];
        var noncePrefix = new byte[NoncePrefixSize];
        var nonce = new byte[NonceSize];
        var aad = new byte[16];
        var ciphertextBuffer = new byte[ChunkSize];
        var plaintextBuffer = new byte[ChunkSize];
        var tag = new byte[TagSize];
        long totalPlaintext = 0;
        uint chunkIndex = 0;

        using var checksum = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        using var aes = new AesGcm(_key, TagSize);

        try
        {
            await using var source = new FileStream(
                sourcePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                81920,
                FileOptions.Asynchronous | FileOptions.SequentialScan);

            await source.ReadExactlyAsync(headerMagic, cancellationToken);

            if (!headerMagic.AsSpan().SequenceEqual(Magic))
            {
                throw new InvalidDataException(
                    "El objeto no usa el formato cifrado aprobado MAOBJ001.");
            }

            await source.ReadExactlyAsync(lengthBuffer, cancellationToken);
            var encodedChunkSize = BinaryPrimitives.ReadInt32BigEndian(lengthBuffer);

            if (encodedChunkSize != ChunkSize)
            {
                throw new InvalidDataException(
                    "El objeto declara un tamano de chunk no soportado.");
            }

            await source.ReadExactlyAsync(noncePrefix, cancellationToken);

            while (true)
            {
                await source.ReadExactlyAsync(lengthBuffer, cancellationToken);
                var encryptedLength = BinaryPrimitives.ReadInt32BigEndian(lengthBuffer);

                if (encryptedLength == 0)
                {
                    break;
                }

                if (encryptedLength is < 0 or > ChunkSize)
                {
                    throw new InvalidDataException(
                        "El objeto contiene un chunk con longitud invalida.");
                }

                if (chunkIndex == uint.MaxValue)
                {
                    throw new InvalidDataException(
                        "El objeto excede el numero maximo de chunks soportado.");
                }

                await source.ReadExactlyAsync(
                    ciphertextBuffer.AsMemory(0, encryptedLength),
                    cancellationToken);
                await source.ReadExactlyAsync(tag, cancellationToken);

                BuildNonce(noncePrefix, chunkIndex, nonce);
                BuildAdditionalData(chunkIndex, encryptedLength, aad);

                aes.Decrypt(
                    nonce,
                    ciphertextBuffer.AsSpan(0, encryptedLength),
                    tag,
                    plaintextBuffer.AsSpan(0, encryptedLength),
                    aad);

                checksum.AppendData(plaintextBuffer, 0, encryptedLength);
                totalPlaintext = checked(totalPlaintext + encryptedLength);

                await plaintextDestination.WriteAsync(
                    plaintextBuffer.AsMemory(0, encryptedLength),
                    cancellationToken);

                chunkIndex++;
            }

            var trailing = new byte[1];
            var trailingRead = await source.ReadAsync(trailing, cancellationToken);

            if (trailingRead != 0)
            {
                throw new InvalidDataException(
                    "El objeto cifrado contiene bytes posteriores al marcador final.");
            }

            return new ObjectCipherResult(
                totalPlaintext,
                checksum.GetHashAndReset());
        }
        finally
        {
            CryptographicOperations.ZeroMemory(ciphertextBuffer);
            CryptographicOperations.ZeroMemory(plaintextBuffer);
            CryptographicOperations.ZeroMemory(tag);
            CryptographicOperations.ZeroMemory(nonce);
            CryptographicOperations.ZeroMemory(aad);
        }
    }

    private static void BuildNonce(
        ReadOnlySpan<byte> prefix,
        uint chunkIndex,
        Span<byte> nonce)
    {
        prefix.CopyTo(nonce[..NoncePrefixSize]);
        BinaryPrimitives.WriteUInt32BigEndian(
            nonce[NoncePrefixSize..],
            chunkIndex);
    }

    private static void BuildAdditionalData(
        uint chunkIndex,
        int plaintextLength,
        Span<byte> aad)
    {
        Magic.AsSpan().CopyTo(aad);
        BinaryPrimitives.WriteUInt32BigEndian(aad[8..12], chunkIndex);
        BinaryPrimitives.WriteInt32BigEndian(aad[12..16], plaintextLength);
    }
}

internal sealed record ObjectCipherResult(
    long PlaintextSize,
    byte[] Checksum);
