using System.Text.Json;
using MusicaAprender.BuildingBlocks.Contracts.Email;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;

internal sealed record EmailDeliveryPayload(
    Guid DeliveryId,
    string OwnerModule,
    Guid AggregateId,
    Guid DeliveryReference,
    string TemplateCode,
    int TemplateVersion,
    string LanguageTag)
{
    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);

    public static EmailDeliveryPayload Create(
        Guid deliveryId,
        EmailQueueRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (deliveryId == Guid.Empty)
        {
            throw new ArgumentException(
                "DeliveryId no puede ser Guid.Empty.",
                nameof(deliveryId));
        }

        if (request.AggregateId == Guid.Empty)
        {
            throw new ArgumentException(
                "AggregateId no puede ser Guid.Empty.",
                nameof(request));
        }

        if (request.DeliveryReference == Guid.Empty)
        {
            throw new ArgumentException(
                "DeliveryReference no puede ser Guid.Empty.",
                nameof(request));
        }

        if (request.CorrelationId == Guid.Empty)
        {
            throw new ArgumentException(
                "CorrelationId no puede ser Guid.Empty.",
                nameof(request));
        }

        if (request.TemplateVersion <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(request),
                "TemplateVersion debe ser mayor que cero.");
        }

        return new EmailDeliveryPayload(
            deliveryId,
            EmailCode.RequireCode(
                request.OwnerModule,
                nameof(request.OwnerModule)),
            request.AggregateId,
            request.DeliveryReference,
            EmailCode.RequireCode(
                request.TemplateCode,
                nameof(request.TemplateCode)),
            request.TemplateVersion,
            EmailCode.RequireLanguageTag(
                request.LanguageTag,
                nameof(request.LanguageTag)));
    }

    public static EmailDeliveryPayload Parse(string payloadJson)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(payloadJson);

        EmailDeliveryPayload? payload;

        try
        {
            payload = JsonSerializer.Deserialize<EmailDeliveryPayload>(
                payloadJson,
                JsonOptions);
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException(
                "El payload de correo no cumple el contrato versionado.",
                exception);
        }

        if (payload is null
            || payload.DeliveryId == Guid.Empty
            || payload.AggregateId == Guid.Empty
            || payload.DeliveryReference == Guid.Empty
            || payload.TemplateVersion <= 0)
        {
            throw new InvalidOperationException(
                "El payload de correo no contiene referencias validas.");
        }

        return payload with
        {
            OwnerModule = EmailCode.RequireCode(
                payload.OwnerModule,
                nameof(payload.OwnerModule)),
            TemplateCode = EmailCode.RequireCode(
                payload.TemplateCode,
                nameof(payload.TemplateCode)),
            LanguageTag = EmailCode.RequireLanguageTag(
                payload.LanguageTag,
                nameof(payload.LanguageTag))
        };
    }

    public string Serialize()
    {
        return JsonSerializer.Serialize(this, JsonOptions);
    }

    public EmailDeliveryContext ToContext(Guid correlationId)
    {
        if (correlationId == Guid.Empty)
        {
            throw new ArgumentException(
                "CorrelationId no puede ser Guid.Empty.",
                nameof(correlationId));
        }

        return new EmailDeliveryContext(
            DeliveryId,
            OwnerModule,
            AggregateId,
            DeliveryReference,
            TemplateCode,
            TemplateVersion,
            LanguageTag,
            correlationId);
    }
}
