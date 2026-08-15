using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Learning.Infrastructure.Administration;

public sealed class FillBlankExerciseAuthoringService(
    IExerciseBankAdministrationTransactionExecutor transactions)
{
    private static readonly int[] AcceptedItemOrders = [1];

    private static readonly IReadOnlyList<ExerciseCompetencyChoice> Competencies =
    [
        new("VOCAB.CONTEXT", "VOCABULARY", "Vocabulario en contexto",
            "Reconocer una palabra o expresión dentro de la línea exacta."),
        new("GRAMMAR.CONTEXT", "GRAMMAR", "Gramática en contexto",
            "Reconocer una partícula, construcción o forma gramatical dentro de la línea exacta."),
        new("READING.CONTEXT", "READING", "Comprensión de la línea",
            "Reconocer una unidad que completa correctamente la línea dentro de su contexto.")
    ];

    public async Task<FillBlankAuthoringContext> ReadContextAsync(
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
                await ReadContextCoreAsync(connection, transaction, recordingId, token),
            cancellationToken);
    }

    public async Task<FillBlankDraftSaved> SaveDraftAsync(
        Guid actorAccountId,
        Guid recordingId,
        FillBlankDraftInput input,
        string ifMatch,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException("El actor es obligatorio.", nameof(actorAccountId));
        }

        ArgumentNullException.ThrowIfNull(input);

        return await transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                var context = await ReadContextCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                if (!string.Equals(ETagFor(context), ifMatch.Trim(), StringComparison.Ordinal))
                {
                    throw new FillBlankExerciseAuthoringException(
                        "learning.fill-blank.source-changed",
                        "La revisión DRAFT de la letra cambió. Tu borrador sigue en pantalla; recarga la fuente antes de guardar.");
                }

                var normalized = ValidateAndNormalize(context, input);

                var spec = new
                {
                    schemaVersion = 1,
                    answerModel = "SINGLE_CHOICE",
                    acceptedItemOrders = AcceptedItemOrders,
                    explanation = normalized.Explanation,
                    feedback = new
                    {
                        correct = normalized.FeedbackCorrect,
                        incorrect = normalized.FeedbackIncorrect
                    },
                    difficulty = new
                    {
                        code = normalized.DifficultyCode,
                        justification = normalized.DifficultyJustification
                    },
                    blank = new
                    {
                        tokenId = normalized.TokenId,
                        surface = normalized.CorrectAnswer
                    }
                };

                var solutionSpecJson = JsonSerializer.Serialize(spec);
                var distractorsJson = JsonSerializer.Serialize(normalized.Distractors);
                var checksum = SHA256.HashData(
                    Encoding.UTF8.GetBytes(
                        $"{normalized.LyricsRevisionId:N}|{normalized.LineId:N}|{normalized.TokenId:N}|{normalized.Prompt}|{solutionSpecJson}|{distractorsJson}"));

                const string sql = """
                    SELECT
                        exercise_id,
                        exercise_revision_id,
                        revision_no,
                        version
                    FROM learning.save_fill_blank_exercise_draft(
                        @recording_id,
                        @line_id,
                        @lyrics_revision_id,
                        @token_id,
                        @competency_code,
                        @prompt,
                        CAST(@distractors AS jsonb),
                        @explanation,
                        @feedback_correct,
                        @feedback_incorrect,
                        @difficulty_code,
                        @difficulty_justification,
                        @checksum
                    );
                    """;

                await using var command = new NpgsqlCommand(sql, connection, transaction);
                command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
                command.Parameters.AddWithValue("line_id", NpgsqlDbType.Uuid, normalized.LineId);
                command.Parameters.AddWithValue("lyrics_revision_id", NpgsqlDbType.Uuid, normalized.LyricsRevisionId);
                command.Parameters.AddWithValue("token_id", NpgsqlDbType.Uuid, normalized.TokenId);
                command.Parameters.AddWithValue("competency_code", NpgsqlDbType.Text, normalized.CompetencyCode);
                command.Parameters.AddWithValue("prompt", NpgsqlDbType.Text, normalized.Prompt);
                command.Parameters.AddWithValue("distractors", NpgsqlDbType.Text, distractorsJson);
                command.Parameters.AddWithValue("explanation", NpgsqlDbType.Text, normalized.Explanation);
                command.Parameters.AddWithValue("feedback_correct", NpgsqlDbType.Text, normalized.FeedbackCorrect);
                command.Parameters.AddWithValue("feedback_incorrect", NpgsqlDbType.Text, normalized.FeedbackIncorrect);
                command.Parameters.AddWithValue("difficulty_code", NpgsqlDbType.Text, normalized.DifficultyCode);
                command.Parameters.AddWithValue(
                    "difficulty_justification",
                    NpgsqlDbType.Text,
                    normalized.DifficultyJustification);
                command.Parameters.AddWithValue("checksum", NpgsqlDbType.Bytea, checksum);

                await using var reader = await command.ExecuteReaderAsync(token);
                if (!await reader.ReadAsync(token))
                {
                    throw new InvalidOperationException(
                        "La operación DRAFT no devolvió la revisión guardada.");
                }

                return new FillBlankDraftSaved(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetInt32(2),
                    reader.GetInt64(3),
                    "DRAFT",
                    "Borrador guardado. Todavía no está publicado ni disponible para estudiantes.");
            },
            cancellationToken);
    }

    public static string ETagFor(FillBlankAuthoringContext context)
    {
        var payload =
            $"{context.RecordingId:N}|{context.LyricsRevisionId?.ToString("N") ?? "none"}|{context.LyricsRevisionNo?.ToString(CultureInfo.InvariantCulture) ?? "none"}|{context.LyricsRevisionChecksumSha256 ?? "none"}";
        var digest = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload))).ToLowerInvariant();
        return $"\"bl071-{digest}\"";
    }

    private static async Task<FillBlankAuthoringContext> ReadContextCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string recordingSql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.recording
                WHERE recording_id = @recording_id
            );
            """;

        await using (var recordingCommand = new NpgsqlCommand(recordingSql, connection, transaction))
        {
            recordingCommand.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
            if (!(bool)(await recordingCommand.ExecuteScalarAsync(cancellationToken) ?? false))
            {
                throw new FillBlankExerciseAuthoringException(
                    "learning.fill-blank.recording.not-found",
                    "La canción editorial solicitada no existe.");
            }
        }

        const string revisionSql = """
            SELECT
                lyrics_revision_id,
                revision_no,
                encode(checksum, 'hex')
            FROM content.lyrics_revision
            WHERE recording_id = @recording_id
              AND status_code = 'DRAFT'
            ORDER BY revision_no DESC, lyrics_revision_id DESC
            LIMIT 1;
            """;

        Guid? revisionId = null;
        int? revisionNo = null;
        string? revisionChecksum = null;

        await using (var revisionCommand = new NpgsqlCommand(revisionSql, connection, transaction))
        {
            revisionCommand.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
            await using var reader = await revisionCommand.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                revisionId = reader.GetGuid(0);
                revisionNo = reader.GetInt32(1);
                revisionChecksum = reader.GetString(2);
            }
        }

        if (!revisionId.HasValue)
        {
            return new FillBlankAuthoringContext(
                recordingId,
                null,
                null,
                null,
                [],
                Competencies,
                false,
                "Necesitas una revisión DRAFT de la letra antes de crear ejercicios.");
        }

        const string lineSql = """
            SELECT
                line.line_id,
                line.line_no,
                line.japanese_text,
                token.token_id,
                token.token_no,
                token.surface
            FROM content.lyric_section AS section
            INNER JOIN content.lyric_line AS line
                ON line.section_id = section.section_id
            LEFT JOIN content.lyric_token AS token
                ON token.line_id = line.line_id
            WHERE section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY section.display_order, line.line_no, token.token_no;
            """;

        var lines = new List<MutableLine>();

        await using (var lineCommand = new NpgsqlCommand(lineSql, connection, transaction))
        {
            lineCommand.Parameters.AddWithValue("lyrics_revision_id", NpgsqlDbType.Uuid, revisionId.Value);
            await using var reader = await lineCommand.ExecuteReaderAsync(cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                var lineId = reader.GetGuid(0);
                var line = lines.FirstOrDefault(candidate => candidate.LineId == lineId);
                if (line is null)
                {
                    line = new MutableLine(
                        lineId,
                        reader.GetInt32(1),
                        reader.GetString(2));
                    lines.Add(line);
                }

                if (!reader.IsDBNull(3))
                {
                    line.Tokens.Add(
                        new FillBlankSourceToken(
                            reader.GetGuid(3),
                            reader.GetInt32(4),
                            reader.GetString(5)));
                }
            }
        }

        var snapshots = lines
            .Select(line => new FillBlankSourceLine(
                line.LineId,
                line.LineNo,
                line.JapaneseText,
                line.Tokens))
            .ToArray();

        var usable = snapshots.Any(line => line.Tokens.Count > 0);

        return new FillBlankAuthoringContext(
            recordingId,
            revisionId,
            revisionNo,
            revisionChecksum,
            snapshots,
            Competencies,
            usable,
            usable
                ? null
                : "La letra DRAFT existe, pero todavía no tiene tokens. Segmenta la letra antes de elegir el espacio.");
    }

    private static NormalizedDraft ValidateAndNormalize(
        FillBlankAuthoringContext context,
        FillBlankDraftInput input)
    {
        if (!context.LyricsRevisionId.HasValue || !context.CanAuthor)
        {
            throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.source-unavailable",
                context.BlockingReason ?? "La fuente DRAFT todavía no está lista.");
        }

        if (input.LyricsRevisionId != context.LyricsRevisionId.Value)
        {
            throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.source-changed",
                "La revisión DRAFT seleccionada ya no es la vigente.");
        }

        var line = context.Lines.FirstOrDefault(candidate => candidate.LineId == input.LineId)
            ?? throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.line.invalid",
                "La línea seleccionada no pertenece a la revisión DRAFT exacta.");

        var sourceToken = line.Tokens.FirstOrDefault(candidate => candidate.TokenId == input.TokenId)
            ?? throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.token.invalid",
                "El espacio seleccionado no pertenece a la línea exacta.");

        var competency = Competencies.FirstOrDefault(candidate =>
            string.Equals(candidate.Code, input.CompetencyCode, StringComparison.Ordinal))
            ?? throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.competency.invalid",
                "Elige una competencia disponible.");

        var prompt = Required(input.Prompt, 240, "Escribe una instrucción breve para el estudiante.");
        var explanation = Required(input.Explanation, 1200, "Agrega una explicación educativa.");
        var feedbackCorrect = Required(
            input.FeedbackCorrect,
            500,
            "Indica qué verá el estudiante cuando acierte.");
        var feedbackIncorrect = Required(
            input.FeedbackIncorrect,
            500,
            "Indica qué verá el estudiante cuando falle.");
        var difficultyJustification = Required(
            input.DifficultyJustification,
            500,
            "Explica brevemente por qué elegiste esa dificultad.");

        var difficultyCode = input.DifficultyCode?.Trim().ToUpperInvariant();
        if (difficultyCode is not ("BEGINNER" or "INTERMEDIATE" or "ADVANCED"))
        {
            throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.difficulty.invalid",
                "Elige Básico, Intermedio o Avanzado.");
        }

        if (input.Distractors is null || input.Distractors.Count is < 2 or > 4)
        {
            throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.options.count",
                "Agrega entre 2 y 4 distractores.");
        }

        var correctKey = NormalizeOption(sourceToken.Surface);
        var normalizedKeys = new HashSet<string>(StringComparer.Ordinal);
        var distractors = new List<string>(input.Distractors.Count);

        foreach (var candidate in input.Distractors)
        {
            var value = Required(candidate, 120, "Los distractores no pueden quedar vacíos.");
            var key = NormalizeOption(value);

            if (key == correctKey)
            {
                throw new FillBlankExerciseAuthoringException(
                    "learning.fill-blank.options.ambiguous",
                    $"“{value}” coincide con la respuesta correcta. Cámbialo por una opción claramente distinta.");
            }

            if (!normalizedKeys.Add(key))
            {
                throw new FillBlankExerciseAuthoringException(
                    "learning.fill-blank.options.duplicate",
                    $"“{value}” está repetido. Cada opción debe ser distinguible.");
            }

            distractors.Add(value);
        }

        return new NormalizedDraft(
            input.LyricsRevisionId,
            input.LineId,
            input.TokenId,
            competency.Code,
            sourceToken.Surface,
            prompt,
            distractors,
            explanation,
            feedbackCorrect,
            feedbackIncorrect,
            difficultyCode,
            difficultyJustification);
    }

    private static string Required(string? value, int maxLength, string message)
    {
        var normalized = value?.Trim();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.required",
                message);
        }

        if (normalized.Length > maxLength)
        {
            throw new FillBlankExerciseAuthoringException(
                "learning.fill-blank.too-long",
                $"El campo supera {maxLength} caracteres.");
        }

        return normalized;
    }

    private static string NormalizeOption(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormKC).Trim();
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

    private sealed class MutableLine(Guid lineId, int lineNo, string japaneseText)
    {
        public Guid LineId { get; } = lineId;
        public int LineNo { get; } = lineNo;
        public string JapaneseText { get; } = japaneseText;
        public List<FillBlankSourceToken> Tokens { get; } = [];
    }

    private sealed record NormalizedDraft(
        Guid LyricsRevisionId,
        Guid LineId,
        Guid TokenId,
        string CompetencyCode,
        string CorrectAnswer,
        string Prompt,
        IReadOnlyList<string> Distractors,
        string Explanation,
        string FeedbackCorrect,
        string FeedbackIncorrect,
        string DifficultyCode,
        string DifficultyJustification);
}

public sealed record FillBlankDraftInput(
    Guid LyricsRevisionId,
    Guid LineId,
    Guid TokenId,
    string CompetencyCode,
    string Prompt,
    IReadOnlyList<string> Distractors,
    string Explanation,
    string FeedbackCorrect,
    string FeedbackIncorrect,
    string DifficultyCode,
    string DifficultyJustification);

public sealed record FillBlankAuthoringContext(
    Guid RecordingId,
    Guid? LyricsRevisionId,
    int? LyricsRevisionNo,
    string? LyricsRevisionChecksumSha256,
    IReadOnlyList<FillBlankSourceLine> Lines,
    IReadOnlyList<ExerciseCompetencyChoice> Competencies,
    bool CanAuthor,
    string? BlockingReason);

public sealed record FillBlankSourceLine(
    Guid LineId,
    int LineNo,
    string JapaneseText,
    IReadOnlyList<FillBlankSourceToken> Tokens);

public sealed record FillBlankSourceToken(
    Guid TokenId,
    int TokenNo,
    string Surface);

public sealed record ExerciseCompetencyChoice(
    string Code,
    string DomainCode,
    string Title,
    string Description);

public sealed record FillBlankDraftSaved(
    Guid ExerciseId,
    Guid ExerciseRevisionId,
    int RevisionNo,
    long Version,
    string StatusCode,
    string Message);

public sealed class FillBlankExerciseAuthoringException(
    string code,
    string message) : Exception(message)
{
    public string Code { get; } = code;
}
