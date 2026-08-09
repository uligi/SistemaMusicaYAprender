namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;

public sealed class IdempotencyConflictException : InvalidOperationException
{
    public IdempotencyConflictException(string operationCode)
        : base("La clave de idempotencia ya existe para una solicitud logica diferente.")
    {
        OperationCode = operationCode;
    }

    public string OperationCode { get; }
}
