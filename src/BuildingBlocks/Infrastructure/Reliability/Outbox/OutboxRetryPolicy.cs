using System.Buffers.Binary;
using System.Security.Cryptography;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public static class OutboxRetryPolicy
{
    public const int MaxAttempts = 3;

    public static TimeSpan CalculateDelay(Guid eventId, int attemptNo)
    {
        if (eventId == Guid.Empty)
        {
            throw new ArgumentException(
                "EventId no puede ser Guid.Empty.",
                nameof(eventId));
        }

        if (attemptNo is < 1 or >= MaxAttempts)
        {
            throw new ArgumentOutOfRangeException(
                nameof(attemptNo),
                "Solo los intentos 1 y 2 programan un nuevo reintento.");
        }

        Span<byte> input = stackalloc byte[20];
        if (!eventId.TryWriteBytes(input[..16]))
        {
            throw new InvalidOperationException(
                "No se pudo serializar EventId para calcular jitter.");
        }
        BinaryPrimitives.WriteInt32BigEndian(input[16..], attemptNo);

        Span<byte> hash = stackalloc byte[32];
        SHA256.HashData(input, hash);

        var jitterMilliseconds =
            50 + BinaryPrimitives.ReadUInt16BigEndian(hash[..2]) % 900;

        var baseSeconds = attemptNo == 1 ? 1 : 2;

        return TimeSpan.FromSeconds(baseSeconds)
            + TimeSpan.FromMilliseconds(jitterMilliseconds);
    }
}
