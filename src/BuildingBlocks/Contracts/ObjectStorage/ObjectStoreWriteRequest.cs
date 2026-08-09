namespace MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;

public sealed record ObjectStoreWriteRequest(
    string OwnerModule,
    string PurposeCode,
    string MediaType,
    Stream Content,
    DateTimeOffset? RetentionUntil = null);
