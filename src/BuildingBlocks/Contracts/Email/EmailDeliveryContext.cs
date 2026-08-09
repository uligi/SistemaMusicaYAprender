namespace MusicaAprender.BuildingBlocks.Contracts.Email;

public sealed record EmailDeliveryContext(
    Guid DeliveryId,
    string OwnerModule,
    Guid AggregateId,
    Guid DeliveryReference,
    string TemplateCode,
    int TemplateVersion,
    string LanguageTag,
    Guid CorrelationId);
