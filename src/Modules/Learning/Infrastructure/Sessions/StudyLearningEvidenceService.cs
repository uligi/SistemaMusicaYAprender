using System.Text.Json;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Learning.Infrastructure.Sessions;

public sealed record StudyLearningEvidenceView(
    Guid EvidenceId,
    Guid EvaluationId,
    Guid CompetencyId,
    Guid RecordingId,
    decimal Outcome,
    int EvidenceVersion,
    DateTimeOffset ConfirmedAt,
    bool ReusedExisting);

public sealed class StudyLearningEvidencePendingException : Exception
{
    public StudyLearningEvidencePendingException()
        : base("La instancia todavía no tiene una evaluación válida que pueda confirmar evidencia.")
    {
    }
}

public sealed class StudyLearningEvidenceDriftException : Exception
{
    public StudyLearningEvidenceDriftException()
        : base("La evidencia o su notificación no coincide con el linaje evaluado y requiere revisión trazable.")
    {
    }
}

public sealed class StudyLearningEvidenceService(
    IRlsTransactionExecutor transactionExecutor,
    ITransactionalOutboxWriter outboxWriter)
{
    public const string ProgressNotificationEventName = "LEARNING.EVIDENCE.CONFIRMED";
    public const string ProgressNotificationAggregateType = "LEARNING_EVIDENCE";
    private const string EvidenceOperation = "LEARNING.EVIDENCE.ENSURE";

    public Task<StudyLearningEvidenceView> ReadAsync(
        DatabaseSessionContext context,
        Guid instanceId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (instanceId == Guid.Empty)
        {
            throw new ArgumentException("La instancia es obligatoria.", nameof(instanceId));
        }

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                var target = await ReadTargetAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    instanceId,
                    token)
                    ?? throw new StudyLearningEvidencePendingException();

                ValidateTarget(target);

                var evidence = await ReadStoredEvidenceAsync(
                    connection,
                    transaction,
                    target.EvaluationId,
                    target.CompetencyId,
                    token)
                    ?? throw new StudyLearningEvidencePendingException();

                ValidateStoredEvidence(evidence, target);
                await ValidateSingleProgressNotificationAsync(
                    connection,
                    transaction,
                    evidence,
                    target,
                    token);

                return ToView(evidence, reusedExisting: true);
            },
            cancellationToken);
    }

    public Task<StudyLearningEvidenceView> EnsureAsync(
        DatabaseSessionContext context,
        Guid instanceId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (instanceId == Guid.Empty)
        {
            throw new ArgumentException("La instancia es obligatoria.", nameof(instanceId));
        }

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await AcquireLockAsync(
                    connection,
                    transaction,
                    $"{EvidenceOperation}:{context.AccountId:N}:{instanceId:N}",
                    token);

                var target = await ReadTargetAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    instanceId,
                    token)
                    ?? throw new StudyLearningEvidencePendingException();

                ValidateTarget(target);

                var existing = await ReadStoredEvidenceAsync(
                    connection,
                    transaction,
                    target.EvaluationId,
                    target.CompetencyId,
                    token);

                if (existing is not null)
                {
                    ValidateStoredEvidence(existing, target);
                    await ValidateSingleProgressNotificationAsync(
                        connection,
                        transaction,
                        existing,
                        target,
                        token);
                    return ToView(existing, reusedExisting: true);
                }

                var evidenceId = Guid.CreateVersion7();
                var confirmedAt = await InsertEvidenceAsync(
                    connection,
                    transaction,
                    evidenceId,
                    target,
                    token);

                var notification = OutboxMessageDraft.Create(
                    ProgressNotificationEventName,
                    schemaVersion: 1,
                    ProgressNotificationAggregateType,
                    evidenceId,
                    JsonSerializer.Serialize(
                        new
                        {
                            evidenceId,
                            evaluationId = target.EvaluationId,
                            competencyId = target.CompetencyId,
                            recordingId = target.RecordingId,
                            outcome = target.Outcome,
                            evidenceVersion = 1,
                        }),
                    correlationId: evidenceId,
                    causationId: target.EvaluationId);

                await outboxWriter.EnqueueAsync(
                    connection,
                    transaction,
                    notification,
                    token);

                return new StudyLearningEvidenceView(
                    evidenceId,
                    target.EvaluationId,
                    target.CompetencyId,
                    target.RecordingId,
                    target.Outcome,
                    1,
                    confirmedAt,
                    ReusedExisting: false);
            },
            cancellationToken);
    }

    private static async Task AcquireLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string lockKey,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_advisory_xact_lock(
                hashtextextended(@lock_key, 0)
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("lock_key", NpgsqlDbType.Text, lockKey);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<EvidenceTarget?> ReadTargetAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid instanceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                profile.learner_profile_id,
                evaluation.evaluation_id,
                submission.submission_id,
                revision.exercise_revision_id,
                definition.exercise_id,
                definition.competency_id,
                definition.recording_id,
                session.recording_id,
                evaluation.score,
                evaluation.evaluator_version,
                octet_length(evaluation.result_digest)
            FROM learning.exercise_instance AS instance
            INNER JOIN learning.study_session AS session
                ON session.study_session_id = instance.study_session_id
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id = session.learner_profile_id
            INNER JOIN learning.answer_submission AS submission
                ON submission.instance_id = instance.instance_id
               AND submission.submission_no = 1
               AND submission.status_code = 'CONFIRMED'
            INNER JOIN learning.evaluation_result AS evaluation
                ON evaluation.submission_id = submission.submission_id
            INNER JOIN learning.exercise_revision AS revision
                ON revision.exercise_revision_id = instance.exercise_revision_id
            INNER JOIN learning.exercise_definition AS definition
                ON definition.exercise_id = revision.exercise_id
            WHERE instance.instance_id = @instance_id
              AND profile.account_id = @account_id
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("instance_id", NpgsqlDbType.Uuid, instanceId);
        command.Parameters.AddWithValue("account_id", NpgsqlDbType.Uuid, accountId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new EvidenceTarget(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2),
            reader.GetGuid(3),
            reader.GetGuid(4),
            reader.GetGuid(5),
            reader.GetGuid(6),
            reader.GetGuid(7),
            reader.GetDecimal(8),
            reader.GetString(9),
            reader.GetInt32(10));
    }

    private static void ValidateTarget(EvidenceTarget target)
    {
        if (target.RecordingId != target.SessionRecordingId
            || target.Outcome is < 0m or > 1m
            || string.IsNullOrWhiteSpace(target.EvaluatorVersion)
            || target.ResultDigestLength != 32)
        {
            throw new StudyLearningEvidenceDriftException();
        }
    }

    private static async Task<StoredEvidence?> ReadStoredEvidenceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid evaluationId,
        Guid competencyId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                evidence_id,
                learner_profile_id,
                evaluation_id,
                competency_id,
                recording_id,
                outcome,
                evidence_version,
                confirmed_at,
                superseded_by
            FROM learning.learning_evidence
            WHERE evaluation_id = @evaluation_id
              AND competency_id = @competency_id
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("evaluation_id", NpgsqlDbType.Uuid, evaluationId);
        command.Parameters.AddWithValue("competency_id", NpgsqlDbType.Uuid, competencyId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new StoredEvidence(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2),
            reader.GetGuid(3),
            reader.GetGuid(4),
            reader.GetDecimal(5),
            reader.GetInt32(6),
            ToUtcOffset(reader.GetDateTime(7)),
            reader.IsDBNull(8) ? null : reader.GetGuid(8));
    }

    private static void ValidateStoredEvidence(
        StoredEvidence existing,
        EvidenceTarget target)
    {
        if (existing.LearnerProfileId != target.LearnerProfileId
            || existing.EvaluationId != target.EvaluationId
            || existing.CompetencyId != target.CompetencyId
            || existing.RecordingId != target.RecordingId
            || existing.Outcome != target.Outcome
            || existing.EvidenceVersion != 1
            || existing.SupersededBy is not null)
        {
            throw new StudyLearningEvidenceDriftException();
        }
    }

    private static async Task<DateTimeOffset> InsertEvidenceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid evidenceId,
        EvidenceTarget target,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO learning.learning_evidence (
                evidence_id,
                learner_profile_id,
                evaluation_id,
                competency_id,
                recording_id,
                outcome,
                evidence_version,
                confirmed_at
            )
            VALUES (
                @evidence_id,
                @learner_profile_id,
                @evaluation_id,
                @competency_id,
                @recording_id,
                @outcome,
                1,
                CURRENT_TIMESTAMP
            )
            RETURNING confirmed_at;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("evidence_id", NpgsqlDbType.Uuid, evidenceId);
        command.Parameters.AddWithValue(
            "learner_profile_id",
            NpgsqlDbType.Uuid,
            target.LearnerProfileId);
        command.Parameters.AddWithValue("evaluation_id", NpgsqlDbType.Uuid, target.EvaluationId);
        command.Parameters.AddWithValue("competency_id", NpgsqlDbType.Uuid, target.CompetencyId);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, target.RecordingId);
        command.Parameters.AddWithValue("outcome", NpgsqlDbType.Numeric, target.Outcome);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not DateTime confirmedAt)
        {
            throw new InvalidOperationException("No se pudo confirmar la evidencia de aprendizaje.");
        }

        return ToUtcOffset(confirmedAt);
    }

    private static async Task ValidateSingleProgressNotificationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        StoredEvidence evidence,
        EvidenceTarget target,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                event_id,
                schema_version,
                aggregate_id,
                correlation_id,
                causation_id,
                payload::text
            FROM ops.outbox_message
            WHERE event_name = @event_name
              AND aggregate_type = @aggregate_type
              AND aggregate_id = @aggregate_id
            ORDER BY occurred_at, event_id;
            """;

        var notifications = new List<StoredNotification>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("event_name", NpgsqlDbType.Text, ProgressNotificationEventName);
        command.Parameters.AddWithValue(
            "aggregate_type",
            NpgsqlDbType.Varchar,
            ProgressNotificationAggregateType);
        command.Parameters.AddWithValue("aggregate_id", NpgsqlDbType.Uuid, evidence.EvidenceId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            notifications.Add(
                new StoredNotification(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetGuid(2),
                    reader.GetGuid(3),
                    reader.IsDBNull(4) ? null : reader.GetGuid(4),
                    reader.GetString(5)));
        }

        if (notifications.Count != 1)
        {
            throw new StudyLearningEvidenceDriftException();
        }

        var notification = notifications[0];
        if (notification.SchemaVersion != 1
            || notification.AggregateId != evidence.EvidenceId
            || notification.CorrelationId != evidence.EvidenceId
            || notification.CausationId != target.EvaluationId)
        {
            throw new StudyLearningEvidenceDriftException();
        }

        ValidateNotificationPayload(notification.PayloadJson, evidence, target);
    }

    private static void ValidateNotificationPayload(
        string payloadJson,
        StoredEvidence evidence,
        EvidenceTarget target)
    {
        try
        {
            using var document = JsonDocument.Parse(payloadJson);
            var root = document.RootElement;

            if (ReadGuid(root, "evidenceId") != evidence.EvidenceId
                || ReadGuid(root, "evaluationId") != target.EvaluationId
                || ReadGuid(root, "competencyId") != target.CompetencyId
                || ReadGuid(root, "recordingId") != target.RecordingId
                || ReadDecimal(root, "outcome") != target.Outcome
                || ReadInt32(root, "evidenceVersion") != 1)
            {
                throw new StudyLearningEvidenceDriftException();
            }
        }
        catch (JsonException)
        {
            throw new StudyLearningEvidenceDriftException();
        }
        catch (InvalidOperationException)
        {
            throw new StudyLearningEvidenceDriftException();
        }
    }

    private static Guid ReadGuid(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var element)
            || element.ValueKind != JsonValueKind.String
            || !Guid.TryParse(element.GetString(), out var value))
        {
            throw new StudyLearningEvidenceDriftException();
        }

        return value;
    }

    private static decimal ReadDecimal(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var element)
            || element.ValueKind != JsonValueKind.Number
            || !element.TryGetDecimal(out var value))
        {
            throw new StudyLearningEvidenceDriftException();
        }

        return value;
    }

    private static int ReadInt32(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var element)
            || element.ValueKind != JsonValueKind.Number
            || !element.TryGetInt32(out var value))
        {
            throw new StudyLearningEvidenceDriftException();
        }

        return value;
    }

    private static StudyLearningEvidenceView ToView(
        StoredEvidence evidence,
        bool reusedExisting) =>
        new(
            evidence.EvidenceId,
            evidence.EvaluationId,
            evidence.CompetencyId,
            evidence.RecordingId,
            evidence.Outcome,
            evidence.EvidenceVersion,
            evidence.ConfirmedAt,
            reusedExisting);

    private static DateTimeOffset ToUtcOffset(DateTime value)
    {
        var utc = value.Kind == DateTimeKind.Utc
            ? value
            : DateTime.SpecifyKind(value, DateTimeKind.Utc);
        return new DateTimeOffset(utc);
    }

    private sealed record EvidenceTarget(
        Guid LearnerProfileId,
        Guid EvaluationId,
        Guid SubmissionId,
        Guid ExerciseRevisionId,
        Guid ExerciseId,
        Guid CompetencyId,
        Guid RecordingId,
        Guid SessionRecordingId,
        decimal Outcome,
        string EvaluatorVersion,
        int ResultDigestLength);

    private sealed record StoredEvidence(
        Guid EvidenceId,
        Guid LearnerProfileId,
        Guid EvaluationId,
        Guid CompetencyId,
        Guid RecordingId,
        decimal Outcome,
        int EvidenceVersion,
        DateTimeOffset ConfirmedAt,
        Guid? SupersededBy);

    private sealed record StoredNotification(
        Guid EventId,
        int SchemaVersion,
        Guid AggregateId,
        Guid CorrelationId,
        Guid? CausationId,
        string PayloadJson);
}
