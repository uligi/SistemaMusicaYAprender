using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.Administration;

public sealed record LinguisticSourceTokenSnapshot(
    Guid TokenId,
    Guid LineId,
    int LineNo,
    int TokenNo,
    string Surface,
    string NormalizedSurface);

public sealed record LinguisticSourceLineSnapshot(
    Guid LineId,
    int LineNo,
    int SectionDisplayOrder,
    string? SectionLabel,
    string JapaneseText,
    List<LinguisticSourceTokenSnapshot> Tokens);

public sealed record TokenReadingAnalysisSnapshot(
    Guid TokenReadingId,
    Guid TokenId,
    Guid LineId,
    int LineNo,
    string Surface,
    string ReadingKana,
    string? Furigana,
    string? Romaji,
    string ReadingType);

public sealed record VocabularySenseAnalysisSnapshot(
    Guid SenseId,
    string LanguageTag,
    string Definition,
    string? UsageNote,
    int DisplayOrder);

public sealed record VocabularyOccurrenceAnalysisSnapshot(
    Guid OccurrenceId,
    Guid TokenId,
    Guid LineId,
    int LineNo,
    string Surface,
    Guid VocabularyId,
    string Lemma,
    string? Reading,
    string? PartOfSpeech,
    string SenseKey,
    string? Inflection,
    string ConfidenceCode,
    List<VocabularySenseAnalysisSnapshot> Senses);

public sealed record MorphologyAnalysisSnapshot(
    Guid AnnotationId,
    Guid TokenId,
    Guid LineId,
    int LineNo,
    string Surface,
    string Lemma,
    string PartOfSpeechCode,
    string? ConjugationCode,
    string FeaturesJson);

public sealed record GrammarOccurrenceAnalysisSnapshot(
    Guid OccurrenceId,
    Guid LineId,
    int LineNo,
    string JapaneseText,
    Guid GrammarPointId,
    string GrammarCode,
    string Title,
    string? LevelCode,
    Guid? StartTokenId,
    Guid? EndTokenId,
    string? Note,
    string? Explanation,
    string? Examples);

public sealed record LinguisticAnalysisProvenanceSnapshot(
    Guid SourceReferenceId,
    string SourceType,
    string Citation,
    string? Locator,
    string ContributionType,
    Guid RecordedBy,
    DateTimeOffset RecordedAt);

public sealed record LinguisticAnalysisRevisionSnapshot(
    Guid AnalysisRevisionId,
    Guid LyricsRevisionId,
    int LyricsRevisionNo,
    int RevisionNo,
    Guid? ParentRevisionId,
    string StatusCode,
    string ChecksumSha256,
    int SourceLineCount,
    int SourceTokenCount,
    int ReadingCoveredTokens,
    int VocabularyCoveredTokens,
    int MorphologyCoveredTokens,
    int GrammarCoveredLines,
    List<TokenReadingAnalysisSnapshot> Readings,
    List<VocabularyOccurrenceAnalysisSnapshot> Vocabulary,
    List<MorphologyAnalysisSnapshot> Morphology,
    List<GrammarOccurrenceAnalysisSnapshot> Grammar,
    List<LinguisticAnalysisProvenanceSnapshot> Provenance);

public sealed record LinguisticAnalysisContextSnapshot(
    Guid RecordingId,
    Guid? LyricsRevisionId,
    int? LyricsRevisionNo,
    string ExplanationLanguage,
    bool HasStaleRevision,
    List<LinguisticSourceLineSnapshot> SourceLines,
    LinguisticAnalysisRevisionSnapshot? Revision);

public sealed class LinguisticAnalysisAdministrationException(
    string code,
    string message)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed partial class LinguisticAnalysisRevisionAdministrationService(
    ILinguisticAnalysisAdministrationTransactionExecutor transactionExecutor)
{
    [GeneratedRegex(
        "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex LanguageTagPattern();

    public Task<LinguisticAnalysisContextSnapshot> ReadContextAsync(
        Guid actorAccountId,
        Guid recordingId,
        string explanationLanguage,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(actorAccountId, recordingId, correlationId);
        var language = PrepareLanguage(explanationLanguage);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ReadContextCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    language,
                    token),
            cancellationToken);
    }

    private static async Task<LinguisticAnalysisContextSnapshot> ReadContextCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        string language,
        CancellationToken cancellationToken)
    {
        await AssertRecordingExistsAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var latestLyrics = await ReadLatestLyricsRevisionAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        if (latestLyrics is null)
        {
            return new LinguisticAnalysisContextSnapshot(
                recordingId,
                null,
                null,
                language,
                false,
                [],
                null);
        }

        var sourceLines = await ReadSourceLinesAsync(
            connection,
            transaction,
            latestLyrics.LyricsRevisionId,
            cancellationToken);

        var analysisHeader = await ReadCompatibleAnalysisHeaderAsync(
            connection,
            transaction,
            latestLyrics.LyricsRevisionId,
            cancellationToken);

        if (analysisHeader is null)
        {
            var stale = await HasStaleAnalysisAsync(
                connection,
                transaction,
                recordingId,
                latestLyrics.LyricsRevisionId,
                cancellationToken);

            return new LinguisticAnalysisContextSnapshot(
                recordingId,
                latestLyrics.LyricsRevisionId,
                latestLyrics.RevisionNo,
                language,
                stale,
                sourceLines,
                null);
        }

        var readings = await ReadTokenReadingsAsync(
            connection,
            transaction,
            analysisHeader.AnalysisRevisionId,
            latestLyrics.LyricsRevisionId,
            cancellationToken);

        var vocabulary = await ReadVocabularyAsync(
            connection,
            transaction,
            analysisHeader.AnalysisRevisionId,
            latestLyrics.LyricsRevisionId,
            language,
            cancellationToken);

        var morphology = await ReadMorphologyAsync(
            connection,
            transaction,
            analysisHeader.AnalysisRevisionId,
            latestLyrics.LyricsRevisionId,
            cancellationToken);

        var grammar = await ReadGrammarAsync(
            connection,
            transaction,
            analysisHeader.AnalysisRevisionId,
            latestLyrics.LyricsRevisionId,
            language,
            cancellationToken);

        var provenance = await ReadProvenanceAsync(
            connection,
            transaction,
            analysisHeader.AnalysisRevisionId,
            cancellationToken);

        var sourceTokenCount = sourceLines.Sum(line => line.Tokens.Count);

        var revision = new LinguisticAnalysisRevisionSnapshot(
            analysisHeader.AnalysisRevisionId,
            latestLyrics.LyricsRevisionId,
            latestLyrics.RevisionNo,
            analysisHeader.RevisionNo,
            analysisHeader.ParentRevisionId,
            analysisHeader.StatusCode,
            analysisHeader.ChecksumSha256,
            sourceLines.Count,
            sourceTokenCount,
            readings.Select(item => item.TokenId).Distinct().Count(),
            vocabulary.Select(item => item.TokenId).Distinct().Count(),
            morphology.Select(item => item.TokenId).Distinct().Count(),
            grammar.Select(item => item.LineId).Distinct().Count(),
            readings,
            vocabulary,
            morphology,
            grammar,
            provenance);

        return new LinguisticAnalysisContextSnapshot(
            recordingId,
            latestLyrics.LyricsRevisionId,
            latestLyrics.RevisionNo,
            language,
            false,
            sourceLines,
            revision);
    }

    private static async Task AssertRecordingExistsAsync(
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

        if (await command.ExecuteScalarAsync(cancellationToken) is not true)
        {
            throw new LinguisticAnalysisAdministrationException(
                "content.analysis.recording.not-found",
                "La canción editorial indicada no existe.");
        }
    }

    private static async Task<LyricsHeader?> ReadLatestLyricsRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                lyrics_revision_id,
                revision_no
            FROM content.lyrics_revision
            WHERE recording_id = @recording_id
            ORDER BY revision_no DESC, lyrics_revision_id DESC
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new LyricsHeader(
            reader.GetGuid(0),
            reader.GetInt32(1));
    }

    private static async Task<List<LinguisticSourceLineSnapshot>> ReadSourceLinesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                line.line_id,
                line.line_no,
                section.display_order,
                section.label,
                line.japanese_text,
                token.token_id,
                token.token_no,
                token.surface,
                token.normalized_surface
            FROM content.lyric_section AS section
            JOIN content.lyric_line AS line
              ON line.section_id = section.section_id
            LEFT JOIN content.lyric_token AS token
              ON token.line_id = line.line_id
            WHERE section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                section.display_order,
                section.section_id,
                line.line_no,
                line.line_id,
                token.token_no,
                token.token_id;
            """;

        var builders = new Dictionary<Guid, SourceLineBuilder>();
        var order = new List<Guid>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var lineId = reader.GetGuid(0);
            if (!builders.TryGetValue(lineId, out var builder))
            {
                builder = new SourceLineBuilder(
                    lineId,
                    reader.GetInt32(1),
                    reader.GetInt32(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.GetString(4));
                builders.Add(lineId, builder);
                order.Add(lineId);
            }

            if (!reader.IsDBNull(5))
            {
                builder.Tokens.Add(
                    new LinguisticSourceTokenSnapshot(
                        reader.GetGuid(5),
                        lineId,
                        reader.GetInt32(1),
                        reader.GetInt32(6),
                        reader.GetString(7),
                        reader.GetString(8)));
            }
        }

        return order
            .Select(lineId => builders[lineId].ToSnapshot())
            .ToList();
    }

    private static async Task<AnalysisHeader?> ReadCompatibleAnalysisHeaderAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                analysis_revision_id,
                revision_no,
                parent_revision_id,
                status_code,
                encode(checksum, 'hex')
            FROM content.linguistic_analysis_revision
            WHERE lyrics_revision_id = @lyrics_revision_id
            ORDER BY revision_no DESC, analysis_revision_id DESC
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new AnalysisHeader(
            reader.GetGuid(0),
            reader.GetInt32(1),
            reader.IsDBNull(2) ? null : reader.GetGuid(2),
            reader.GetString(3),
            reader.GetString(4));
    }

    private static async Task<bool> HasStaleAnalysisAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid currentLyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM content.linguistic_analysis_revision AS analysis
                JOIN content.lyrics_revision AS lyrics
                  ON lyrics.lyrics_revision_id = analysis.lyrics_revision_id
                WHERE lyrics.recording_id = @recording_id
                  AND analysis.lyrics_revision_id <> @lyrics_revision_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            currentLyricsRevisionId);

        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    private static async Task<List<TokenReadingAnalysisSnapshot>> ReadTokenReadingsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                reading.token_reading_id,
                reading.token_id,
                line.line_id,
                line.line_no,
                token.surface,
                reading.reading_kana,
                reading.furigana,
                reading.romaji,
                reading.reading_type
            FROM content.token_reading AS reading
            JOIN content.lyric_token AS token
              ON token.token_id = reading.token_id
            JOIN content.lyric_line AS line
              ON line.line_id = token.line_id
            JOIN content.lyric_section AS section
              ON section.section_id = line.section_id
            WHERE reading.analysis_revision_id = @analysis_revision_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                section.display_order,
                section.section_id,
                line.line_no,
                line.line_id,
                token.token_no,
                token.token_id,
                reading.token_reading_id;
            """;

        var result = new List<TokenReadingAnalysisSnapshot>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new TokenReadingAnalysisSnapshot(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetGuid(2),
                    reader.GetInt32(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.IsDBNull(6) ? null : reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetString(7),
                    reader.GetString(8)));
        }

        return result;
    }

    private static async Task<List<VocabularyOccurrenceAnalysisSnapshot>> ReadVocabularyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        string language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                occurrence.occurrence_id,
                occurrence.token_id,
                line.line_id,
                line.line_no,
                token.surface,
                entry.vocabulary_id,
                entry.lemma,
                entry.reading,
                entry.part_of_speech,
                entry.sense_key,
                occurrence.inflection,
                occurrence.confidence_code,
                sense.sense_id,
                sense.language_tag,
                sense.definition,
                sense.usage_note,
                sense.display_order
            FROM content.vocabulary_occurrence AS occurrence
            JOIN content.lyric_token AS token
              ON token.token_id = occurrence.token_id
            JOIN content.lyric_line AS line
              ON line.line_id = token.line_id
            JOIN content.lyric_section AS section
              ON section.section_id = line.section_id
            JOIN content.vocabulary_entry AS entry
              ON entry.vocabulary_id = occurrence.vocabulary_id
            LEFT JOIN content.vocabulary_sense AS sense
              ON sense.vocabulary_id = entry.vocabulary_id
             AND sense.language_tag = @language
            WHERE occurrence.analysis_revision_id = @analysis_revision_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                section.display_order,
                section.section_id,
                line.line_no,
                line.line_id,
                token.token_no,
                token.token_id,
                occurrence.occurrence_id,
                sense.display_order,
                sense.sense_id;
            """;

        var builders = new Dictionary<Guid, VocabularyBuilder>();
        var order = new List<Guid>();

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue("language", NpgsqlDbType.Varchar, language);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var occurrenceId = reader.GetGuid(0);
            if (!builders.TryGetValue(occurrenceId, out var builder))
            {
                builder = new VocabularyBuilder(
                    occurrenceId,
                    reader.GetGuid(1),
                    reader.GetGuid(2),
                    reader.GetInt32(3),
                    reader.GetString(4),
                    reader.GetGuid(5),
                    reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetString(7),
                    reader.IsDBNull(8) ? null : reader.GetString(8),
                    reader.GetString(9),
                    reader.IsDBNull(10) ? null : reader.GetString(10),
                    reader.GetString(11));
                builders.Add(occurrenceId, builder);
                order.Add(occurrenceId);
            }

            if (!reader.IsDBNull(12))
            {
                builder.Senses.Add(
                    new VocabularySenseAnalysisSnapshot(
                        reader.GetGuid(12),
                        reader.GetString(13),
                        reader.GetString(14),
                        reader.IsDBNull(15) ? null : reader.GetString(15),
                        reader.GetInt32(16)));
            }
        }

        return order
            .Select(occurrenceId => builders[occurrenceId].ToSnapshot())
            .ToList();
    }

    private static async Task<List<MorphologyAnalysisSnapshot>> ReadMorphologyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                annotation.annotation_id,
                annotation.token_id,
                line.line_id,
                line.line_no,
                token.surface,
                annotation.lemma,
                annotation.pos_code,
                annotation.conjugation_code,
                annotation.features::text
            FROM content.morphology_annotation AS annotation
            JOIN content.lyric_token AS token
              ON token.token_id = annotation.token_id
            JOIN content.lyric_line AS line
              ON line.line_id = token.line_id
            JOIN content.lyric_section AS section
              ON section.section_id = line.section_id
            WHERE annotation.analysis_revision_id = @analysis_revision_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                section.display_order,
                section.section_id,
                line.line_no,
                line.line_id,
                token.token_no,
                token.token_id,
                annotation.annotation_id;
            """;

        var result = new List<MorphologyAnalysisSnapshot>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new MorphologyAnalysisSnapshot(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetGuid(2),
                    reader.GetInt32(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetString(7),
                    reader.GetString(8)));
        }

        return result;
    }

    private static async Task<List<GrammarOccurrenceAnalysisSnapshot>> ReadGrammarAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        string language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                occurrence.occurrence_id,
                occurrence.line_id,
                line.line_no,
                line.japanese_text,
                point.grammar_point_id,
                point.grammar_code,
                point.title,
                point.level_code,
                occurrence.start_token_id,
                occurrence.end_token_id,
                occurrence.note,
                explanation.explanation,
                explanation.examples
            FROM content.grammar_occurrence AS occurrence
            JOIN content.lyric_line AS line
              ON line.line_id = occurrence.line_id
            JOIN content.lyric_section AS section
              ON section.section_id = line.section_id
            JOIN content.grammar_point AS point
              ON point.grammar_point_id = occurrence.grammar_point_id
            LEFT JOIN LATERAL (
                SELECT
                    item.explanation,
                    item.examples
                FROM content.grammar_explanation AS item
                WHERE item.grammar_point_id = point.grammar_point_id
                  AND item.language_tag = @language
                ORDER BY item.revision_no DESC, item.explanation_id DESC
                LIMIT 1
            ) AS explanation ON TRUE
            WHERE occurrence.analysis_revision_id = @analysis_revision_id
              AND section.lyrics_revision_id = @lyrics_revision_id
              AND (
                    occurrence.start_token_id IS NULL
                    OR EXISTS (
                        SELECT 1
                        FROM content.lyric_token AS start_token
                        JOIN content.lyric_line AS start_line
                          ON start_line.line_id = start_token.line_id
                        JOIN content.lyric_section AS start_section
                          ON start_section.section_id = start_line.section_id
                        WHERE start_token.token_id = occurrence.start_token_id
                          AND start_token.line_id = occurrence.line_id
                          AND start_section.lyrics_revision_id = @lyrics_revision_id
                    )
              )
              AND (
                    occurrence.end_token_id IS NULL
                    OR EXISTS (
                        SELECT 1
                        FROM content.lyric_token AS end_token
                        JOIN content.lyric_line AS end_line
                          ON end_line.line_id = end_token.line_id
                        JOIN content.lyric_section AS end_section
                          ON end_section.section_id = end_line.section_id
                        WHERE end_token.token_id = occurrence.end_token_id
                          AND end_token.line_id = occurrence.line_id
                          AND end_section.lyrics_revision_id = @lyrics_revision_id
                    )
              )
            ORDER BY
                section.display_order,
                section.section_id,
                line.line_no,
                line.line_id,
                occurrence.occurrence_id;
            """;

        var result = new List<GrammarOccurrenceAnalysisSnapshot>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue("language", NpgsqlDbType.Varchar, language);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new GrammarOccurrenceAnalysisSnapshot(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetInt32(2),
                    reader.GetString(3),
                    reader.GetGuid(4),
                    reader.GetString(5),
                    reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetString(7),
                    reader.IsDBNull(8) ? null : reader.GetGuid(8),
                    reader.IsDBNull(9) ? null : reader.GetGuid(9),
                    reader.IsDBNull(10) ? null : reader.GetString(10),
                    reader.IsDBNull(11) ? null : reader.GetString(11),
                    reader.IsDBNull(12) ? null : reader.GetString(12)));
        }

        return result;
    }

    private static async Task<List<LinguisticAnalysisProvenanceSnapshot>> ReadProvenanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid analysisRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                source.source_reference_id,
                source.source_type,
                source.citation,
                source.locator,
                provenance.contribution_type,
                provenance.recorded_by,
                provenance.recorded_at
            FROM editorial.provenance_record AS provenance
            JOIN catalog.source_reference AS source
              ON source.source_reference_id = provenance.source_reference_id
            WHERE provenance.object_type = 'LINGUISTIC_ANALYSIS_REVISION'
              AND provenance.object_id = @analysis_revision_id
            ORDER BY provenance.recorded_at, provenance.provenance_id;
            """;

        var result = new List<LinguisticAnalysisProvenanceSnapshot>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new LinguisticAnalysisProvenanceSnapshot(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.GetString(4),
                    reader.GetGuid(5),
                    new DateTimeOffset(reader.GetDateTime(6))));
        }

        return result;
    }

    private static void ValidateIdentity(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new LinguisticAnalysisAdministrationException(
                "content.analysis.actor.invalid",
                "La identidad editorial no es válida.");
        }

        if (recordingId == Guid.Empty)
        {
            throw new LinguisticAnalysisAdministrationException(
                "content.analysis.recording.invalid",
                "La grabación indicada no es válida.");
        }

        if (string.IsNullOrWhiteSpace(correlationId))
        {
            throw new LinguisticAnalysisAdministrationException(
                "content.analysis.correlation.invalid",
                "La correlación de la solicitud es obligatoria.");
        }
    }

    private static string PrepareLanguage(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new LinguisticAnalysisAdministrationException(
                "content.analysis.language.invalid",
                "El idioma de explicación no es válido.");
        }

        var language = value.Trim();
        if (!LanguageTagPattern().IsMatch(language))
        {
            throw new LinguisticAnalysisAdministrationException(
                "content.analysis.language.invalid",
                "El idioma de explicación no es válido.");
        }

        return language;
    }

    private sealed record LyricsHeader(
        Guid LyricsRevisionId,
        int RevisionNo);

    private sealed record AnalysisHeader(
        Guid AnalysisRevisionId,
        int RevisionNo,
        Guid? ParentRevisionId,
        string StatusCode,
        string ChecksumSha256);

    private sealed class SourceLineBuilder(
        Guid lineId,
        int lineNo,
        int sectionDisplayOrder,
        string? sectionLabel,
        string japaneseText)
    {
        public Guid LineId { get; } = lineId;
        public int LineNo { get; } = lineNo;
        public int SectionDisplayOrder { get; } = sectionDisplayOrder;
        public string? SectionLabel { get; } = sectionLabel;
        public string JapaneseText { get; } = japaneseText;
        public List<LinguisticSourceTokenSnapshot> Tokens { get; } = [];

        public LinguisticSourceLineSnapshot ToSnapshot() =>
            new(
                LineId,
                LineNo,
                SectionDisplayOrder,
                SectionLabel,
                JapaneseText,
                Tokens);
    }

    private sealed class VocabularyBuilder(
        Guid occurrenceId,
        Guid tokenId,
        Guid lineId,
        int lineNo,
        string surface,
        Guid vocabularyId,
        string lemma,
        string? reading,
        string? partOfSpeech,
        string senseKey,
        string? inflection,
        string confidenceCode)
    {
        public Guid OccurrenceId { get; } = occurrenceId;
        public Guid TokenId { get; } = tokenId;
        public Guid LineId { get; } = lineId;
        public int LineNo { get; } = lineNo;
        public string Surface { get; } = surface;
        public Guid VocabularyId { get; } = vocabularyId;
        public string Lemma { get; } = lemma;
        public string? Reading { get; } = reading;
        public string? PartOfSpeech { get; } = partOfSpeech;
        public string SenseKey { get; } = senseKey;
        public string? Inflection { get; } = inflection;
        public string ConfidenceCode { get; } = confidenceCode;
        public List<VocabularySenseAnalysisSnapshot> Senses { get; } = [];

        public VocabularyOccurrenceAnalysisSnapshot ToSnapshot() =>
            new(
                OccurrenceId,
                TokenId,
                LineId,
                LineNo,
                Surface,
                VocabularyId,
                Lemma,
                Reading,
                PartOfSpeech,
                SenseKey,
                Inflection,
                ConfidenceCode,
                Senses);
    }
}
