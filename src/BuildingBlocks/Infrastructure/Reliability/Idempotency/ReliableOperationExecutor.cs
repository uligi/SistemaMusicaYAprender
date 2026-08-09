using System.Security.Cryptography;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;

public sealed class ReliableOperationExecutor(
    IRlsTransactionExecutor transactionExecutor,
    ITransactionalOutboxWriter outboxWriter)
    : IReliableOperationExecutor
{
    public async Task<ReliableOperationOutcome> ExecuteAsync(
        DatabaseSessionContext context,
        ReliableOperationRequest request,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<ReliableOperationResult>>
            operation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(operation);

        return await transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                var reservation = await ReserveAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    request,
                    token);

                if (reservation.Replay is not null)
                {
                    return reservation.Replay;
                }

                var result = await operation(
                    connection,
                    transaction,
                    token);

                foreach (var message in result.Events)
                {
                    await outboxWriter.EnqueueAsync(
                        connection,
                        transaction,
                        message,
                        token);
                }

                await CompleteAsync(
                    connection,
                    transaction,
                    reservation.IdempotencyId,
                    result,
                    token);

                return new ReliableOperationOutcome(
                    result.ResponseCode,
                    result.ResponseReferenceJson,
                    Replayed: false);
            },
            cancellationToken);
    }

    private static async Task<Reservation> ReserveAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        ReliableOperationRequest request,
        CancellationToken cancellationToken)
    {
        const string insertSql = """
            INSERT INTO ops.idempotency_record (
                account_id,
                operation_code,
                idempotency_key,
                request_digest,
                response_code,
                response_ref,
                created_at,
                expires_at
            )
            VALUES (
                @account_id,
                @operation_code,
                @idempotency_key,
                @request_digest,
                102,
                '{}'::jsonb,
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP + @retention
            )
            ON CONFLICT (account_id, operation_code, idempotency_key)
            DO NOTHING
            RETURNING idempotency_id;
            """;

        await using (var insertCommand =
                     new NpgsqlCommand(insertSql, connection, transaction))
        {
            insertCommand.Parameters.AddWithValue("account_id", accountId);
            insertCommand.Parameters.AddWithValue(
                "operation_code",
                request.OperationCode);
            insertCommand.Parameters.AddWithValue(
                "idempotency_key",
                request.IdempotencyKey);
            insertCommand.Parameters.AddWithValue(
                "request_digest",
                NpgsqlDbType.Bytea,
                request.RequestDigest.ToArray());
            insertCommand.Parameters.AddWithValue(
                "retention",
                NpgsqlDbType.Interval,
                request.Retention);

            var inserted = await insertCommand.ExecuteScalarAsync(cancellationToken);

            if (inserted is Guid idempotencyId)
            {
                return new Reservation(idempotencyId, null);
            }
        }

        const string existingSql = """
            SELECT
                idempotency_id,
                request_digest,
                response_code,
                response_ref::text,
                expires_at <= CURRENT_TIMESTAMP AS expired
            FROM ops.idempotency_record
            WHERE
                account_id = @account_id
                AND operation_code = @operation_code
                AND idempotency_key = @idempotency_key
            FOR UPDATE;
            """;

        await using var existingCommand =
            new NpgsqlCommand(existingSql, connection, transaction);

        existingCommand.Parameters.AddWithValue("account_id", accountId);
        existingCommand.Parameters.AddWithValue(
            "operation_code",
            request.OperationCode);
        existingCommand.Parameters.AddWithValue(
            "idempotency_key",
            request.IdempotencyKey);

        await using var reader =
            await existingCommand.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "La reserva idempotente desaparecio despues de resolver el conflicto de unicidad.");
        }

        var existingId = reader.GetGuid(0);
        var existingDigest = (byte[])reader.GetValue(1);
        var existingCode = reader.GetInt32(2);
        var existingReference = reader.GetString(3);
        var expired = reader.GetBoolean(4);

        await reader.DisposeAsync();

        if (expired)
        {
            await ResetExpiredAsync(
                connection,
                transaction,
                existingId,
                request,
                cancellationToken);

            return new Reservation(existingId, null);
        }

        if (!CryptographicOperations.FixedTimeEquals(
                existingDigest,
                request.RequestDigest.Span))
        {
            throw new IdempotencyConflictException(request.OperationCode);
        }

        if (existingCode == 102)
        {
            throw new InvalidOperationException(
                "Se encontro una reserva idempotente incompleta ya confirmada.");
        }

        return new Reservation(
            existingId,
            new ReliableOperationOutcome(
                existingCode,
                existingReference,
                Replayed: true));
    }

    private static async Task ResetExpiredAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid idempotencyId,
        ReliableOperationRequest request,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE ops.idempotency_record
            SET
                request_digest = @request_digest,
                response_code = 102,
                response_ref = '{}'::jsonb,
                created_at = CURRENT_TIMESTAMP,
                expires_at = CURRENT_TIMESTAMP + @retention
            WHERE idempotency_id = @idempotency_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("idempotency_id", idempotencyId);
        command.Parameters.AddWithValue(
            "request_digest",
            NpgsqlDbType.Bytea,
            request.RequestDigest.ToArray());
        command.Parameters.AddWithValue(
            "retention",
            NpgsqlDbType.Interval,
            request.Retention);

        var changed = await command.ExecuteNonQueryAsync(cancellationToken);

        if (changed != 1)
        {
            throw new InvalidOperationException(
                "No se pudo renovar exactamente una reserva idempotente expirada.");
        }
    }

    private static async Task CompleteAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid idempotencyId,
        ReliableOperationResult result,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE ops.idempotency_record
            SET
                response_code = @response_code,
                response_ref = @response_ref
            WHERE
                idempotency_id = @idempotency_id
                AND response_code = 102;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("idempotency_id", idempotencyId);
        command.Parameters.AddWithValue("response_code", result.ResponseCode);
        command.Parameters.AddWithValue(
            "response_ref",
            NpgsqlDbType.Jsonb,
            result.ResponseReferenceJson);

        var changed = await command.ExecuteNonQueryAsync(cancellationToken);

        if (changed != 1)
        {
            throw new InvalidOperationException(
                "No se pudo finalizar exactamente una reserva idempotente.");
        }
    }

    private sealed record Reservation(
        Guid IdempotencyId,
        ReliableOperationOutcome? Replay);
}
