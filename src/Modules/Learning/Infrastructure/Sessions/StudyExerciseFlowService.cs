using System.Security.Cryptography;
using System.Text;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Learning.Infrastructure.Sessions;

public sealed record FrozenExerciseOption(
    Guid InstanceItemId,
    int DisplayOrder,
    string Value);

public sealed record FrozenExerciseSubmission(
    Guid SubmissionId,
    string StatusCode,
    DateTimeOffset SubmittedAt,
    Guid SelectedInstanceItemId);

public sealed record FrozenExerciseView(
    Guid InstanceId,
    Guid StudySessionId,
    string StateCode,
    int InstanceNo,
    DateTimeOffset DeliveredAt,
    long Version,
    int ExerciseRevisionNo,
    string Prompt,
    int LineNo,
    string MaskedJapaneseText,
    IReadOnlyList<FrozenExerciseOption> Options,
    FrozenExerciseSubmission? Submission);

public sealed record FrozenExercisePrepared(
    Guid InstanceId,
    bool ReusedExisting);

public sealed record AnswerSubmissionResult(
    Guid SubmissionId,
    Guid InstanceId,
    string StatusCode,
    DateTimeOffset SubmittedAt,
    Guid SelectedInstanceItemId,
    bool ReusedExisting);

public sealed class StudyExerciseSessionUnavailableException : Exception
{
    public StudyExerciseSessionUnavailableException()
        : base("La sesión privada ya no está disponible para preparar un ejercicio.")
    {
    }
}

public sealed class StudyExerciseNoEligibleExerciseException : Exception
{
    public StudyExerciseNoEligibleExerciseException()
        : base("La publicación de la sesión no contiene un completar espacios elegible.")
    {
    }
}

public sealed class StudyExerciseInstanceNotFoundException : Exception
{
    public StudyExerciseInstanceNotFoundException()
        : base("La instancia de ejercicio no existe o no pertenece a la cuenta.")
    {
    }
}

public sealed class StudyExerciseInvalidSelectionException : Exception
{
    public StudyExerciseInvalidSelectionException()
        : base("La opción elegida no pertenece a la instancia congelada.")
    {
    }
}

public sealed class StudyExerciseAlreadySubmittedException : Exception
{
    public StudyExerciseAlreadySubmittedException()
        : base("La instancia ya tiene una respuesta confirmada diferente.")
    {
    }
}

public sealed class StudyExerciseIdempotencyConflictException : Exception
{
    public StudyExerciseIdempotencyConflictException()
        : base("La clave de idempotencia ya fue usada con otra respuesta.")
    {
    }
}

public sealed class StudyExerciseFlowService(
    IRlsTransactionExecutor transactionExecutor)
{
    private const string PrepareOperation = "LEARNING.EXERCISE_INSTANCE.PREPARE";
    private const string SubmitOperation = "LEARNING.ANSWER_SUBMISSION.CONFIRM";
    private const int MinimumIdempotencyKeyLength = 8;
    private const int MaximumIdempotencyKeyLength = 128;

    public Task<FrozenExercisePrepared> PrepareFirstAsync(
        DatabaseSessionContext context,
        Guid studySessionId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (studySessionId == Guid.Empty)
        {
            throw new ArgumentException(
                "La sesión de estudio es obligatoria.",
                nameof(studySessionId));
        }

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await AcquireLockAsync(
                    connection,
                    transaction,
                    $"{PrepareOperation}:{context.AccountId:N}:{studySessionId:N}",
                    token);

                var session = await ReadOwnedSessionAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    studySessionId,
                    token)
                    ?? throw new StudyExerciseSessionUnavailableException();

                var existing = await ReadExistingInstanceIdAsync(
                    connection,
                    transaction,
                    studySessionId,
                    token);

                if (existing.HasValue)
                {
                    return new FrozenExercisePrepared(
                        existing.Value,
                        true);
                }

                var candidate = await ResolvePublishedExerciseAsync(
                    connection,
                    transaction,
                    session,
                    token)
                    ?? throw new StudyExerciseNoEligibleExerciseException();

                var sourceOptions = await ReadSourceOptionsAsync(
                    connection,
                    transaction,
                    candidate.ExerciseRevisionId,
                    token);

                ValidateSourceOptions(sourceOptions);

                var seed = Convert
                    .ToHexString(RandomNumberGenerator.GetBytes(16))
                    .ToLowerInvariant();

                var instanceId = Guid.CreateVersion7();

                await InsertInstanceAsync(
                    connection,
                    transaction,
                    instanceId,
                    studySessionId,
                    candidate.ExerciseRevisionId,
                    seed,
                    token);

                var ordered = sourceOptions
                    .OrderBy(
                        option => BuildOrderKey(seed, option.SourceItemId),
                        StringComparer.Ordinal)
                    .ThenBy(option => option.SourceItemId)
                    .ToArray();

                for (var index = 0; index < ordered.Length; index++)
                {
                    await InsertInstanceItemAsync(
                        connection,
                        transaction,
                        instanceId,
                        ordered[index],
                        index + 1,
                        token);
                }

                return new FrozenExercisePrepared(
                    instanceId,
                    false);
            },
            cancellationToken);
    }

    public Task<FrozenExerciseView> ReadAsync(
        DatabaseSessionContext context,
        Guid instanceId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (instanceId == Guid.Empty)
        {
            throw new ArgumentException(
                "La instancia es obligatoria.",
                nameof(instanceId));
        }

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
                await ReadViewCoreAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    instanceId,
                    token)
                ?? throw new StudyExerciseInstanceNotFoundException(),
            cancellationToken);
    }

    public Task<AnswerSubmissionResult> SubmitAsync(
        DatabaseSessionContext context,
        Guid instanceId,
        Guid selectedInstanceItemId,
        string idempotencyKey,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (instanceId == Guid.Empty)
        {
            throw new ArgumentException(
                "La instancia es obligatoria.",
                nameof(instanceId));
        }

        if (selectedInstanceItemId == Guid.Empty)
        {
            throw new ArgumentException(
                "Debes elegir una opción antes de confirmar.",
                nameof(selectedInstanceItemId));
        }

        var normalizedIdempotencyKey =
            NormalizeIdempotencyKey(idempotencyKey);

        var answerDigest = SHA256.HashData(
            Encoding.UTF8.GetBytes(
                $"{instanceId:N}|{selectedInstanceItemId:N}"));

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await AcquireLockAsync(
                    connection,
                    transaction,
                    $"{SubmitOperation}:{context.AccountId:N}:{instanceId:N}",
                    token);

                var target = await ReadSubmissionTargetAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    instanceId,
                    token)
                    ?? throw new StudyExerciseInstanceNotFoundException();

                if (!await SelectionBelongsToInstanceAsync(
                        connection,
                        transaction,
                        instanceId,
                        selectedInstanceItemId,
                        token))
                {
                    throw new StudyExerciseInvalidSelectionException();
                }

                var existing = await ReadSubmissionAsync(
                    connection,
                    transaction,
                    instanceId,
                    token);

                if (existing is not null)
                {
                    if (CryptographicOperations.FixedTimeEquals(
                            answerDigest,
                            existing.AnswerDigest))
                    {
                        return existing.ToResult(reusedExisting: true);
                    }

                    if (string.Equals(
                            existing.IdempotencyKey,
                            normalizedIdempotencyKey,
                            StringComparison.Ordinal))
                    {
                        throw new StudyExerciseIdempotencyConflictException();
                    }

                    throw new StudyExerciseAlreadySubmittedException();
                }

                if (!target.IsOpen)
                {
                    throw new StudyExerciseSessionUnavailableException();
                }

                var submissionId = Guid.CreateVersion7();
                var submittedAt = await InsertSubmissionAsync(
                    connection,
                    transaction,
                    submissionId,
                    instanceId,
                    normalizedIdempotencyKey,
                    answerDigest,
                    token);

                await InsertAnswerValueAsync(
                    connection,
                    transaction,
                    submissionId,
                    selectedInstanceItemId,
                    token);

                await MarkInstanceRespondedAsync(
                    connection,
                    transaction,
                    instanceId,
                    token);

                return new AnswerSubmissionResult(
                    submissionId,
                    instanceId,
                    "CONFIRMED",
                    submittedAt,
                    selectedInstanceItemId,
                    false);
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

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "lock_key",
            NpgsqlDbType.Text,
            lockKey);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<OwnedStudySession?> ReadOwnedSessionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid studySessionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                session.study_session_id,
                session.recording_id,
                session.publication_id
            FROM learning.study_session AS session
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id =
                   session.learner_profile_id
            WHERE session.study_session_id = @study_session_id
              AND profile.account_id = @account_id
              AND session.status_code IN ('ACTIVE', 'PAUSED')
              AND session.ended_at IS NULL
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "study_session_id",
            NpgsqlDbType.Uuid,
            studySessionId);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new OwnedStudySession(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2));
    }

    private static async Task<Guid?> ReadExistingInstanceIdAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid studySessionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT instance_id
            FROM learning.exercise_instance
            WHERE study_session_id = @study_session_id
              AND instance_no = 1
            ORDER BY instance_id
            LIMIT 2;
            """;

        var ids = new List<Guid>(2);

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "study_session_id",
            NpgsqlDbType.Uuid,
            studySessionId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            ids.Add(reader.GetGuid(0));
        }

        return ids.Count switch
        {
            0 => null,
            1 => ids[0],
            _ => throw new InvalidOperationException(
                "La sesión contiene más de una instancia número 1.")
        };
    }

    private static async Task<PublishedExerciseCandidate?>
        ResolvePublishedExerciseAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            OwnedStudySession session,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT revision.exercise_revision_id
            FROM editorial.publication AS publication
            INNER JOIN editorial.editorial_package AS package
                ON package.package_id = publication.package_id
               AND package.recording_id = publication.recording_id
               AND package.status_code = 'APPROVED'
               AND package.frozen_at IS NOT NULL
            INNER JOIN editorial.publication_component AS published
                ON published.publication_id =
                   publication.publication_id
               AND published.component_kind = 'EXERCISE'
            INNER JOIN editorial.package_component AS component
                ON component.package_component_id =
                   published.source_component_id
               AND component.package_id = publication.package_id
               AND component.component_kind = 'EXERCISE'
               AND component.exercise_revision_id IS NOT NULL
               AND published.component_checksum = component.checksum
            INNER JOIN learning.exercise_revision AS revision
                ON revision.exercise_revision_id =
                   component.exercise_revision_id
            INNER JOIN learning.exercise_definition AS definition
                ON definition.exercise_id = revision.exercise_id
               AND definition.recording_id = publication.recording_id
               AND definition.exercise_type = 'FILL_BLANK_OPTIONS'
               AND definition.line_id IS NOT NULL
            INNER JOIN content.lyric_line AS line
                ON line.line_id = definition.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            WHERE publication.publication_id = @publication_id
              AND publication.recording_id = @recording_id
              AND publication.status_code = 'ACTIVE'
              AND publication.active_from <= CURRENT_TIMESTAMP
              AND (
                  publication.active_to IS NULL
                  OR publication.active_to > CURRENT_TIMESTAMP
              )
              AND EXISTS (
                  SELECT 1
                  FROM editorial.publication_availability AS availability
                  WHERE availability.publication_id =
                        publication.publication_id
                    AND availability.audience_code = 'PUBLIC'
                    AND availability.status_code = 'ACTIVE'
                    AND availability.valid_from <= CURRENT_TIMESTAMP
                    AND (
                        availability.valid_to IS NULL
                        OR availability.valid_to > CURRENT_TIMESTAMP
                    )
              )
              AND EXISTS (
                  SELECT 1
                  FROM editorial.package_component AS lyrics_component
                  WHERE lyrics_component.package_id =
                        publication.package_id
                    AND lyrics_component.component_kind = 'LYRICS'
                    AND lyrics_component.lyrics_revision_id =
                        section.lyrics_revision_id
              )
            ORDER BY
                section.display_order,
                line.line_no,
                definition.exercise_id,
                revision.revision_no
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "publication_id",
            NpgsqlDbType.Uuid,
            session.PublicationId);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            session.RecordingId);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        return value is Guid exerciseRevisionId
            ? new PublishedExerciseCandidate(exerciseRevisionId)
            : null;
    }

    private static async Task<IReadOnlyList<SourceOption>>
        ReadSourceOptionsAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid exerciseRevisionId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                item.exercise_item_id,
                item.prompt_fragment,
                item.metadata ->> 'role',
                item.metadata ->> 'sourceTokenId'
            FROM learning.exercise_item AS item
            WHERE item.exercise_revision_id =
                  @exercise_revision_id
              AND item.item_type = 'OPTION'
            ORDER BY item.item_order, item.exercise_item_id;
            """;

        var options = new List<SourceOption>();

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "exercise_revision_id",
            NpgsqlDbType.Uuid,
            exerciseRevisionId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            options.Add(
                new SourceOption(
                    reader.GetGuid(0),
                    reader.IsDBNull(1) ? string.Empty : reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3)));
        }

        return options;
    }

    private static void ValidateSourceOptions(
        IReadOnlyList<SourceOption> options)
    {
        if (options.Count is < 3 or > 5)
        {
            throw new StudyExerciseNoEligibleExerciseException();
        }

        var correct = options
            .Where(option =>
                string.Equals(
                    option.Role,
                    "CORRECT",
                    StringComparison.Ordinal))
            .ToArray();

        if (correct.Length != 1
            || !Guid.TryParse(correct[0].SourceTokenId, out _))
        {
            throw new StudyExerciseNoEligibleExerciseException();
        }

        var normalized = new HashSet<string>(
            StringComparer.Ordinal);

        foreach (var option in options)
        {
            if (string.IsNullOrWhiteSpace(option.Value)
                || !normalized.Add(NormalizeOption(option.Value)))
            {
                throw new StudyExerciseNoEligibleExerciseException();
            }
        }
    }

    private static async Task InsertInstanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid instanceId,
        Guid studySessionId,
        Guid exerciseRevisionId,
        string seed,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO learning.exercise_instance (
                instance_id,
                study_session_id,
                exercise_revision_id,
                instance_no,
                state_code,
                seed,
                delivered_at,
                expires_at,
                version
            )
            VALUES (
                @instance_id,
                @study_session_id,
                @exercise_revision_id,
                1,
                'DELIVERED',
                @seed,
                CURRENT_TIMESTAMP,
                NULL,
                1
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);
        command.Parameters.AddWithValue(
            "study_session_id",
            NpgsqlDbType.Uuid,
            studySessionId);
        command.Parameters.AddWithValue(
            "exercise_revision_id",
            NpgsqlDbType.Uuid,
            exerciseRevisionId);
        command.Parameters.AddWithValue(
            "seed",
            NpgsqlDbType.Text,
            seed);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se pudo congelar la instancia de ejercicio.");
        }
    }

    private static async Task InsertInstanceItemAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid instanceId,
        SourceOption option,
        int displayOrder,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO learning.exercise_instance_item (
                instance_id,
                source_item_id,
                display_order,
                presented_value
            )
            VALUES (
                @instance_id,
                @source_item_id,
                @display_order,
                to_jsonb(CAST(@presented_value AS text))
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);
        command.Parameters.AddWithValue(
            "source_item_id",
            NpgsqlDbType.Uuid,
            option.SourceItemId);
        command.Parameters.AddWithValue(
            "display_order",
            NpgsqlDbType.Integer,
            displayOrder);
        command.Parameters.AddWithValue(
            "presented_value",
            NpgsqlDbType.Text,
            option.Value);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se pudo congelar una opción visible.");
        }
    }

    private static async Task<FrozenExerciseView?> ReadViewCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid instanceId,
        CancellationToken cancellationToken)
    {
        var header = await ReadViewHeaderAsync(
            connection,
            transaction,
            accountId,
            instanceId,
            cancellationToken);

        if (header is null)
        {
            return null;
        }

        var options = await ReadFrozenOptionsAsync(
            connection,
            transaction,
            instanceId,
            cancellationToken);

        if (options.Count is < 3 or > 5)
        {
            throw new InvalidOperationException(
                "La instancia congelada no conserva un conjunto válido de opciones.");
        }

        var submission = await ReadFrozenSubmissionAsync(
            connection,
            transaction,
            instanceId,
            cancellationToken);

        return new FrozenExerciseView(
            header.InstanceId,
            header.StudySessionId,
            header.StateCode,
            header.InstanceNo,
            header.DeliveredAt,
            header.Version,
            header.ExerciseRevisionNo,
            header.Prompt,
            header.LineNo,
            MaskJapaneseLine(
                header.JapaneseText,
                header.CorrectSurface,
                header.StartOffset,
                header.EndOffset),
            options,
            submission);
    }

    private static async Task<ViewHeader?> ReadViewHeaderAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid instanceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                instance.instance_id,
                instance.study_session_id,
                instance.state_code,
                instance.instance_no,
                instance.delivered_at,
                instance.version,
                revision.revision_no,
                revision.prompt,
                line.line_no,
                line.japanese_text,
                token.surface,
                token.start_offset,
                token.end_offset
            FROM learning.exercise_instance AS instance
            INNER JOIN learning.study_session AS session
                ON session.study_session_id =
                   instance.study_session_id
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id =
                   session.learner_profile_id
            INNER JOIN learning.exercise_revision AS revision
                ON revision.exercise_revision_id =
                   instance.exercise_revision_id
            INNER JOIN learning.exercise_definition AS definition
                ON definition.exercise_id = revision.exercise_id
               AND definition.exercise_type = 'FILL_BLANK_OPTIONS'
               AND definition.line_id IS NOT NULL
            INNER JOIN content.lyric_line AS line
                ON line.line_id = definition.line_id
            INNER JOIN LATERAL (
                SELECT item.metadata ->> 'sourceTokenId' AS token_id
                FROM learning.exercise_item AS item
                WHERE item.exercise_revision_id =
                      revision.exercise_revision_id
                  AND item.item_type = 'OPTION'
                  AND item.metadata ->> 'role' = 'CORRECT'
                ORDER BY item.item_order
                LIMIT 1
            ) AS correct ON TRUE
            INNER JOIN content.lyric_token AS token
                ON token.token_id::text = correct.token_id
               AND token.line_id = line.line_id
            WHERE instance.instance_id = @instance_id
              AND profile.account_id = @account_id
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new ViewHeader(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            reader.GetInt32(3),
            ToUtcOffset(reader.GetDateTime(4)),
            reader.GetInt64(5),
            reader.GetInt32(6),
            reader.GetString(7),
            reader.GetInt32(8),
            reader.GetString(9),
            reader.GetString(10),
            reader.GetInt32(11),
            reader.GetInt32(12));
    }

    private static async Task<IReadOnlyList<FrozenExerciseOption>>
        ReadFrozenOptionsAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid instanceId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                instance_item_id,
                display_order,
                presented_value #>> '{}'
            FROM learning.exercise_instance_item
            WHERE instance_id = @instance_id
            ORDER BY display_order, instance_item_id;
            """;

        var options = new List<FrozenExerciseOption>();

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            options.Add(
                new FrozenExerciseOption(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2)));
        }

        return options;
    }

    private static async Task<FrozenExerciseSubmission?>
        ReadFrozenSubmissionAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid instanceId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                submission.submission_id,
                submission.status_code,
                submission.submitted_at,
                answer.selected_item_id
            FROM learning.answer_submission AS submission
            INNER JOIN learning.answer_value AS answer
                ON answer.submission_id = submission.submission_id
               AND answer.value_type = 'SELECTED_ITEM'
               AND answer.selected_item_id IS NOT NULL
            WHERE submission.instance_id = @instance_id
              AND submission.submission_no = 1
            ORDER BY submission.submitted_at, submission.submission_id
            LIMIT 2;
            """;

        var rows = new List<FrozenExerciseSubmission>(2);

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(
                new FrozenExerciseSubmission(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    ToUtcOffset(reader.GetDateTime(2)),
                    reader.GetGuid(3)));
        }

        return rows.Count switch
        {
            0 => null,
            1 => rows[0],
            _ => throw new InvalidOperationException(
                "La instancia contiene más de una respuesta lógica número 1.")
        };
    }

    private static async Task<SubmissionTarget?>
        ReadSubmissionTargetAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid accountId,
            Guid instanceId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                instance.state_code,
                session.status_code,
                session.ended_at IS NULL
            FROM learning.exercise_instance AS instance
            INNER JOIN learning.study_session AS session
                ON session.study_session_id =
                   instance.study_session_id
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id =
                   session.learner_profile_id
            WHERE instance.instance_id = @instance_id
              AND profile.account_id = @account_id
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new SubmissionTarget(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetBoolean(2));
    }

    private static async Task<bool> SelectionBelongsToInstanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid instanceId,
        Guid selectedInstanceItemId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM learning.exercise_instance_item
                WHERE instance_item_id =
                      @selected_instance_item_id
                  AND instance_id = @instance_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "selected_instance_item_id",
            NpgsqlDbType.Uuid,
            selectedInstanceItemId);
        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static async Task<StoredSubmission?> ReadSubmissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid instanceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                submission.submission_id,
                submission.idempotency_key,
                submission.status_code,
                submission.submitted_at,
                submission.answer_digest,
                answer.selected_item_id
            FROM learning.answer_submission AS submission
            INNER JOIN learning.answer_value AS answer
                ON answer.submission_id = submission.submission_id
               AND answer.value_type = 'SELECTED_ITEM'
               AND answer.selected_item_id IS NOT NULL
            WHERE submission.instance_id = @instance_id
              AND submission.submission_no = 1
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new StoredSubmission(
            reader.GetGuid(0),
            instanceId,
            reader.GetString(1),
            reader.GetString(2),
            ToUtcOffset(reader.GetDateTime(3)),
            (byte[])reader.GetValue(4),
            reader.GetGuid(5));
    }

    private static async Task<DateTimeOffset> InsertSubmissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid submissionId,
        Guid instanceId,
        string idempotencyKey,
        byte[] answerDigest,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO learning.answer_submission (
                submission_id,
                instance_id,
                submission_no,
                idempotency_key,
                submitted_at,
                status_code,
                answer_digest
            )
            VALUES (
                @submission_id,
                @instance_id,
                1,
                @idempotency_key,
                CURRENT_TIMESTAMP,
                'CONFIRMED',
                @answer_digest
            )
            RETURNING submitted_at;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "submission_id",
            NpgsqlDbType.Uuid,
            submissionId);
        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);
        command.Parameters.AddWithValue(
            "idempotency_key",
            NpgsqlDbType.Text,
            idempotencyKey);
        command.Parameters.AddWithValue(
            "answer_digest",
            NpgsqlDbType.Bytea,
            answerDigest);

        var value = await command.ExecuteScalarAsync(cancellationToken)
            ?? throw new InvalidOperationException(
                "La confirmación no devolvió fecha de persistencia.");

        return ToUtcOffset((DateTime)value);
    }

    private static async Task InsertAnswerValueAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid submissionId,
        Guid selectedInstanceItemId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO learning.answer_value (
                submission_id,
                instance_item_id,
                value_type,
                value_text,
                value_number,
                selected_item_id
            )
            VALUES (
                @submission_id,
                @selected_instance_item_id,
                'SELECTED_ITEM',
                NULL,
                NULL,
                @selected_instance_item_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "submission_id",
            NpgsqlDbType.Uuid,
            submissionId);
        command.Parameters.AddWithValue(
            "selected_instance_item_id",
            NpgsqlDbType.Uuid,
            selectedInstanceItemId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se pudo conservar el valor elegido.");
        }
    }

    private static async Task MarkInstanceRespondedAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid instanceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE learning.exercise_instance
            SET
                state_code = 'RESPONDED',
                version = version + 1
            WHERE instance_id = @instance_id
              AND state_code = 'DELIVERED';
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "instance_id",
            NpgsqlDbType.Uuid,
            instanceId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "La instancia cambió antes de confirmar la respuesta.");
        }
    }

    private static string NormalizeIdempotencyKey(string value)
    {
        var normalized = value?.Trim();

        if (string.IsNullOrWhiteSpace(normalized)
            || normalized.Length < MinimumIdempotencyKeyLength
            || normalized.Length > MaximumIdempotencyKeyLength)
        {
            throw new ArgumentException(
                $"Idempotency-Key debe tener entre {MinimumIdempotencyKeyLength} y {MaximumIdempotencyKeyLength} caracteres.",
                nameof(value));
        }

        return normalized;
    }

    private static string BuildOrderKey(
        string seed,
        Guid sourceItemId) =>
        Convert.ToHexString(
            SHA256.HashData(
                Encoding.UTF8.GetBytes(
                    $"{seed}:{sourceItemId:N}")));

    private static string NormalizeOption(string value)
    {
        var normalized = value
            .Normalize(NormalizationForm.FormKC)
            .Trim();

        var builder = new StringBuilder(normalized.Length);
        var previousWhitespace = false;

        foreach (var character in normalized)
        {
            if (char.IsWhiteSpace(character))
            {
                if (!previousWhitespace)
                {
                    builder.Append(' ');
                }

                previousWhitespace = true;
                continue;
            }

            builder.Append(char.ToLowerInvariant(character));
            previousWhitespace = false;
        }

        return builder.ToString();
    }

    private static string MaskJapaneseLine(
        string japaneseText,
        string correctSurface,
        int startOffset,
        int endOffset)
    {
        if (startOffset >= 0
            && endOffset > startOffset
            && endOffset <= japaneseText.Length)
        {
            var candidate = japaneseText[startOffset..endOffset];
            if (string.Equals(
                    candidate,
                    correctSurface,
                    StringComparison.Ordinal))
            {
                return japaneseText[..startOffset]
                    + "＿＿"
                    + japaneseText[endOffset..];
            }
        }

        var fallback = japaneseText.IndexOf(
            correctSurface,
            StringComparison.Ordinal);

        if (fallback < 0)
        {
            throw new InvalidOperationException(
                "El token congelado ya no puede localizarse en su línea publicada.");
        }

        return japaneseText[..fallback]
            + "＿＿"
            + japaneseText[(fallback + correctSurface.Length)..];
    }

    private static DateTimeOffset ToUtcOffset(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private sealed record OwnedStudySession(
        Guid StudySessionId,
        Guid RecordingId,
        Guid PublicationId);

    private sealed record PublishedExerciseCandidate(
        Guid ExerciseRevisionId);

    private sealed record SourceOption(
        Guid SourceItemId,
        string Value,
        string? Role,
        string? SourceTokenId);

    private sealed record ViewHeader(
        Guid InstanceId,
        Guid StudySessionId,
        string StateCode,
        int InstanceNo,
        DateTimeOffset DeliveredAt,
        long Version,
        int ExerciseRevisionNo,
        string Prompt,
        int LineNo,
        string JapaneseText,
        string CorrectSurface,
        int StartOffset,
        int EndOffset);

    private sealed record SubmissionTarget(
        string StateCode,
        string SessionStatusCode,
        bool SessionNotEnded)
    {
        public bool IsOpen =>
            SessionNotEnded
            && string.Equals(StateCode, "DELIVERED", StringComparison.Ordinal)
            && (
                string.Equals(SessionStatusCode, "ACTIVE", StringComparison.Ordinal)
                || string.Equals(SessionStatusCode, "PAUSED", StringComparison.Ordinal)
            );
    }

    private sealed record StoredSubmission(
        Guid SubmissionId,
        Guid InstanceId,
        string IdempotencyKey,
        string StatusCode,
        DateTimeOffset SubmittedAt,
        byte[] AnswerDigest,
        Guid SelectedInstanceItemId)
    {
        public AnswerSubmissionResult ToResult(
            bool reusedExisting) =>
            new(
                SubmissionId,
                InstanceId,
                StatusCode,
                SubmittedAt,
                SelectedInstanceItemId,
                reusedExisting);
    }
}
