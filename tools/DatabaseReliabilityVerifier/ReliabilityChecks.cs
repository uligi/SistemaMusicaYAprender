using System.Globalization;
using System.Text;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Inbox;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;

namespace MusicaAprender.DatabaseReliabilityVerifier;

internal sealed class ReliabilityChecks
{
    private static readonly Guid AccountId =
        Guid.Parse("15000000-0000-4000-8000-000000000001");

    private static readonly Guid CollisionEventId =
        Guid.Parse("15000000-0000-7000-8000-000000000101");

    private static readonly Guid AtomicEventId =
        Guid.Parse("15000000-0000-7000-8000-000000000102");

    private static readonly Guid DispatchEventId =
        Guid.Parse("15000000-0000-7000-8000-000000000103");

    private static readonly Guid RetryEventId =
        Guid.Parse("15000000-0000-7000-8000-000000000104");

    private static readonly Guid CorrelationId =
        Guid.Parse("15000000-0000-7000-8000-000000000201");

    private const string OriginalDisplayName = "BL-MVP-015 ORIGINAL";
    private const string CommittedDisplayName = "BL-MVP-015 COMMITTED";

    private readonly string _workerConnectionString;
    private readonly RlsTransactionExecutor _transactionExecutor;
    private readonly TransactionalOutboxWriter _outboxWriter;
    private readonly ReliableOperationExecutor _reliableExecutor;
    private readonly DatabaseSessionContext _sessionContext;

    public ReliabilityChecks(ReliabilityVerificationOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var apiConnectionString = options.CreateApiConnectionString();
        _workerConnectionString = options.CreateWorkerConnectionString();

        _transactionExecutor =
            new RlsTransactionExecutor(apiConnectionString);
        _outboxWriter = new TransactionalOutboxWriter();
        _reliableExecutor =
            new ReliableOperationExecutor(
                _transactionExecutor,
                _outboxWriter);
        _sessionContext = DatabaseSessionContext.Create(
            AccountId,
            "STUDENT",
            "blmvp015-reliability");
    }

    public async Task RunAsync()
    {
        await VerifyAtomicRollbackAsync();
        await VerifyAtomicCommitAndIdempotencyAsync();
        await VerifyInboxRedeliveryAsync();
        await VerifyRetryAndObservabilityAsync();

        Console.WriteLine(
            "OK: decision/outbox atomicos; 1.000 reintentos sin duplicados; inbox exactamente-una-vez logico; 3 intentos observables.");
    }

    private async Task VerifyAtomicRollbackAsync()
    {
        var collision = CreateEvent(
            CollisionEventId,
            "ops.reliability-collision.v1");

        await _transactionExecutor.ExecuteAsync(
            _sessionContext,
            (connection, transaction, token) =>
                _outboxWriter.EnqueueAsync(
                    connection,
                    transaction,
                    collision,
                    token));

        var request = ReliableOperationRequest.Create(
            "BL015.ATOMIC_ROLLBACK",
            "rollback-on-outbox-conflict",
            Encoding.UTF8.GetBytes("request:rollback"),
            TimeSpan.FromHours(1));

        var duplicateEvent = CreateEvent(
            CollisionEventId,
            "ops.reliability-duplicate.v1");

        var failedAsExpected = false;

        try
        {
            await _reliableExecutor.ExecuteAsync(
                _sessionContext,
                request,
                async (connection, transaction, token) =>
                {
                    await UpdateDisplayNameAsync(
                        connection,
                        transaction,
                        "BL-MVP-015 SHOULD ROLLBACK",
                        token);

                    return ReliableOperationResult.Create(
                        200,
                        """{"state":"should-not-commit"}""",
                        duplicateEvent);
                });
        }
        catch (PostgresException exception)
            when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            failedAsExpected = true;
        }

        Assert(
            failedAsExpected,
            "La colision del outbox debio abortar la transaccion.");

        var displayName = await ReadDisplayNameAsync();

        Assert(
            string.Equals(
                displayName,
                OriginalDisplayName,
                StringComparison.Ordinal),
            "La decision de negocio sobrevivio indebidamente al fallo del outbox.");

        var recordCount = await CountIdempotencyAsync(
            "BL015.ATOMIC_ROLLBACK",
            "rollback-on-outbox-conflict");

        Assert(
            recordCount == 0,
            "La reserva idempotente sobrevivio indebidamente al rollback.");

        Console.WriteLine(
            "OK: un fallo del outbox revierte decision e idempotencia.");
    }

    private async Task VerifyAtomicCommitAndIdempotencyAsync()
    {
        var request = ReliableOperationRequest.Create(
            "BL015.ATOMIC_COMMIT",
            "same-request-1000-times",
            Encoding.UTF8.GetBytes("request:atomic-commit"),
            TimeSpan.FromHours(1));

        var message = CreateEvent(
            AtomicEventId,
            "identity.profile-updated.v1");

        var first = await _reliableExecutor.ExecuteAsync(
            _sessionContext,
            request,
            async (connection, transaction, token) =>
            {
                await UpdateDisplayNameAsync(
                    connection,
                    transaction,
                    CommittedDisplayName,
                    token);

                return ReliableOperationResult.Create(
                    200,
                    $$"""{"accountId":"{{AccountId:D}}","state":"committed"}""",
                    message);
            });

        Assert(
            !first.Replayed,
            "La primera ejecucion no debe marcarse como replay.");

        var unexpectedExecutions = 0;

        for (var repetition = 0; repetition < 1000; repetition++)
        {
            var replay = await _reliableExecutor.ExecuteAsync(
                _sessionContext,
                request,
                (_, _, _) =>
                {
                    unexpectedExecutions++;
                    return Task.FromException<ReliableOperationResult>(
                        new InvalidOperationException(
                            "Un replay no debe ejecutar nuevamente la decision."));
                });

            Assert(
                replay.Replayed,
                "Cada repeticion posterior debe reutilizar la respuesta.");
            Assert(
                replay.ResponseCode == 200,
                "El replay debe conservar el codigo de respuesta.");
        }

        Assert(
            unexpectedExecutions == 0,
            "La decision se ejecuto durante un replay idempotente.");

        Assert(
            await CountIdempotencyAsync(
                request.OperationCode,
                request.IdempotencyKey) == 1,
            "Debe existir un solo registro idempotente.");

        Assert(
            await CountOutboxAsync(AtomicEventId) == 1,
            "Debe existir un solo evento de outbox.");

        Assert(
            string.Equals(
                await ReadDisplayNameAsync(),
                CommittedDisplayName,
                StringComparison.Ordinal),
            "La decision confirmada no coincide con el estado esperado.");

        var conflictingRequest = ReliableOperationRequest.Create(
            request.OperationCode,
            request.IdempotencyKey,
            Encoding.UTF8.GetBytes("request:different"),
            TimeSpan.FromHours(1));

        var conflictDetected = false;

        try
        {
            await _reliableExecutor.ExecuteAsync(
                _sessionContext,
                conflictingRequest,
                (_, _, _) =>
                    Task.FromException<ReliableOperationResult>(
                        new InvalidOperationException(
                            "Una clave con digest distinto no debe ejecutar la decision.")));
        }
        catch (IdempotencyConflictException)
        {
            conflictDetected = true;
        }

        Assert(
            conflictDetected,
            "La misma clave con digest distinto debe producir conflicto.");

        Console.WriteLine(
            "OK: 1.000 repeticiones reutilizan una sola decision, respuesta y evento.");
    }

    private async Task VerifyInboxRedeliveryAsync()
    {
        const string eventName = "progress.reliability-projection.v1";
        var message = CreateEvent(DispatchEventId, eventName);

        await _transactionExecutor.ExecuteAsync(
            _sessionContext,
            (connection, transaction, token) =>
                _outboxWriter.EnqueueAsync(
                    connection,
                    transaction,
                    message,
                    token));

        var consumer = new CheckpointConsumer(
            "BL015.PROJECTION_CONSUMER",
            eventName,
            "BL015.PROJECTION");

        var dispatcher = OutboxDispatcher.CreateForConnectionString(
            _workerConnectionString,
            [consumer],
            new InboxConsumerExecutor());

        var first =
            await dispatcher.DispatchEventAsync(DispatchEventId);

        Assert(
            first.Kind == OutboxDispatchOutcomeKind.Processed
            && first.AttemptNo == 1,
            "La primera entrega debe procesarse en el primer intento.");

        await ForcePendingAsync(DispatchEventId);

        var second =
            await dispatcher.DispatchEventAsync(DispatchEventId);

        Assert(
            second.Kind == OutboxDispatchOutcomeKind.Processed
            && second.AttemptNo == 2,
            "La redelivery controlada debe terminar sin duplicar el efecto.");

        Assert(
            consumer.InvocationCount == 1,
            "El inbox no evito la segunda ejecucion del consumidor.");

        Assert(
            await ReadProjectionVersionAsync(
                "BL015.PROJECTION",
                consumer.ConsumerCode) == 1,
            "El efecto del consumidor se aplico mas de una vez.");

        Assert(
            await CountInboxAsync(
                DispatchEventId,
                consumer.ConsumerCode) == 1,
            "Debe existir una sola fila de inbox por consumidor/evento.");

        Console.WriteLine(
            "OK: redelivery del outbox conserva un unico efecto por inbox.");
    }

    private async Task VerifyRetryAndObservabilityAsync()
    {
        const string eventName = "ops.reliability-failure.v1";
        var message = CreateEvent(RetryEventId, eventName);

        await _transactionExecutor.ExecuteAsync(
            _sessionContext,
            (connection, transaction, token) =>
                _outboxWriter.EnqueueAsync(
                    connection,
                    transaction,
                    message,
                    token));

        var consumer = new FailingConsumer(
            "BL015.FAILING_CONSUMER",
            eventName);

        var dispatcher = OutboxDispatcher.CreateForConnectionString(
            _workerConnectionString,
            [consumer],
            new InboxConsumerExecutor());

        var first =
            await dispatcher.DispatchEventAsync(RetryEventId);

        Assert(
            first.Kind == OutboxDispatchOutcomeKind.RetryScheduled
            && first.AttemptNo == 1
            && first.RetryDelay is not null,
            "El primer fallo debe programar reintento.");

        await ForceRetryDueAsync(RetryEventId);

        var second =
            await dispatcher.DispatchEventAsync(RetryEventId);

        Assert(
            second.Kind == OutboxDispatchOutcomeKind.RetryScheduled
            && second.AttemptNo == 2
            && second.RetryDelay is not null,
            "El segundo fallo debe programar el ultimo reintento.");

        Assert(
            second.RetryDelay > first.RetryDelay,
            "El retroceso debe crecer exponencialmente.");

        await ForceRetryDueAsync(RetryEventId);

        var third =
            await dispatcher.DispatchEventAsync(RetryEventId);

        Assert(
            third.Kind == OutboxDispatchOutcomeKind.Review
            && third.AttemptNo == OutboxRetryPolicy.MaxAttempts,
            "El tercer fallo debe terminar en revision.");

        var fourth =
            await dispatcher.DispatchEventAsync(RetryEventId);

        Assert(
            fourth.Kind == OutboxDispatchOutcomeKind.None,
            "Un evento en REVIEW no debe ejecutar un cuarto intento.");

        var observation =
            await ReadFailureObservationAsync(RetryEventId);

        Assert(
            observation.OutboxStatus == "REVIEW",
            "El outbox fallido debe terminar en REVIEW.");
        Assert(
            observation.JobStatus == "REVIEW",
            "El trabajo fallido debe terminar en REVIEW.");
        Assert(
            observation.AttemptCount == 3,
            "El trabajo debe conservar exactamente tres intentos.");
        Assert(
            observation.AttemptRows == 3
            && observation.DistinctAttemptNumbers == 3,
            "job_attempt debe conservar tres evidencias unicas.");
        Assert(
            observation.FailureRows == 3
            && observation.ValidDigestRows == 3,
            "Cada fallo debe conservar codigo y digest seguro.");
        Assert(
            observation.InboxRows == 0,
            "Un efecto fallido no debe confirmar una fila de inbox.");

        Console.WriteLine(
            "OK: maximo 3 intentos con backoff+jitter; fallos observables y sin inbox parcial.");
    }

    private static OutboxMessageDraft CreateEvent(
        Guid eventId,
        string eventName)
    {
        return OutboxMessageDraft.Create(
            eventName,
            schemaVersion: 1,
            aggregateType: "IDENTITY.USER_PROFILE",
            aggregateId: AccountId,
            payloadJson: $$"""{"accountId":"{{AccountId:D}}"}""",
            correlationId: CorrelationId,
            eventId: eventId);
    }

    private static async Task UpdateDisplayNameAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string displayName,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE identity.user_profile
            SET display_name = @display_name
            WHERE account_id = @account_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "display_name",
            displayName);
        command.Parameters.AddWithValue(
            "account_id",
            AccountId);

        var changed =
            await command.ExecuteNonQueryAsync(cancellationToken);

        Assert(
            changed == 1,
            "La decision sintetica debe modificar exactamente un perfil.");
    }

    private async Task<string> ReadDisplayNameAsync()
    {
        return await _transactionExecutor.ExecuteAsync(
            _sessionContext,
            async (connection, transaction, token) =>
            {
                const string sql = """
                    SELECT display_name
                    FROM identity.user_profile
                    WHERE account_id = @account_id;
                    """;

                await using var command =
                    new NpgsqlCommand(sql, connection, transaction);

                command.Parameters.AddWithValue(
                    "account_id",
                    AccountId);

                var value =
                    await command.ExecuteScalarAsync(token);

                return value as string
                    ?? throw new InvalidOperationException(
                        "No se encontro el perfil fixture BL-MVP-015.");
            });
    }

    private async Task<long> CountIdempotencyAsync(
        string operationCode,
        string idempotencyKey)
    {
        return await _transactionExecutor.ExecuteAsync(
            _sessionContext,
            async (connection, transaction, token) =>
            {
                const string sql = """
                    SELECT count(*)
                    FROM ops.idempotency_record
                    WHERE
                        account_id = @account_id
                        AND operation_code = @operation_code
                        AND idempotency_key = @idempotency_key;
                    """;

                await using var command =
                    new NpgsqlCommand(sql, connection, transaction);

                command.Parameters.AddWithValue("account_id", AccountId);
                command.Parameters.AddWithValue(
                    "operation_code",
                    operationCode);
                command.Parameters.AddWithValue(
                    "idempotency_key",
                    idempotencyKey);

                return Convert.ToInt64(
                    await command.ExecuteScalarAsync(token),
                    CultureInfo.InvariantCulture);
            });
    }

    private async Task<long> CountOutboxAsync(Guid eventId)
    {
        return await _transactionExecutor.ExecuteAsync(
            _sessionContext,
            async (connection, transaction, token) =>
            {
                const string sql = """
                    SELECT count(*)
                    FROM ops.outbox_message
                    WHERE event_id = @event_id;
                    """;

                await using var command =
                    new NpgsqlCommand(sql, connection, transaction);

                command.Parameters.AddWithValue("event_id", eventId);

                return Convert.ToInt64(
                    await command.ExecuteScalarAsync(token),
                    CultureInfo.InvariantCulture);
            });
    }

    private async Task ForcePendingAsync(Guid eventId)
    {
        await ExecuteWorkerNonQueryAsync(
            """
            UPDATE ops.outbox_message
            SET
                status_code = 'PENDING',
                next_attempt_at = NULL
            WHERE event_id = @event_id;
            """,
            eventId);
    }

    private async Task ForceRetryDueAsync(Guid eventId)
    {
        await ExecuteWorkerNonQueryAsync(
            """
            UPDATE ops.outbox_message
            SET next_attempt_at = CURRENT_TIMESTAMP - INTERVAL '1 second'
            WHERE
                event_id = @event_id
                AND status_code = 'RETRY_WAIT';

            UPDATE ops.background_job
            SET next_attempt_at = CURRENT_TIMESTAMP - INTERVAL '1 second'
            WHERE
                job_id = @event_id
                AND status_code = 'RETRY_WAIT';
            """,
            eventId);
    }

    private async Task ExecuteWorkerNonQueryAsync(
        string sql,
        Guid eventId)
    {
        await using var connection =
            new NpgsqlConnection(_workerConnectionString);

        await connection.OpenAsync();

        await using var transaction =
            await connection.BeginTransactionAsync();

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue("event_id", eventId);
        await command.ExecuteNonQueryAsync();
        await transaction.CommitAsync();
    }

    private async Task<long> ReadProjectionVersionAsync(
        string projectionCode,
        string consumerCode)
    {
        await using var connection =
            new NpgsqlConnection(_workerConnectionString);

        await connection.OpenAsync();

        const string sql = """
            SELECT projection_version
            FROM ops.read_model_checkpoint
            WHERE
                projection_code = @projection_code
                AND consumer_code = @consumer_code;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("projection_code", projectionCode);
        command.Parameters.AddWithValue("consumer_code", consumerCode);

        return Convert.ToInt64(
            await command.ExecuteScalarAsync(),
            CultureInfo.InvariantCulture);
    }

    private async Task<long> CountInboxAsync(
        Guid eventId,
        string consumerCode)
    {
        await using var connection =
            new NpgsqlConnection(_workerConnectionString);

        await connection.OpenAsync();

        const string sql = """
            SELECT count(*)
            FROM ops.inbox_message
            WHERE
                event_id = @event_id
                AND consumer_code = @consumer_code
                AND result_code = 'PROCESSED';
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("event_id", eventId);
        command.Parameters.AddWithValue("consumer_code", consumerCode);

        return Convert.ToInt64(
            await command.ExecuteScalarAsync(),
            CultureInfo.InvariantCulture);
    }

    private async Task<FailureObservation> ReadFailureObservationAsync(
        Guid eventId)
    {
        await using var connection =
            new NpgsqlConnection(_workerConnectionString);

        await connection.OpenAsync();

        const string sql = """
            SELECT
                o.status_code,
                j.status_code,
                j.attempt_count,
                count(a.*),
                count(DISTINCT a.attempt_no),
                count(*) FILTER (
                    WHERE
                        a.result_code = 'FAILURE'
                        AND a.error_code = 'SYNTHETIC_FAILURE'
                ),
                count(*) FILTER (
                    WHERE octet_length(a.error_digest) = 32
                ),
                (
                    SELECT count(*)
                    FROM ops.inbox_message i
                    WHERE i.event_id = o.event_id
                )
            FROM ops.outbox_message o
            JOIN ops.background_job j
                ON j.job_id = o.event_id
            LEFT JOIN ops.job_attempt a
                ON a.job_id = j.job_id
            WHERE o.event_id = @event_id
            GROUP BY
                o.event_id,
                o.status_code,
                j.status_code,
                j.attempt_count;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("event_id", eventId);

        await using var reader = await command.ExecuteReaderAsync();

        if (!await reader.ReadAsync())
        {
            throw new InvalidOperationException(
                "No se encontro evidencia del evento fallido.");
        }

        return new FailureObservation(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetInt32(2),
            reader.GetInt64(3),
            reader.GetInt64(4),
            reader.GetInt64(5),
            reader.GetInt64(6),
            reader.GetInt64(7));
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private sealed record FailureObservation(
        string OutboxStatus,
        string JobStatus,
        int AttemptCount,
        long AttemptRows,
        long DistinctAttemptNumbers,
        long FailureRows,
        long ValidDigestRows,
        long InboxRows);

    private sealed class CheckpointConsumer(
        string consumerCode,
        string eventName,
        string projectionCode)
        : IOutboxConsumer
    {
        public string ConsumerCode { get; } = consumerCode;

        public int InvocationCount { get; private set; }

        public bool CanHandle(string candidateEventName, int schemaVersion)
        {
            return schemaVersion == 1
                && string.Equals(
                    candidateEventName,
                    eventName,
                    StringComparison.Ordinal);
        }

        public async Task HandleAsync(
            OutboxEnvelope message,
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            CancellationToken cancellationToken)
        {
            InvocationCount++;

            const string sql = """
                INSERT INTO ops.read_model_checkpoint (
                    projection_code,
                    consumer_code,
                    last_event_id,
                    last_occurred_at,
                    projection_version,
                    updated_at
                )
                VALUES (
                    @projection_code,
                    @consumer_code,
                    @event_id,
                    @occurred_at,
                    1,
                    CURRENT_TIMESTAMP
                )
                ON CONFLICT (projection_code, consumer_code)
                DO UPDATE SET
                    last_event_id = EXCLUDED.last_event_id,
                    last_occurred_at = EXCLUDED.last_occurred_at,
                    projection_version =
                        ops.read_model_checkpoint.projection_version + 1,
                    updated_at = CURRENT_TIMESTAMP;
                """;

            await using var command =
                new NpgsqlCommand(sql, connection, transaction);

            command.Parameters.AddWithValue(
                "projection_code",
                projectionCode);
            command.Parameters.AddWithValue(
                "consumer_code",
                ConsumerCode);
            command.Parameters.AddWithValue(
                "event_id",
                message.EventId);
            command.Parameters.AddWithValue(
                "occurred_at",
                message.OccurredAt);

            await command.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    private sealed class FailingConsumer(
        string consumerCode,
        string eventName)
        : IOutboxConsumer
    {
        public string ConsumerCode { get; } = consumerCode;

        public bool CanHandle(string candidateEventName, int schemaVersion)
        {
            return schemaVersion == 1
                && string.Equals(
                    candidateEventName,
                    eventName,
                    StringComparison.Ordinal);
        }

        public Task HandleAsync(
            OutboxEnvelope message,
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            CancellationToken cancellationToken)
        {
            _ = message;
            _ = connection;
            _ = transaction;
            _ = cancellationToken;

            throw new OutboxConsumerException("SYNTHETIC_FAILURE");
        }
    }
}
