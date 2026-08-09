namespace MusicaAprender.BuildingBlocks.Contracts.Email;

public sealed record EmailQueueReceipt(
    Guid EventId,
    Guid DeliveryId);
