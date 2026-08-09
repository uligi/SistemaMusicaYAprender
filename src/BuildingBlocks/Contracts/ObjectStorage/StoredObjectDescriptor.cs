namespace MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;

public sealed record StoredObjectDescriptor(
    Guid ObjectId,
    string OwnerModule,
    string PurposeCode,
    string StorageKey,
    string MediaType,
    long SizeBytes,
    byte[] Checksum,
    string EncryptionKeyReference,
    DateTimeOffset CreatedAt,
    DateTimeOffset? RetentionUntil,
    string StatusCode);
