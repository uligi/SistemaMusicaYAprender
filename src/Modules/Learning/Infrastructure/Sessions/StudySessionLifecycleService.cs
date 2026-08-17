using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Learning.Infrastructure.Sessions;

public sealed record StudySessionLifecycleView(
    Guid StudySessionId,
    string StatusCode,
    DateTimeOffset StartedAt,
    DateTimeOffset? EndedAt,
    long Version,
    bool ReusedExisting);

public sealed class StudySessionLifecycleNotFoundException : Exception
{
    public StudySessionLifecycleNotFoundException()
        : base("La sesión de estudio no existe o no pertenece a la cuenta.")
    {
    }
}

public sealed class StudySessionLifecycleVersionConflictException : Exception
{
    public StudySessionLifecycleVersionConflictException()
        : base("La sesión cambió desde la versión que intentabas modificar.")
    {
    }
}

public sealed class StudySessionLifecycleTransitionConflictException : Exception
{
    public StudySessionLifecycleTransitionConflictException()
        : base("La transición solicitada no es válida para el estado actual de la sesión.")
    {
    }
}

public sealed class StudySessionLifecycleService(
    IRlsTransactionExecutor transactionExecutor)
{
    private const string OperationCode = "LEARNING.STUDY_SESSION.LIFECYCLE";

    public Task<StudySessionLifecycleView> ReadAsync(
        DatabaseSessionContext context,
        Guid studySessionId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);
        ValidateSessionId(studySessionId);

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
                await ReadOwnedAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    studySessionId,
                    reusedExisting: true,
                    token)
                ?? throw new StudySessionLifecycleNotFoundException(),
            cancellationToken);
    }

    public Task<StudySessionLifecycleView> PauseAsync(
        DatabaseSessionContext context,
        Guid studySessionId,
        long expectedVersion,
        CancellationToken cancellationToken = default) =>
        TransitionAsync(
            context,
            studySessionId,
            expectedVersion,
            expectedStatus: "ACTIVE",
            targetStatus: "PAUSED",
            complete: false,
            cancellationToken);

    public Task<StudySessionLifecycleView> ResumeAsync(
        DatabaseSessionContext context,
        Guid studySessionId,
        long expectedVersion,
        CancellationToken cancellationToken = default) =>
        TransitionAsync(
            context,
            studySessionId,
            expectedVersion,
            expectedStatus: "PAUSED",
            targetStatus: "ACTIVE",
            complete: false,
            cancellationToken);

    public Task<StudySessionLifecycleView> CompleteAsync(
        DatabaseSessionContext context,
        Guid studySessionId,
        long expectedVersion,
        CancellationToken cancellationToken = default) =>
        CompleteCoreAsync(
            context,
            studySessionId,
            expectedVersion,
            cancellationToken);

    private Task<StudySessionLifecycleView> TransitionAsync(
        DatabaseSessionContext context,
        Guid studySessionId,
        long expectedVersion,
        string expectedStatus,
        string targetStatus,
        bool complete,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(context);
        ValidateSessionId(studySessionId);
        ValidateExpectedVersion(expectedVersion);

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await AcquireLockAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    studySessionId,
                    token);

                var current = await ReadOwnedAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    studySessionId,
                    reusedExisting: true,
                    token)
                    ?? throw new StudySessionLifecycleNotFoundException();

                if (current.Version != expectedVersion)
                {
                    throw new StudySessionLifecycleVersionConflictException();
                }

                if (string.Equals(current.StatusCode, targetStatus, StringComparison.Ordinal)
                    && current.EndedAt is null)
                {
                    return current;
                }

                if (!string.Equals(current.StatusCode, expectedStatus, StringComparison.Ordinal)
                    || current.EndedAt is not null)
                {
                    throw new StudySessionLifecycleTransitionConflictException();
                }

                return await UpdateAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    studySessionId,
                    expectedVersion,
                    expectedStatus,
                    targetStatus,
                    complete,
                    token);
            },
            cancellationToken);
    }

    private Task<StudySessionLifecycleView> CompleteCoreAsync(
        DatabaseSessionContext context,
        Guid studySessionId,
        long expectedVersion,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(context);
        ValidateSessionId(studySessionId);
        ValidateExpectedVersion(expectedVersion);

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await AcquireLockAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    studySessionId,
                    token);

                var current = await ReadOwnedAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    studySessionId,
                    reusedExisting: true,
                    token)
                    ?? throw new StudySessionLifecycleNotFoundException();

                if (current.Version != expectedVersion)
                {
                    throw new StudySessionLifecycleVersionConflictException();
                }

                if (string.Equals(current.StatusCode, "COMPLETED", StringComparison.Ordinal)
                    && current.EndedAt is not null)
                {
                    return current;
                }

                if (current.EndedAt is not null
                    || !(string.Equals(current.StatusCode, "ACTIVE", StringComparison.Ordinal)
                        || string.Equals(current.StatusCode, "PAUSED", StringComparison.Ordinal)))
                {
                    throw new StudySessionLifecycleTransitionConflictException();
                }

                return await UpdateAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    studySessionId,
                    expectedVersion,
                    current.StatusCode,
                    "COMPLETED",
                    complete: true,
                    token);
            },
            cancellationToken);
    }

    private static async Task AcquireLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid studySessionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_advisory_xact_lock(
                hashtextextended(@lock_key, 0)
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "lock_key",
            NpgsqlDbType.Text,
            $"{OperationCode}:{accountId:N}:{studySessionId:N}");
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<StudySessionLifecycleView?> ReadOwnedAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid studySessionId,
        bool reusedExisting,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                session.study_session_id,
                session.status_code,
                session.started_at,
                session.ended_at,
                session.version
            FROM learning.study_session AS session
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id = session.learner_profile_id
            WHERE session.study_session_id = @study_session_id
              AND profile.account_id = @account_id
            LIMIT 1
            FOR UPDATE OF session;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("study_session_id", NpgsqlDbType.Uuid, studySessionId);
        command.Parameters.AddWithValue("account_id", NpgsqlDbType.Uuid, accountId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new StudySessionLifecycleView(
            reader.GetGuid(0),
            reader.GetString(1),
            ToUtcOffset(reader.GetDateTime(2)),
            reader.IsDBNull(3) ? null : ToUtcOffset(reader.GetDateTime(3)),
            reader.GetInt64(4),
            reusedExisting);
    }

    private static async Task<StudySessionLifecycleView> UpdateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid studySessionId,
        long expectedVersion,
        string expectedStatus,
        string targetStatus,
        bool complete,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE learning.study_session AS session
            SET
                status_code = @target_status,
                ended_at = CASE
                    WHEN @complete THEN CURRENT_TIMESTAMP
                    ELSE NULL
                END
            FROM learning.learner_profile AS profile
            WHERE session.learner_profile_id = profile.learner_profile_id
              AND profile.account_id = @account_id
              AND session.study_session_id = @study_session_id
              AND session.version = @expected_version
              AND session.status_code = @expected_status
              AND session.ended_at IS NULL
            RETURNING
                session.study_session_id,
                session.status_code,
                session.started_at,
                session.ended_at,
                session.version;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("target_status", NpgsqlDbType.Varchar, targetStatus);
        command.Parameters.AddWithValue("complete", NpgsqlDbType.Boolean, complete);
        command.Parameters.AddWithValue("account_id", NpgsqlDbType.Uuid, accountId);
        command.Parameters.AddWithValue("study_session_id", NpgsqlDbType.Uuid, studySessionId);
        command.Parameters.AddWithValue("expected_version", NpgsqlDbType.Bigint, expectedVersion);
        command.Parameters.AddWithValue("expected_status", NpgsqlDbType.Varchar, expectedStatus);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new StudySessionLifecycleVersionConflictException();
        }

        return new StudySessionLifecycleView(
            reader.GetGuid(0),
            reader.GetString(1),
            ToUtcOffset(reader.GetDateTime(2)),
            reader.IsDBNull(3) ? null : ToUtcOffset(reader.GetDateTime(3)),
            reader.GetInt64(4),
            ReusedExisting: false);
    }

    private static void ValidateSessionId(Guid studySessionId)
    {
        if (studySessionId == Guid.Empty)
        {
            throw new ArgumentException("La sesión de estudio es obligatoria.", nameof(studySessionId));
        }
    }

    private static void ValidateExpectedVersion(long expectedVersion)
    {
        if (expectedVersion <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(expectedVersion),
                "La versión esperada debe ser mayor que cero.");
        }
    }

    private static DateTimeOffset ToUtcOffset(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));
}
