namespace MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;

public sealed record ObjectStoreAccessContext(
    string OwnerModule,
    string PurposeCode);
