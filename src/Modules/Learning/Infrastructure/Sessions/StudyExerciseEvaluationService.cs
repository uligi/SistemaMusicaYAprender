using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Learning.Infrastructure.Sessions;

public sealed record StudyEvaluationFeedback(
    string FeedbackCode,
    string LanguageTag,
    string Message,
    int DisplayOrder);

public sealed record StudyEvaluationView(
    Guid EvaluationId,
    Guid SubmissionId,
    string EvaluatorVersion,
    decimal Score,
    bool Correct,
    DateTimeOffset EvaluatedAt,
    string ResultDigestSha256,
    bool ReusedExisting,
    IReadOnlyList<StudyEvaluationFeedback> Feedback);

public sealed class StudyExerciseEvaluationPendingException : Exception
{
    public StudyExerciseEvaluationPendingException()
        : base("La respuesta confirmada todavía no tiene una evaluación persistida.")
    {
    }
}

public sealed class StudyExerciseEvaluationInstanceNotFoundException : Exception
{
    public StudyExerciseEvaluationInstanceNotFoundException()
        : base("La instancia o su respuesta confirmada no existe para esta cuenta.")
    {
    }
}

public sealed class StudyExerciseEvaluationRuleUnavailableException : Exception
{
    public StudyExerciseEvaluationRuleUnavailableException()
        : base("La regla congelada no permite producir una evaluación confirmada y requiere revisión.")
    {
    }
}

public sealed class StudyExerciseEvaluationDriftException : Exception
{
    public StudyExerciseEvaluationDriftException()
        : base("La evaluación persistida no coincide con la regla congelada y requiere revisión trazable.")
    {
    }
}

public sealed class StudyExerciseEvaluationService(
    IRlsTransactionExecutor transactionExecutor)
{
    public const string EvaluatorVersion = "FILL_BLANK_OPTIONS.SINGLE_CHOICE/v1";
    private const string EvaluationOperation = "LEARNING.EVALUATION_RESULT.ENSURE";
    private const string FeedbackLanguage = "es-CR";
    private const string NextActionMessage =
        "Puedes volver a la canción o continuar con la práctica cuando haya otra actividad disponible.";

    public Task<StudyEvaluationView> ReadAsync(
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
                var view = await ReadExistingViewAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    instanceId,
                    reusedExisting: true,
                    token);

                return view ?? throw new StudyExerciseEvaluationPendingException();
            },
            cancellationToken);
    }

    public Task<StudyEvaluationView> EnsureAsync(
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
                    $"{EvaluationOperation}:{context.AccountId:N}:{instanceId:N}",
                    token);

                var target = await ReadEvaluationTargetAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    instanceId,
                    token)
                    ?? throw new StudyExerciseEvaluationInstanceNotFoundException();

                var rule = ParseRule(target.SolutionSpecJson);
                var revisionOptions = await ReadRevisionOptionsAsync(
                    connection,
                    transaction,
                    target.ExerciseRevisionId,
                    token);

                var accepted = ResolveAcceptedOptions(rule, revisionOptions);

                var selected = revisionOptions.FirstOrDefault(option =>
                    option.SourceItemId == target.SelectedSourceItemId);

                if (selected is null)
                {
                    throw new StudyExerciseEvaluationRuleUnavailableException();
                }

                var acceptedSourceItemIds = accepted
                    .Select(option => option.SourceItemId)
                    .ToHashSet();
                var correct = acceptedSourceItemIds.Contains(target.SelectedSourceItemId);
                var score = correct ? 1.000000m : 0.000000m;
                var digest = BuildResultDigest(
                    target,
                    accepted,
                    score,
                    correct);

                var existing = await ReadStoredEvaluationAsync(
                    connection,
                    transaction,
                    target.SubmissionId,
                    token);

                var reusedExisting = existing is not null;

                if (existing is null
                    && !await SessionAcceptsNewEducationalMutationAsync(
                        connection,
                        transaction,
                        context.AccountId,
                        instanceId,
                        token))
                {
                    throw new StudyExerciseSessionUnavailableException();
                }

                Guid evaluationId;

                if (existing is null)
                {
                    evaluationId = Guid.CreateVersion7();
                    await InsertEvaluationAsync(
                        connection,
                        transaction,
                        evaluationId,
                        target.SubmissionId,
                        score,
                        correct,
                        digest,
                        token);
                }
                else
                {
                    ValidateStoredEvaluation(existing, score, correct, digest);
                    evaluationId = existing.EvaluationId;
                }

                var expectedFeedback = BuildExpectedFeedback(
                    evaluationId,
                    target.SelectedInstanceItemId,
                    rule,
                    correct);

                var storedFeedback = await ReadStoredFeedbackAsync(
                    connection,
                    transaction,
                    evaluationId,
                    token);

                if (storedFeedback.Count == 0)
                {
                    foreach (var item in expectedFeedback)
                    {
                        await InsertFeedbackAsync(
                            connection,
                            transaction,
                            item,
                            token);
                    }
                }
                else
                {
                    ValidateStoredFeedback(storedFeedback, expectedFeedback);
                }

                return await ReadExistingViewAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    instanceId,
                    reusedExisting,
                    token)
                    ?? throw new InvalidOperationException(
                        "La evaluación confirmada no pudo recuperarse después de persistirla.");
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

    private static async Task<EvaluationTarget?> ReadEvaluationTargetAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid instanceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                submission.submission_id,
                instance.exercise_revision_id,
                answer.selected_item_id,
                selected.source_item_id,
                revision.solution_spec::text
            FROM learning.exercise_instance AS instance
            INNER JOIN learning.study_session AS session
                ON session.study_session_id = instance.study_session_id
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id = session.learner_profile_id
            INNER JOIN learning.answer_submission AS submission
                ON submission.instance_id = instance.instance_id
               AND submission.submission_no = 1
               AND submission.status_code = 'CONFIRMED'
            INNER JOIN learning.answer_value AS answer
                ON answer.submission_id = submission.submission_id
               AND answer.value_type = 'SELECTED_ITEM'
               AND answer.selected_item_id IS NOT NULL
            INNER JOIN learning.exercise_instance_item AS selected
                ON selected.instance_item_id = answer.selected_item_id
               AND selected.instance_id = instance.instance_id
            INNER JOIN learning.exercise_revision AS revision
                ON revision.exercise_revision_id = instance.exercise_revision_id
            INNER JOIN learning.exercise_definition AS definition
                ON definition.exercise_id = revision.exercise_id
               AND definition.exercise_type = 'FILL_BLANK_OPTIONS'
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

        return new EvaluationTarget(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2),
            reader.GetGuid(3),
            reader.GetString(4));
    }

    private static async Task<bool> SessionAcceptsNewEducationalMutationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid instanceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                session.status_code,
                session.ended_at IS NULL
            FROM learning.exercise_instance AS instance
            INNER JOIN learning.study_session AS session
                ON session.study_session_id = instance.study_session_id
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id = session.learner_profile_id
            WHERE instance.instance_id = @instance_id
              AND profile.account_id = @account_id
            LIMIT 1
            FOR UPDATE OF session;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("instance_id", NpgsqlDbType.Uuid, instanceId);
        command.Parameters.AddWithValue("account_id", NpgsqlDbType.Uuid, accountId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return false;
        }

        return string.Equals(reader.GetString(0), "ACTIVE", StringComparison.Ordinal)
            && reader.GetBoolean(1);
    }

    private static EvaluationRule ParseRule(string solutionSpecJson)
    {
        try
        {
            using var document = JsonDocument.Parse(solutionSpecJson);
            var root = document.RootElement;

            if (!root.TryGetProperty("schemaVersion", out var schemaVersionElement)
                || schemaVersionElement.ValueKind != JsonValueKind.Number
                || !schemaVersionElement.TryGetInt32(out var schemaVersion)
                || schemaVersion != 1)
            {
                throw new StudyExerciseEvaluationRuleUnavailableException();
            }

            if (!root.TryGetProperty("answerModel", out var answerModelElement)
                || !string.Equals(
                    answerModelElement.GetString(),
                    "SINGLE_CHOICE",
                    StringComparison.Ordinal))
            {
                throw new StudyExerciseEvaluationRuleUnavailableException();
            }

            if (!root.TryGetProperty("acceptedItemOrders", out var acceptedElement)
                || acceptedElement.ValueKind != JsonValueKind.Array)
            {
                throw new StudyExerciseEvaluationRuleUnavailableException();
            }

            var acceptedItemOrders = acceptedElement
                .EnumerateArray()
                .Select(item =>
                    item.ValueKind == JsonValueKind.Number
                    && item.TryGetInt32(out var order)
                        ? order
                        : 0)
                .Where(order => order > 0)
                .Distinct()
                .OrderBy(order => order)
                .ToArray();

            if (acceptedItemOrders.Length == 0)
            {
                throw new StudyExerciseEvaluationRuleUnavailableException();
            }

            var explanation = RequiredRuleText(root, "explanation");

            if (!root.TryGetProperty("feedback", out var feedbackElement)
                || feedbackElement.ValueKind != JsonValueKind.Object)
            {
                throw new StudyExerciseEvaluationRuleUnavailableException();
            }

            var feedbackCorrect = RequiredRuleText(feedbackElement, "correct");
            var feedbackIncorrect = RequiredRuleText(feedbackElement, "incorrect");

            return new EvaluationRule(
                acceptedItemOrders,
                explanation,
                feedbackCorrect,
                feedbackIncorrect);
        }
        catch (JsonException)
        {
            throw new StudyExerciseEvaluationRuleUnavailableException();
        }
        catch (InvalidOperationException)
        {
            throw new StudyExerciseEvaluationRuleUnavailableException();
        }
    }

    private static string RequiredRuleText(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var element)
            || element.ValueKind != JsonValueKind.String
            || string.IsNullOrWhiteSpace(element.GetString()))
        {
            throw new StudyExerciseEvaluationRuleUnavailableException();
        }

        return element.GetString()!.Trim();
    }

    private static async Task<IReadOnlyList<RevisionOption>> ReadRevisionOptionsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid exerciseRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                exercise_item_id,
                item_order
            FROM learning.exercise_item
            WHERE exercise_revision_id = @exercise_revision_id
              AND item_type = 'OPTION'
            ORDER BY item_order, exercise_item_id;
            """;

        var options = new List<RevisionOption>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "exercise_revision_id",
            NpgsqlDbType.Uuid,
            exerciseRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            options.Add(new RevisionOption(reader.GetGuid(0), reader.GetInt32(1)));
        }

        return options;
    }

    private static List<RevisionOption> ResolveAcceptedOptions(
        EvaluationRule rule,
        IReadOnlyList<RevisionOption> revisionOptions)
    {
        var accepted = new List<RevisionOption>(rule.AcceptedItemOrders.Count);

        foreach (var acceptedOrder in rule.AcceptedItemOrders)
        {
            var matches = revisionOptions
                .Where(option => option.ItemOrder == acceptedOrder)
                .ToArray();

            if (matches.Length != 1)
            {
                throw new StudyExerciseEvaluationRuleUnavailableException();
            }

            accepted.Add(matches[0]);
        }

        return accepted;
    }

    private static byte[] BuildResultDigest(
        EvaluationTarget target,
        IReadOnlyList<RevisionOption> accepted,
        decimal score,
        bool correct)
    {
        var acceptedMaterial = string.Join(
            ",",
            accepted
                .OrderBy(option => option.ItemOrder)
                .Select(option => $"{option.ItemOrder}:{option.SourceItemId:N}"));

        var material = string.Join(
            "|",
            EvaluatorVersion,
            target.SubmissionId.ToString("N"),
            target.ExerciseRevisionId.ToString("N"),
            acceptedMaterial,
            target.SelectedSourceItemId.ToString("N"),
            score.ToString("0.000000", CultureInfo.InvariantCulture),
            correct ? "1" : "0");

        return SHA256.HashData(Encoding.UTF8.GetBytes(material));
    }

    private static async Task<StoredEvaluation?> ReadStoredEvaluationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid submissionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                evaluation_id,
                evaluator_version,
                score,
                correct,
                evaluated_at,
                result_digest
            FROM learning.evaluation_result
            WHERE submission_id = @submission_id
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("submission_id", NpgsqlDbType.Uuid, submissionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new StoredEvaluation(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetDecimal(2),
            reader.GetBoolean(3),
            ToUtcOffset(reader.GetDateTime(4)),
            (byte[])reader[5]);
    }

    private static void ValidateStoredEvaluation(
        StoredEvaluation existing,
        decimal score,
        bool correct,
        byte[] digest)
    {
        if (!string.Equals(existing.EvaluatorVersion, EvaluatorVersion, StringComparison.Ordinal)
            || existing.Score != score
            || existing.Correct != correct
            || !CryptographicOperations.FixedTimeEquals(existing.ResultDigest, digest))
        {
            throw new StudyExerciseEvaluationDriftException();
        }
    }

    private static async Task InsertEvaluationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid evaluationId,
        Guid submissionId,
        decimal score,
        bool correct,
        byte[] digest,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO learning.evaluation_result (
                evaluation_id,
                submission_id,
                evaluator_version,
                score,
                correct,
                evaluated_at,
                result_digest
            )
            VALUES (
                @evaluation_id,
                @submission_id,
                @evaluator_version,
                @score,
                @correct,
                CURRENT_TIMESTAMP,
                @result_digest
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("evaluation_id", NpgsqlDbType.Uuid, evaluationId);
        command.Parameters.AddWithValue("submission_id", NpgsqlDbType.Uuid, submissionId);
        command.Parameters.AddWithValue("evaluator_version", NpgsqlDbType.Text, EvaluatorVersion);
        command.Parameters.AddWithValue("score", NpgsqlDbType.Numeric, score);
        command.Parameters.AddWithValue("correct", NpgsqlDbType.Boolean, correct);
        command.Parameters.AddWithValue("result_digest", NpgsqlDbType.Bytea, digest);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException("No se pudo persistir la evaluación reproducible.");
        }
    }

    private static IReadOnlyList<ExpectedFeedback> BuildExpectedFeedback(
        Guid evaluationId,
        Guid selectedInstanceItemId,
        EvaluationRule rule,
        bool correct) =>
    [
        new ExpectedFeedback(
            Guid.CreateVersion7(),
            evaluationId,
            selectedInstanceItemId,
            correct ? "RESULT.CORRECT" : "RESULT.INCORRECT",
            FeedbackLanguage,
            correct ? rule.FeedbackCorrect : rule.FeedbackIncorrect,
            0),
        new ExpectedFeedback(
            Guid.CreateVersion7(),
            evaluationId,
            selectedInstanceItemId,
            "EXPLANATION.RULE",
            FeedbackLanguage,
            rule.Explanation,
            1),
        new ExpectedFeedback(
            Guid.CreateVersion7(),
            evaluationId,
            null,
            "NEXT_ACTION.CONTINUE",
            FeedbackLanguage,
            NextActionMessage,
            2)
    ];

    private static async Task<IReadOnlyList<StoredFeedback>> ReadStoredFeedbackAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid evaluationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                feedback_id,
                item_id,
                feedback_code,
                language_tag,
                message,
                display_order
            FROM learning.feedback_item
            WHERE evaluation_id = @evaluation_id
            ORDER BY display_order, feedback_id;
            """;

        var feedback = new List<StoredFeedback>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("evaluation_id", NpgsqlDbType.Uuid, evaluationId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            feedback.Add(
                new StoredFeedback(
                    reader.GetGuid(0),
                    reader.IsDBNull(1) ? null : reader.GetGuid(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetInt32(5)));
        }

        return feedback;
    }

    private static async Task InsertFeedbackAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ExpectedFeedback feedback,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO learning.feedback_item (
                feedback_id,
                evaluation_id,
                item_id,
                feedback_code,
                language_tag,
                message,
                display_order
            )
            VALUES (
                @feedback_id,
                @evaluation_id,
                @item_id,
                @feedback_code,
                @language_tag,
                @message,
                @display_order
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("feedback_id", NpgsqlDbType.Uuid, feedback.FeedbackId);
        command.Parameters.AddWithValue("evaluation_id", NpgsqlDbType.Uuid, feedback.EvaluationId);
        command.Parameters.Add(
            new NpgsqlParameter("item_id", NpgsqlDbType.Uuid)
            {
                Value = feedback.ItemId.HasValue ? feedback.ItemId.Value : DBNull.Value
            });
        command.Parameters.AddWithValue("feedback_code", NpgsqlDbType.Text, feedback.FeedbackCode);
        command.Parameters.AddWithValue("language_tag", NpgsqlDbType.Text, feedback.LanguageTag);
        command.Parameters.AddWithValue("message", NpgsqlDbType.Text, feedback.Message);
        command.Parameters.AddWithValue("display_order", NpgsqlDbType.Integer, feedback.DisplayOrder);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException("No se pudo persistir la retroalimentación accesible.");
        }
    }

    private static void ValidateStoredFeedback(
        IReadOnlyList<StoredFeedback> stored,
        IReadOnlyList<ExpectedFeedback> expected)
    {
        if (stored.Count != expected.Count)
        {
            throw new StudyExerciseEvaluationDriftException();
        }

        for (var index = 0; index < expected.Count; index++)
        {
            var actual = stored[index];
            var candidate = expected[index];

            if (actual.ItemId != candidate.ItemId
                || actual.DisplayOrder != candidate.DisplayOrder
                || !string.Equals(actual.FeedbackCode, candidate.FeedbackCode, StringComparison.Ordinal)
                || !string.Equals(actual.LanguageTag, candidate.LanguageTag, StringComparison.Ordinal)
                || !string.Equals(actual.Message, candidate.Message, StringComparison.Ordinal))
            {
                throw new StudyExerciseEvaluationDriftException();
            }
        }
    }

    private static async Task<StudyEvaluationView?> ReadExistingViewAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid instanceId,
        bool reusedExisting,
        CancellationToken cancellationToken)
    {
        const string headerSql = """
            SELECT
                evaluation.evaluation_id,
                evaluation.submission_id,
                evaluation.evaluator_version,
                evaluation.score,
                evaluation.correct,
                evaluation.evaluated_at,
                evaluation.result_digest
            FROM learning.evaluation_result AS evaluation
            INNER JOIN learning.answer_submission AS submission
                ON submission.submission_id = evaluation.submission_id
               AND submission.submission_no = 1
            INNER JOIN learning.exercise_instance AS instance
                ON instance.instance_id = submission.instance_id
            INNER JOIN learning.study_session AS session
                ON session.study_session_id = instance.study_session_id
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id = session.learner_profile_id
            WHERE instance.instance_id = @instance_id
              AND profile.account_id = @account_id
            LIMIT 1;
            """;

        Guid evaluationId;
        Guid submissionId;
        string evaluatorVersion;
        decimal score;
        bool correct;
        DateTimeOffset evaluatedAt;
        byte[] digest;

        await using (var command = new NpgsqlCommand(headerSql, connection, transaction))
        {
            command.Parameters.AddWithValue("instance_id", NpgsqlDbType.Uuid, instanceId);
            command.Parameters.AddWithValue("account_id", NpgsqlDbType.Uuid, accountId);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return null;
            }

            evaluationId = reader.GetGuid(0);
            submissionId = reader.GetGuid(1);
            evaluatorVersion = reader.GetString(2);
            score = reader.GetDecimal(3);
            correct = reader.GetBoolean(4);
            evaluatedAt = ToUtcOffset(reader.GetDateTime(5));
            digest = (byte[])reader[6];
        }

        var feedback = await ReadStoredFeedbackAsync(
            connection,
            transaction,
            evaluationId,
            cancellationToken);

        if (feedback.Count != 3)
        {
            throw new StudyExerciseEvaluationDriftException();
        }

        return new StudyEvaluationView(
            evaluationId,
            submissionId,
            evaluatorVersion,
            score,
            correct,
            evaluatedAt,
            Convert.ToHexString(digest).ToLowerInvariant(),
            reusedExisting,
            feedback
                .OrderBy(item => item.DisplayOrder)
                .Select(item =>
                    new StudyEvaluationFeedback(
                        item.FeedbackCode,
                        item.LanguageTag,
                        item.Message,
                        item.DisplayOrder))
                .ToArray());
    }

    private static DateTimeOffset ToUtcOffset(DateTime value)
    {
        var utc = value.Kind == DateTimeKind.Utc
            ? value
            : DateTime.SpecifyKind(value, DateTimeKind.Utc);
        return new DateTimeOffset(utc);
    }

    private sealed record EvaluationTarget(
        Guid SubmissionId,
        Guid ExerciseRevisionId,
        Guid SelectedInstanceItemId,
        Guid SelectedSourceItemId,
        string SolutionSpecJson);

    private sealed record EvaluationRule(
        IReadOnlyList<int> AcceptedItemOrders,
        string Explanation,
        string FeedbackCorrect,
        string FeedbackIncorrect);

    private sealed record RevisionOption(Guid SourceItemId, int ItemOrder);

    private sealed record StoredEvaluation(
        Guid EvaluationId,
        string EvaluatorVersion,
        decimal Score,
        bool Correct,
        DateTimeOffset EvaluatedAt,
        byte[] ResultDigest);

    private sealed record ExpectedFeedback(
        Guid FeedbackId,
        Guid EvaluationId,
        Guid? ItemId,
        string FeedbackCode,
        string LanguageTag,
        string Message,
        int DisplayOrder);

    private sealed record StoredFeedback(
        Guid FeedbackId,
        Guid? ItemId,
        string FeedbackCode,
        string LanguageTag,
        string Message,
        int DisplayOrder);
}
