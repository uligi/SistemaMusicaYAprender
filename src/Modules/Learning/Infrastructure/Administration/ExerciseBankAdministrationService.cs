using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Learning.Infrastructure.Administration;

public interface IExerciseBankAdministrationTransactionExecutor
{
    Task<TResult> ExecuteAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default);
}

public sealed class ExerciseBankAdministrationService(
    IExerciseBankAdministrationTransactionExecutor transactions)
{
    public async Task<ExerciseBankSnapshot> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException("El actor es obligatorio.", nameof(actorAccountId));
        }

        if (recordingId == Guid.Empty)
        {
            throw new ArgumentException("La grabación es obligatoria.", nameof(recordingId));
        }

        return await transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                if (!await RecordingExistsAsync(connection, transaction, recordingId, token))
                {
                    throw new ExerciseBankAdministrationException(
                        "learning.exercise-bank.recording.not-found",
                        "La canción editorial solicitada no existe.");
                }

                var definitions = await ReadDefinitionsAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                var exercises = new List<ExerciseBankEntry>(definitions.Count);

                foreach (var definition in definitions)
                {
                    var revisions = await ReadRevisionsAsync(
                        connection,
                        transaction,
                        definition,
                        token);

                    exercises.Add(
                        new ExerciseBankEntry(
                            definition.ExerciseId,
                            definition.ExerciseType,
                            definition.StatusCode,
                            definition.Version,
                            new ExerciseCompetencySnapshot(
                                definition.CompetencyCode,
                                definition.CompetencyDomainCode,
                                definition.CompetencyTitle),
                            new ExerciseSourceSnapshot(
                                recordingId,
                                definition.LineId,
                                definition.LineNo,
                                definition.JapaneseText,
                                definition.LyricsRevisionId,
                                definition.LyricsRevisionNo,
                                definition.LyricsRevisionChecksumSha256),
                            revisions));
                }

                return new ExerciseBankSnapshot(
                    recordingId,
                    exercises.Count,
                    exercises);
            },
            cancellationToken);
    }

    private static async Task<bool> RecordingExistsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.recording
                WHERE recording_id = @recording_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    private static async Task<List<DefinitionRow>> ReadDefinitionsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                definition.exercise_id,
                definition.exercise_type,
                definition.status_code,
                definition.version,
                competency.competency_code,
                competency.domain_code,
                competency.title,
                line.line_id,
                line.line_no,
                line.japanese_text,
                lyrics.lyrics_revision_id,
                lyrics.revision_no,
                encode(lyrics.checksum, 'hex')
            FROM learning.exercise_definition AS definition
            INNER JOIN learning.competency AS competency
                ON competency.competency_id = definition.competency_id
            LEFT JOIN content.lyric_line AS line
                ON line.line_id = definition.line_id
            LEFT JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            LEFT JOIN content.lyrics_revision AS lyrics
                ON lyrics.lyrics_revision_id = section.lyrics_revision_id
               AND lyrics.recording_id = definition.recording_id
            WHERE definition.recording_id = @recording_id
            ORDER BY
                definition.exercise_type,
                competency.competency_code,
                definition.exercise_id;
            """;

        var rows = new List<DefinitionRow>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(
                new DefinitionRow(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetInt64(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetGuid(7),
                    reader.IsDBNull(8) ? null : reader.GetInt32(8),
                    reader.IsDBNull(9) ? null : reader.GetString(9),
                    reader.IsDBNull(10) ? null : reader.GetGuid(10),
                    reader.IsDBNull(11) ? null : reader.GetInt32(11),
                    reader.IsDBNull(12) ? null : reader.GetString(12)));
        }

        return rows;
    }

    private static async Task<IReadOnlyList<ExerciseRevisionSnapshot>> ReadRevisionsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        DefinitionRow definition,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                exercise_revision_id,
                revision_no,
                prompt,
                solution_spec::text,
                status_code,
                encode(checksum, 'hex'),
                version
            FROM learning.exercise_revision
            WHERE exercise_id = @exercise_id
            ORDER BY revision_no DESC, exercise_revision_id;
            """;

        var revisions = new List<ExerciseRevisionSnapshot>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "exercise_id",
            NpgsqlDbType.Uuid,
            definition.ExerciseId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var revisionRows = new List<RevisionRow>();

        while (await reader.ReadAsync(cancellationToken))
        {
            revisionRows.Add(
                new RevisionRow(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetInt64(6)));
        }

        await reader.CloseAsync();

        foreach (var revision in revisionRows)
        {
            var model = ParseSolutionSpec(revision.SolutionSpecJson);
            var items = await ReadItemsAsync(
                connection,
                transaction,
                revision.ExerciseRevisionId,
                model.AcceptedItemOrders,
                cancellationToken);
            var provenance = await ReadProvenanceAsync(
                connection,
                transaction,
                revision.ExerciseRevisionId,
                cancellationToken);

            var acceptedOrders = model.AcceptedItemOrders.ToHashSet();
            var solutionValues = items
                .Where(item => acceptedOrders.Contains(item.ItemOrder))
                .Select(item => item.Value ?? item.Label ?? $"Opción {item.ItemOrder}")
                .ToArray();

            var hasContext =
                definition.LineId.HasValue &&
                definition.LyricsRevisionId.HasValue &&
                definition.LyricsRevisionNo.HasValue;

            var optionCount = items.Count(item =>
                string.Equals(item.ItemType, "OPTION", StringComparison.OrdinalIgnoreCase));

            var matchedSolutions = model.AcceptedItemOrders.Count(order =>
                items.Any(item => item.ItemOrder == order));

            var completeness = new ExerciseRevisionCompleteness(
                hasContext,
                optionCount >= 2,
                model.AcceptedItemOrders.Count > 0 &&
                    matchedSolutions == model.AcceptedItemOrders.Count,
                !string.IsNullOrWhiteSpace(model.Explanation),
                !string.IsNullOrWhiteSpace(model.DifficultyCode) &&
                    !string.IsNullOrWhiteSpace(model.DifficultyJustification),
                provenance.Count > 0);

            var warnings = new List<string>(model.Warnings);
            if (!hasContext)
            {
                warnings.Add("Falta ancla exacta a una línea y revisión de letra.");
            }

            if (optionCount < 2)
            {
                warnings.Add("La revisión todavía no conserva al menos dos opciones.");
            }

            if (!completeness.HasSolution)
            {
                warnings.Add("La solución no referencia opciones conservadas por esta revisión.");
            }

            if (!completeness.HasExplanation)
            {
                warnings.Add("Falta explicación educativa.");
            }

            if (!completeness.HasDifficulty)
            {
                warnings.Add("Falta dificultad editorial justificada.");
            }

            if (!completeness.HasProvenance)
            {
                warnings.Add("Falta procedencia editorial.");
            }

            revisions.Add(
                new ExerciseRevisionSnapshot(
                    revision.ExerciseRevisionId,
                    revision.RevisionNo,
                    revision.StatusCode,
                    revision.Prompt,
                    revision.ChecksumSha256,
                    revision.Version,
                    model.SchemaVersion,
                    model.AnswerModel,
                    model.Explanation,
                    new ExerciseFeedbackSnapshot(
                        model.CorrectFeedback,
                        model.IncorrectFeedback),
                    new ExerciseDifficultySnapshot(
                        model.DifficultyCode,
                        model.DifficultyJustification),
                    items,
                    solutionValues,
                    provenance,
                    completeness,
                    warnings));
        }

        return revisions;
    }

    private static async Task<IReadOnlyList<ExerciseItemSnapshot>> ReadItemsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid exerciseRevisionId,
        IReadOnlyList<int> acceptedItemOrders,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                exercise_item_id,
                item_type,
                item_order,
                prompt_fragment,
                expected_value::text,
                metadata::text
            FROM learning.exercise_item
            WHERE exercise_revision_id = @exercise_revision_id
            ORDER BY item_order, exercise_item_id;
            """;

        var accepted = acceptedItemOrders.ToHashSet();
        var result = new List<ExerciseItemSnapshot>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "exercise_revision_id",
            NpgsqlDbType.Uuid,
            exerciseRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var itemOrder = reader.GetInt32(2);
            var expectedValueJson = reader.IsDBNull(4) ? null : reader.GetString(4);
            var metadataJson = reader.GetString(5);

            result.Add(
                new ExerciseItemSnapshot(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    itemOrder,
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    JsonValueForDisplay(expectedValueJson),
                    metadataJson,
                    accepted.Contains(itemOrder)));
        }

        return result;
    }

    private static async Task<IReadOnlyList<ExerciseProvenanceSnapshot>> ReadProvenanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid exerciseRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                source.source_type,
                source.citation,
                source.locator,
                provenance.contribution_type,
                provenance.recorded_at
            FROM editorial.provenance_record AS provenance
            INNER JOIN catalog.source_reference AS source
                ON source.source_reference_id = provenance.source_reference_id
            WHERE provenance.object_type = 'EXERCISE_REVISION'
              AND provenance.object_id = @exercise_revision_id
            ORDER BY provenance.recorded_at, provenance.provenance_id;
            """;

        var result = new List<ExerciseProvenanceSnapshot>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "exercise_revision_id",
            NpgsqlDbType.Uuid,
            exerciseRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new ExerciseProvenanceSnapshot(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3),
                    reader.GetFieldValue<DateTimeOffset>(4)));
        }

        return result;
    }

    private static SolutionSpecModel ParseSolutionSpec(string json)
    {
        var warnings = new List<string>();

        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;

            var schemaVersion = ReadInt(root, "schemaVersion");
            if (schemaVersion != 1)
            {
                warnings.Add("El contrato solution_spec no usa schemaVersion 1.");
            }

            var answerModel = ReadString(root, "answerModel") ?? "UNSPECIFIED";
            var explanation = ReadString(root, "explanation");

            string? correctFeedback = null;
            string? incorrectFeedback = null;
            if (root.TryGetProperty("feedback", out var feedback) &&
                feedback.ValueKind == JsonValueKind.Object)
            {
                correctFeedback = ReadString(feedback, "correct");
                incorrectFeedback = ReadString(feedback, "incorrect");
            }

            string? difficultyCode = null;
            string? difficultyJustification = null;
            if (root.TryGetProperty("difficulty", out var difficulty) &&
                difficulty.ValueKind == JsonValueKind.Object)
            {
                difficultyCode = ReadString(difficulty, "code");
                difficultyJustification = ReadString(difficulty, "justification");
            }

            var acceptedItemOrders = new List<int>();
            if (root.TryGetProperty("acceptedItemOrders", out var accepted) &&
                accepted.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in accepted.EnumerateArray())
                {
                    if (item.ValueKind == JsonValueKind.Number &&
                        item.TryGetInt32(out var itemOrder) &&
                        itemOrder >= 0)
                    {
                        acceptedItemOrders.Add(itemOrder);
                    }
                }
            }

            return new SolutionSpecModel(
                schemaVersion,
                answerModel,
                explanation,
                correctFeedback,
                incorrectFeedback,
                difficultyCode,
                difficultyJustification,
                acceptedItemOrders.Distinct().Order().ToArray(),
                warnings);
        }
        catch (JsonException)
        {
            warnings.Add("solution_spec no cumple un documento JSON legible.");
            return new SolutionSpecModel(
                null,
                "UNSPECIFIED",
                null,
                null,
                null,
                null,
                null,
                [],
                warnings);
        }
    }

    private static int? ReadInt(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) &&
               property.ValueKind == JsonValueKind.Number &&
               property.TryGetInt32(out var value)
            ? value
            : null;
    }

    private static string? ReadString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) &&
               property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    private static string? JsonValueForDisplay(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.ValueKind switch
            {
                JsonValueKind.String => document.RootElement.GetString(),
                JsonValueKind.Null => null,
                _ => document.RootElement.GetRawText()
            };
        }
        catch (JsonException)
        {
            return json;
        }
    }

    private sealed record DefinitionRow(
        Guid ExerciseId,
        string ExerciseType,
        string StatusCode,
        long Version,
        string CompetencyCode,
        string CompetencyDomainCode,
        string CompetencyTitle,
        Guid? LineId,
        int? LineNo,
        string? JapaneseText,
        Guid? LyricsRevisionId,
        int? LyricsRevisionNo,
        string? LyricsRevisionChecksumSha256);

    private sealed record RevisionRow(
        Guid ExerciseRevisionId,
        int RevisionNo,
        string Prompt,
        string SolutionSpecJson,
        string StatusCode,
        string ChecksumSha256,
        long Version);

    private sealed record SolutionSpecModel(
        int? SchemaVersion,
        string AnswerModel,
        string? Explanation,
        string? CorrectFeedback,
        string? IncorrectFeedback,
        string? DifficultyCode,
        string? DifficultyJustification,
        IReadOnlyList<int> AcceptedItemOrders,
        IReadOnlyList<string> Warnings);
}

public sealed record ExerciseBankSnapshot(
    Guid RecordingId,
    int ExerciseCount,
    IReadOnlyList<ExerciseBankEntry> Exercises);

public sealed record ExerciseBankEntry(
    Guid ExerciseId,
    string ExerciseType,
    string StatusCode,
    long Version,
    ExerciseCompetencySnapshot Competency,
    ExerciseSourceSnapshot Source,
    IReadOnlyList<ExerciseRevisionSnapshot> Revisions);

public sealed record ExerciseCompetencySnapshot(
    string Code,
    string DomainCode,
    string Title);

public sealed record ExerciseSourceSnapshot(
    Guid RecordingId,
    Guid? LineId,
    int? LineNo,
    string? JapaneseText,
    Guid? LyricsRevisionId,
    int? LyricsRevisionNo,
    string? LyricsRevisionChecksumSha256);

public sealed record ExerciseRevisionSnapshot(
    Guid ExerciseRevisionId,
    int RevisionNo,
    string StatusCode,
    string Prompt,
    string ChecksumSha256,
    long Version,
    int? SchemaVersion,
    string AnswerModel,
    string? Explanation,
    ExerciseFeedbackSnapshot Feedback,
    ExerciseDifficultySnapshot Difficulty,
    IReadOnlyList<ExerciseItemSnapshot> Items,
    IReadOnlyList<string> Solutions,
    IReadOnlyList<ExerciseProvenanceSnapshot> Provenance,
    ExerciseRevisionCompleteness Completeness,
    IReadOnlyList<string> Warnings);

public sealed record ExerciseFeedbackSnapshot(
    string? Correct,
    string? Incorrect);

public sealed record ExerciseDifficultySnapshot(
    string? Code,
    string? Justification);

public sealed record ExerciseItemSnapshot(
    Guid ExerciseItemId,
    string ItemType,
    int ItemOrder,
    string? Label,
    string? Value,
    string MetadataJson,
    bool IsAccepted);

public sealed record ExerciseProvenanceSnapshot(
    string SourceType,
    string Citation,
    string? Locator,
    string ContributionType,
    DateTimeOffset RecordedAt);

public sealed record ExerciseRevisionCompleteness(
    bool HasContext,
    bool HasOptions,
    bool HasSolution,
    bool HasExplanation,
    bool HasDifficulty,
    bool HasProvenance)
{
    public bool ReadyForReview =>
        HasContext &&
        HasOptions &&
        HasSolution &&
        HasExplanation &&
        HasDifficulty &&
        HasProvenance;
}

public sealed class ExerciseBankAdministrationException(
    string code,
    string message) : Exception(message)
{
    public string Code { get; } = code;
}
