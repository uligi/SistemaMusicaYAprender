using System.Collections.ObjectModel;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Common;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Inbox;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public sealed class OutboxDispatcher
{
    private const string DispatchJobType = "OUTBOX_DISPATCH";
    private const string OwnerModule = "OPS";
    private const string SavepointName = "outbox_consumer_effects";

    private readonly string _connectionString;
    private readonly ReadOnlyCollection<IOutboxConsumer> _consumers;
    private readonly IInboxConsumerExecutor _inboxExecutor;

    public OutboxDispatcher(
        IConfiguration configuration,
        IEnumerable<IOutboxConsumer> consumers,
        IInboxConsumerExecutor inboxExecutor)
        : this(
            RequireConnectionString(configuration),
            consumers,
            inboxExecutor)
    {
    }

    private OutboxDispatcher(
        string connectionString,
        IEnumerable<IOutboxConsumer> consumers,
        IInboxConsumerExecutor inboxExecutor)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        ArgumentNullException.ThrowIfNull(consumers);
        ArgumentNullException.ThrowIfNull(inboxExecutor);

        _connectionString = connectionString;
        _inboxExecutor = inboxExecutor;

        var materialized = consumers
            .OrderBy(static item => item.ConsumerCode, StringComparer.Ordinal)
            .ToArray();

        foreach (var consumer in materialized)
        {
            ReliabilityCode.RequireCode(
                consumer.ConsumerCode,
                nameof(consumer.ConsumerCode));
        }

        var duplicateCode = materialized
            .GroupBy(
                static item => item.ConsumerCode,
                StringComparer.Ordinal)
            .FirstOrDefault(static group => group.Count() > 1);

        if (duplicateCode is not null)
        {
            throw new InvalidOperationException(
                "ConsumerCode debe identificar un unico consumidor de outbox.");
        }

        _consumers = Array.AsReadOnly(materialized);
    }

    public int RegisteredConsumerCount => _consumers.Count;

    public static OutboxDispatcher CreateForConnectionString(
        string connectionString,
        IEnumerable<IOutboxConsumer> consumers,
        IInboxConsumerExecutor inboxExecutor)
    {
        return new OutboxDispatcher(
            connectionString,
            consumers,
            inboxExecutor);
    }

    public Task<OutboxDispatchOutcome> DispatchNextAsync(
        CancellationToken cancellationToken = default)
    {
        if (_consumers.Count == 0)
        {
            return Task.FromResult(OutboxDispatchOutcome.NoWork);
        }

        return DispatchCoreAsync(null, cancellationToken);
    }

    public Task<OutboxDispatchOutcome> DispatchEventAsync(
        Guid eventId,
        CancellationToken cancellationToken = default)
    {
        if (eventId == Guid.Empty)
        {
            throw new ArgumentException(
                "EventId no puede ser Guid.Empty.",
                nameof(eventId));
        }

        return DispatchCoreAsync(eventId, cancellationToken);
    }

    private async Task<OutboxDispatchOutcome> DispatchCoreAsync(
        Guid? requestedEventId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        var message = await ClaimAsync(
            connection,
            transaction,
            requestedEventId,
            cancellationToken);

        if (message is null)
        {
            await transaction.RollbackAsync(cancellationToken);
            return OutboxDispatchOutcome.NoWork;
        }

        var attempt = await BeginJobAsync(
            connection,
            transaction,
            message,
            cancellationToken);

        await transaction.SaveAsync(
            SavepointName,
            cancellationToken);

        IOutboxConsumer[] matchingConsumers;

        try
        {
            matchingConsumers = _consumers
                .Where(consumer =>
                    consumer.CanHandle(
                        message.EventName,
                        message.SchemaVersion))
                .ToArray();

            if (matchingConsumers.Length == 0)
            {
                throw new OutboxConsumerException("NO_CONSUMER");
            }

            foreach (var consumer in matchingConsumers)
            {
                await _inboxExecutor.ExecuteAsync(
                    connection,
                    transaction,
                    message,
                    consumer,
                    cancellationToken);
            }
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // Frontera de resiliencia: todo fallo del consumidor debe quedar registrado.
        catch (Exception exception)
#pragma warning restore CA1031
        {
            await transaction.RollbackAsync(
                SavepointName,
                cancellationToken);

            await transaction.ReleaseAsync(
                SavepointName,
                cancellationToken);

            var errorCode = GetSafeErrorCode(exception);
            var errorDigest = CreateErrorDigest(
                exception,
                errorCode);

            var terminal =
                attempt.AttemptNo >= OutboxRetryPolicy.MaxAttempts;

            TimeSpan? retryDelay = terminal
                ? null
                : OutboxRetryPolicy.CalculateDelay(
                    message.EventId,
                    attempt.AttemptNo);

            DateTime? nextAttemptAt = retryDelay is null
                ? null
                : attempt.StartedAt + retryDelay.Value;

            await CompleteFailureAsync(
                connection,
                transaction,
                message.EventId,
                attempt.AttemptNo,
                attempt.StartedAt,
                errorCode,
                errorDigest,
                nextAttemptAt,
                terminal,
                cancellationToken);

            await transaction.CommitAsync(cancellationToken);

            return new OutboxDispatchOutcome(
                terminal
                    ? OutboxDispatchOutcomeKind.Review
                    : OutboxDispatchOutcomeKind.RetryScheduled,
                message.EventId,
                message.CorrelationId,
                attempt.AttemptNo,
                0,
                retryDelay,
                nextAttemptAt,
                errorCode);
        }

        await transaction.ReleaseAsync(
            SavepointName,
            cancellationToken);

        await CompleteSuccessAsync(
            connection,
            transaction,
            message.EventId,
            attempt.AttemptNo,
            attempt.StartedAt,
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        return new OutboxDispatchOutcome(
            OutboxDispatchOutcomeKind.Processed,
            message.EventId,
            message.CorrelationId,
            attempt.AttemptNo,
            matchingConsumers.Length,
            null,
            null,
            null);
    }

    private static async Task<OutboxEnvelope?> ClaimAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid? requestedEventId,
        CancellationToken cancellationToken)
    {
        var sql = requestedEventId is null
            ? """
              SELECT
                  event_id,
                  event_name,
                  schema_version,
                  aggregate_type,
                  aggregate_id,
                  payload::text,
                  occurred_at,
                  correlation_id,
                  causation_id
              FROM ops.outbox_message
              WHERE
                  status_code IN ('PENDING', 'RETRY_WAIT')
                  AND (
                      next_attempt_at IS NULL
                      OR next_attempt_at <= CURRENT_TIMESTAMP
                  )
              ORDER BY
                  COALESCE(next_attempt_at, occurred_at),
                  occurred_at,
                  event_id
              FOR UPDATE SKIP LOCKED
              LIMIT 1;
              """
            : """
              SELECT
                  event_id,
                  event_name,
                  schema_version,
                  aggregate_type,
                  aggregate_id,
                  payload::text,
                  occurred_at,
                  correlation_id,
                  causation_id
              FROM ops.outbox_message
              WHERE
                  event_id = @event_id
                  AND status_code IN ('PENDING', 'RETRY_WAIT')
                  AND (
                      next_attempt_at IS NULL
                      OR next_attempt_at <= CURRENT_TIMESTAMP
                  )
              FOR UPDATE SKIP LOCKED;
              """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);

        if (requestedEventId is not null)
        {
            command.Parameters.AddWithValue(
                "event_id",
                requestedEventId.Value);
        }

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new OutboxEnvelope(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetInt32(2),
            reader.GetString(3),
            reader.GetGuid(4),
            reader.GetString(5),
            reader.GetDateTime(6),
            reader.GetGuid(7),
            reader.IsDBNull(8) ? null : reader.GetGuid(8));
    }

    private static async Task<DispatchAttempt> BeginJobAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        OutboxEnvelope message,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO ops.background_job (
                job_id,
                job_type,
                owner_module,
                payload,
                status_code,
                scheduled_at,
                next_attempt_at,
                attempt_count,
                correlation_id
            )
            VALUES (
                @job_id,
                @job_type,
                @owner_module,
                jsonb_build_object(
                    'eventId',
                    CAST(@event_id AS text)
                ),
                'RUNNING',
                @scheduled_at,
                NULL,
                0,
                @correlation_id
            )
            ON CONFLICT (job_id)
            DO UPDATE SET
                status_code = 'RUNNING',
                next_attempt_at = NULL
            RETURNING
                attempt_count + 1,
                CURRENT_TIMESTAMP;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("job_id", message.EventId);
        command.Parameters.AddWithValue("job_type", DispatchJobType);
        command.Parameters.AddWithValue("owner_module", OwnerModule);
        command.Parameters.AddWithValue("event_id", message.EventId);
        command.Parameters.AddWithValue(
            "scheduled_at",
            NpgsqlDbType.TimestampTz,
            message.OccurredAt);
        command.Parameters.AddWithValue(
            "correlation_id",
            message.CorrelationId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "No se pudo iniciar el trabajo de outbox.");
        }

        return new DispatchAttempt(
            reader.GetInt32(0),
            reader.GetDateTime(1));
    }

    private static async Task CompleteSuccessAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid eventId,
        int attemptNo,
        DateTime startedAt,
        CancellationToken cancellationToken)
    {
        const string outboxSql = """
            UPDATE ops.outbox_message
            SET
                status_code = 'PROCESSED',
                next_attempt_at = NULL
            WHERE event_id = @event_id;
            """;

        await ExecuteSingleRowAsync(
            connection,
            transaction,
            outboxSql,
            eventId,
            cancellationToken);

        const string jobSql = """
            UPDATE ops.background_job
            SET
                status_code = 'SUCCEEDED',
                next_attempt_at = NULL,
                attempt_count = @attempt_no
            WHERE job_id = @event_id;
            """;

        await using (var jobCommand =
                     new NpgsqlCommand(jobSql, connection, transaction))
        {
            jobCommand.Parameters.AddWithValue("attempt_no", attemptNo);
            jobCommand.Parameters.AddWithValue("event_id", eventId);

            var changed =
                await jobCommand.ExecuteNonQueryAsync(cancellationToken);

            RequireSingleRow(changed, "trabajo de outbox");
        }

        await InsertAttemptAsync(
            connection,
            transaction,
            eventId,
            attemptNo,
            startedAt,
            "SUCCESS",
            null,
            null,
            cancellationToken);
    }

    private static async Task CompleteFailureAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid eventId,
        int attemptNo,
        DateTime startedAt,
        string errorCode,
        byte[] errorDigest,
        DateTime? nextAttemptAt,
        bool terminal,
        CancellationToken cancellationToken)
    {
        var statusCode = terminal ? "REVIEW" : "RETRY_WAIT";

        const string outboxSql = """
            UPDATE ops.outbox_message
            SET
                status_code = @status_code,
                next_attempt_at = @next_attempt_at
            WHERE event_id = @event_id;
            """;

        await using (var outboxCommand =
                     new NpgsqlCommand(outboxSql, connection, transaction))
        {
            AddFailureStateParameters(
                outboxCommand,
                statusCode,
                nextAttemptAt,
                eventId);

            var changed =
                await outboxCommand.ExecuteNonQueryAsync(cancellationToken);

            RequireSingleRow(changed, "outbox fallido");
        }

        const string jobSql = """
            UPDATE ops.background_job
            SET
                status_code = @status_code,
                next_attempt_at = @next_attempt_at,
                attempt_count = @attempt_no
            WHERE job_id = @event_id;
            """;

        await using (var jobCommand =
                     new NpgsqlCommand(jobSql, connection, transaction))
        {
            AddFailureStateParameters(
                jobCommand,
                statusCode,
                nextAttemptAt,
                eventId);
            jobCommand.Parameters.AddWithValue("attempt_no", attemptNo);

            var changed =
                await jobCommand.ExecuteNonQueryAsync(cancellationToken);

            RequireSingleRow(changed, "trabajo fallido");
        }

        await InsertAttemptAsync(
            connection,
            transaction,
            eventId,
            attemptNo,
            startedAt,
            "FAILURE",
            errorCode,
            errorDigest,
            cancellationToken);
    }

    private static void AddFailureStateParameters(
        NpgsqlCommand command,
        string statusCode,
        DateTime? nextAttemptAt,
        Guid eventId)
    {
        command.Parameters.AddWithValue("status_code", statusCode);
        command.Parameters.AddWithValue(
            "next_attempt_at",
            NpgsqlDbType.TimestampTz,
            nextAttemptAt is null
                ? DBNull.Value
                : nextAttemptAt.Value);
        command.Parameters.AddWithValue("event_id", eventId);
    }

    private static async Task ExecuteSingleRowAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string sql,
        Guid eventId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("event_id", eventId);

        var changed = await command.ExecuteNonQueryAsync(cancellationToken);

        RequireSingleRow(changed, "evento de outbox");
    }

    private static async Task InsertAttemptAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid eventId,
        int attemptNo,
        DateTime startedAt,
        string resultCode,
        string? errorCode,
        byte[]? errorDigest,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO ops.job_attempt (
                job_id,
                attempt_no,
                started_at,
                finished_at,
                result_code,
                error_code,
                error_digest
            )
            VALUES (
                @job_id,
                @attempt_no,
                @started_at,
                CURRENT_TIMESTAMP,
                @result_code,
                @error_code,
                @error_digest
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("job_id", eventId);
        command.Parameters.AddWithValue("attempt_no", attemptNo);
        command.Parameters.AddWithValue(
            "started_at",
            NpgsqlDbType.TimestampTz,
            startedAt);
        command.Parameters.AddWithValue("result_code", resultCode);
        command.Parameters.AddWithValue(
            "error_code",
            NpgsqlDbType.Varchar,
            errorCode is null ? DBNull.Value : errorCode);
        command.Parameters.AddWithValue(
            "error_digest",
            NpgsqlDbType.Bytea,
            errorDigest is null ? DBNull.Value : errorDigest);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static string GetSafeErrorCode(Exception exception)
    {
        return exception is OutboxConsumerException controlled
            ? controlled.ErrorCode
            : "UNEXPECTED_ERROR";
    }

    private static byte[] CreateErrorDigest(
        Exception exception,
        string errorCode)
    {
        var safeDescriptor =
            $"{exception.GetType().FullName ?? exception.GetType().Name}|{errorCode}";

        return SHA256.HashData(
            Encoding.UTF8.GetBytes(safeDescriptor));
    }

    private static void RequireSingleRow(
        int changed,
        string operation)
    {
        if (changed != 1)
        {
            throw new InvalidOperationException(
                $"No se pudo actualizar exactamente una fila para {operation}.");
        }
    }

    private static string RequireConnectionString(
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var connectionString =
            configuration.GetConnectionString("PostgreSQL");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para el dispatcher de outbox.");
        }

        return connectionString;
    }

    private sealed record DispatchAttempt(
        int AttemptNo,
        DateTime StartedAt);
}
