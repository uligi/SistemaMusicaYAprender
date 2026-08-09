namespace MusicaAprender.BuildingBlocks.Contracts.Email;

public sealed record EmailQueueRequest(
    string OwnerModule,
    Guid AggregateId,
    Guid DeliveryReference,
    string TemplateCode,
    int TemplateVersion,
    string LanguageTag,
    Guid CorrelationId,
    Guid? CausationId = null);
