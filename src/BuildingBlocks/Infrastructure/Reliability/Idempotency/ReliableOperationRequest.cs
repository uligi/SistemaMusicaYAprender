using System.Security.Cryptography;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Common;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;

public sealed class ReliableOperationRequest
{
    private readonly byte[] _requestDigest;

    private ReliableOperationRequest(
        string operationCode,
        string idempotencyKey,
        byte[] requestDigest,
        TimeSpan retention)
    {
        OperationCode = operationCode;
        IdempotencyKey = idempotencyKey;
        _requestDigest = requestDigest;
        Retention = retention;
    }

    public string OperationCode { get; }

    public string IdempotencyKey { get; }

    public ReadOnlyMemory<byte> RequestDigest => _requestDigest;

    public TimeSpan Retention { get; }

    public static ReliableOperationRequest Create(
        string operationCode,
        string idempotencyKey,
        ReadOnlySpan<byte> canonicalRequest,
        TimeSpan retention)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(idempotencyKey);

        if (idempotencyKey.Length > 512)
        {
            throw new ArgumentException(
                "IdempotencyKey no puede exceder 512 caracteres.",
                nameof(idempotencyKey));
        }

        if (idempotencyKey.Any(char.IsControl))
        {
            throw new ArgumentException(
                "IdempotencyKey no puede contener caracteres de control.",
                nameof(idempotencyKey));
        }

        if (retention <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(
                nameof(retention),
                "Retention debe ser mayor que cero.");
        }

        return new ReliableOperationRequest(
            ReliabilityCode.RequireCode(operationCode, nameof(operationCode)),
            idempotencyKey,
            SHA256.HashData(canonicalRequest),
            retention);
    }
}
