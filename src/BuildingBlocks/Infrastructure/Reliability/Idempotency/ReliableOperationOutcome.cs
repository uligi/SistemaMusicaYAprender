namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;

public sealed record ReliableOperationOutcome(
    int ResponseCode,
    string ResponseReferenceJson,
    bool Replayed);
