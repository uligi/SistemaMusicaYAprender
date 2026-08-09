using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Common;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public sealed class OutboxConsumerException : Exception
{
    public OutboxConsumerException(string errorCode)
        : base("El consumidor de outbox informo un fallo controlado.")
    {
        ErrorCode = ReliabilityCode.RequireCode(errorCode, nameof(errorCode));
    }

    public string ErrorCode { get; }
}
