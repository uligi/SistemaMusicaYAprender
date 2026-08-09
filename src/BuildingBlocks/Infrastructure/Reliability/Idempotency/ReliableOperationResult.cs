using System.Text.Json;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;

public sealed class ReliableOperationResult
{
    private ReliableOperationResult(
        int responseCode,
        string responseReferenceJson,
        IReadOnlyList<OutboxMessageDraft> events)
    {
        ResponseCode = responseCode;
        ResponseReferenceJson = responseReferenceJson;
        Events = events;
    }

    public int ResponseCode { get; }

    public string ResponseReferenceJson { get; }

    public IReadOnlyList<OutboxMessageDraft> Events { get; }

    public static ReliableOperationResult Create(
        int responseCode,
        string responseReferenceJson,
        params OutboxMessageDraft[] events)
    {
        if (responseCode is < 100 or > 599)
        {
            throw new ArgumentOutOfRangeException(
                nameof(responseCode),
                "ResponseCode debe estar entre 100 y 599.");
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(responseReferenceJson);
        ArgumentNullException.ThrowIfNull(events);

        using var responseReference =
            JsonDocument.Parse(responseReferenceJson);

        if (responseReference.RootElement.ValueKind != JsonValueKind.Object)
        {
            throw new ArgumentException(
                "ResponseReferenceJson debe representar un objeto JSON.",
                nameof(responseReferenceJson));
        }

        return new ReliableOperationResult(
            responseCode,
            responseReference.RootElement.GetRawText(),
            Array.AsReadOnly((OutboxMessageDraft[])events.Clone()));
    }
}
