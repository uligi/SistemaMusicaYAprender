namespace MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;

public interface IObjectStore
{
    Task<StoredObjectDescriptor> StoreAsync(
        ObjectStoreWriteRequest request,
        CancellationToken cancellationToken = default);

    Task ReadAsync(
        StoredObjectDescriptor descriptor,
        ObjectStoreAccessContext access,
        Stream destination,
        CancellationToken cancellationToken = default);

    Task DeleteAsync(
        StoredObjectDescriptor descriptor,
        ObjectStoreAccessContext access,
        CancellationToken cancellationToken = default);
}
