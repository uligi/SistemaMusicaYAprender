using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

public sealed record PublicContextualReading(
    string ReadingKana,
    string? Furigana,
    string? Romaji,
    string ReadingType);

public sealed record PublicContextualVocabularySense(
    string LanguageTag,
    string Definition,
    string? UsageNote,
    int DisplayOrder);

public sealed record PublicContextualVocabulary(
    string Lemma,
    string? Reading,
    string? PartOfSpeech,
    string SenseKey,
    string? Inflection,
    string ConfidenceCode,
    IReadOnlyList<PublicContextualVocabularySense> Senses);

public sealed record PublicContextualKanjiReading(
    string Reading,
    string ReadingType,
    string LanguageTag,
    string Meaning,
    int DisplayOrder);

public sealed record PublicContextualKanji(
    string Character,
    int CharOffset,
    string? GradeCode,
    string? JlptCode,
    IReadOnlyList<PublicContextualKanjiReading> Readings);

public sealed record PublicContextualMorphology(
    string Lemma,
    string PartOfSpeechCode,
    string? ConjugationCode);

public sealed record PublicContextualGrammar(
    string GrammarCode,
    string Title,
    string? LevelCode,
    string? Note,
    string? Explanation,
    string? Examples);

public sealed record PublicContextualProvenance(
    string SourceType,
    string Citation,
    string? Locator,
    string ContributionType);

public sealed record PublicContextualLine(
    int SectionOrder,
    string? SectionLabel,
    int LineNo,
    string JapaneseText,
    string? SpeakerLabel);

public sealed record PublicContextualAnalysis(
    bool Available,
    string TokenKey,
    string Surface,
    int TokenNo,
    string TargetLanguage,
    PublicContextualLine Line,
    IReadOnlyList<PublicContextualReading> Readings,
    IReadOnlyList<PublicContextualVocabulary> Vocabulary,
    IReadOnlyList<PublicContextualKanji> Kanji,
    IReadOnlyList<PublicContextualMorphology> Morphology,
    IReadOnlyList<PublicContextualGrammar> Grammar,
    IReadOnlyList<PublicContextualProvenance> Provenance);

public sealed class AmbiguousPublicContextualAnalysisException : Exception
{
    public AmbiguousPublicContextualAnalysisException()
        : base("El análisis contextual coincide con más de una publicación o token elegible.")
    {
    }
}

public sealed class IncompatiblePublicContextualAnalysisException : Exception
{
    public IncompatiblePublicContextualAnalysisException()
        : base("La revisión publicada de análisis no pertenece a la letra publicada seleccionada.")
    {
    }
}

public sealed class PublicContextualAnalysisService
{
    private const int PublicSongKeyLength = 20;
    private const int MaximumSlugLength = 160;
    private readonly string _connectionString;

    public PublicContextualAnalysisService(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        _connectionString = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para el análisis contextual público.");
    }

    public async Task<PublicContextualAnalysis?> ReadAsync(
        string slug,
        string tokenKey,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken = default)
    {
        var slugKey = ExtractSlugKey(slug);
        var normalizedTokenKey = PublicAnalysisTokenKey.Normalize(tokenKey);
        var normalizedTerritory = NormalizeCode(territoryCode, nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag) ?? "es";

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        var headers = await ReadEligibleHeadersAsync(
            connection,
            slugKey,
            normalizedTerritory,
            normalizedLanguage,
            cancellationToken);

        if (headers.Count == 0)
        {
            return null;
        }

        if (headers.Count > 1)
        {
            throw new AmbiguousPublicContextualAnalysisException();
        }

        var header = headers[0];
        if (header.LyricsRevisionId is not { } lyricsRevisionId
            || header.AnalysisRevisionId is not { } analysisRevisionId)
        {
            return null;
        }

        await EnsureCompatibleAsync(
            connection,
            header.RecordingId,
            lyricsRevisionId,
            analysisRevisionId,
            cancellationToken);

        var token = await ReadTargetTokenAsync(
            connection,
            lyricsRevisionId,
            normalizedTokenKey,
            cancellationToken);

        if (token is null)
        {
            return null;
        }

        var readings = await ReadReadingsAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.TokenId,
            cancellationToken);

        var vocabulary = await ReadVocabularyAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.TokenId,
            normalizedLanguage,
            cancellationToken);

        var kanji = await ReadKanjiAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.TokenId,
            normalizedLanguage,
            cancellationToken);

        var morphology = await ReadMorphologyAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.TokenId,
            cancellationToken);

        var grammar = await ReadGrammarAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.LineId,
            token.TokenNo,
            normalizedLanguage,
            cancellationToken);

        var provenance = await ReadProvenanceAsync(
            connection,
            analysisRevisionId,
            cancellationToken);

        var available = readings.Count > 0
            || vocabulary.Count > 0
            || kanji.Count > 0
            || morphology.Count > 0
            || grammar.Count > 0;

        return new PublicContextualAnalysis(
            available,
            normalizedTokenKey,
            token.Surface,
            token.TokenNo,
            normalizedLanguage,
            new PublicContextualLine(
                token.SectionOrder,
                token.SectionLabel,
                token.LineNo,
                token.JapaneseText,
                token.SpeakerLabel),
            readings,
            vocabulary,
            kanji,
            morphology,
            grammar,
            provenance);
    }

    private static async Task<List<EligibleHeader>> ReadEligibleHeadersAsync(
        NpgsqlConnection connection,
        string slugKey,
        string territoryCode,
        string languageTag,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                recording.recording_id,
                lyrics_component.lyrics_revision_id,
                analysis_component.analysis_revision_id
            FROM editorial.published_package_projection AS projection
            INNER JOIN editorial.publication AS publication
                ON publication.publication_id = projection.publication_id
               AND publication.recording_id = projection.recording_id
            INNER JOIN catalog.recording AS recording
                ON recording.recording_id = publication.recording_id
            INNER JOIN catalog.recording_source AS source
                ON source.source_id = NULLIF(
                    projection.component_versions #>> '{source,sourceId}',
                    ''
                )::uuid
               AND source.recording_id = recording.recording_id
               AND source.provider_code =
                    projection.component_versions #>> '{source,providerCode}'
               AND source.external_ref =
                    projection.component_versions #>> '{source,externalRef}'
               AND source.version = NULLIF(
                    projection.component_versions #>> '{source,version}',
                    ''
                )::bigint
            INNER JOIN LATERAL (
                SELECT
                    availability_row.territory_code,
                    availability_row.language_tag
                FROM editorial.publication_availability AS availability_row
                WHERE availability_row.publication_id = publication.publication_id
                  AND availability_row.territory_code = @territory_code
                  AND availability_row.audience_code = 'PUBLIC'
                  AND availability_row.status_code = 'ACTIVE'
                  AND availability_row.valid_from <= CURRENT_TIMESTAMP
                  AND (
                      availability_row.valid_to IS NULL
                      OR availability_row.valid_to > CURRENT_TIMESTAMP
                  )
                  AND (
                      availability_row.language_tag IS NULL
                      OR lower(availability_row.language_tag) = lower(@language_tag)
                  )
                ORDER BY
                    CASE
                        WHEN availability_row.language_tag IS NOT NULL
                             AND lower(availability_row.language_tag) = lower(@language_tag)
                        THEN 0
                        ELSE 1
                    END,
                    availability_row.valid_from DESC,
                    availability_row.availability_id
                LIMIT 1
            ) AS availability ON true
            LEFT JOIN LATERAL (
                SELECT package_component.lyrics_revision_id
                FROM editorial.publication_component AS published_component
                INNER JOIN editorial.package_component AS package_component
                    ON package_component.package_component_id =
                         published_component.source_component_id
                   AND package_component.package_id = publication.package_id
                   AND package_component.component_kind = 'LYRICS'
                WHERE published_component.publication_id = publication.publication_id
                  AND published_component.component_kind = 'LYRICS'
                  AND package_component.lyrics_revision_id IS NOT NULL
                ORDER BY
                    published_component.display_order,
                    published_component.publication_component_id
                LIMIT 1
            ) AS lyrics_component ON true
            LEFT JOIN LATERAL (
                SELECT package_component.analysis_revision_id
                FROM editorial.publication_component AS published_component
                INNER JOIN editorial.package_component AS package_component
                    ON package_component.package_component_id =
                         published_component.source_component_id
                   AND package_component.package_id = publication.package_id
                   AND package_component.component_kind = 'ANALYSIS'
                WHERE published_component.publication_id = publication.publication_id
                  AND published_component.component_kind = 'ANALYSIS'
                  AND package_component.analysis_revision_id IS NOT NULL
                ORDER BY
                    published_component.display_order,
                    published_component.publication_component_id
                LIMIT 1
            ) AS analysis_component ON true
            WHERE upper(
                      substring(
                          md5(recording.recording_id::text || ':public-song-v1')
                          from 1 for 20
                      )
                  ) = @slug_key
              AND publication.status_code = 'ACTIVE'
              AND publication.active_from <= CURRENT_TIMESTAMP
              AND (
                  publication.active_to IS NULL
                  OR publication.active_to > CURRENT_TIMESTAMP
              )
              AND source.provider_code = 'YOUTUBE'
              AND source.status_code IN ('ACTIVE', 'PUBLISHED')
              AND source.external_ref ~ '^[A-Za-z0-9_-]{11}$'
            ORDER BY publication.active_from DESC, publication.publication_no DESC
            LIMIT 2;
            """;

        var result = new List<EligibleHeader>(2);

        await using var command = new NpgsqlCommand(sql, connection)
        {
            CommandTimeout = 15
        };

        command.Parameters.AddWithValue("slug_key", NpgsqlDbType.Varchar, slugKey);
        command.Parameters.AddWithValue(
            "territory_code",
            NpgsqlDbType.Varchar,
            territoryCode);
        command.Parameters.AddWithValue(
            "language_tag",
            NpgsqlDbType.Varchar,
            languageTag);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new EligibleHeader(
                    reader.GetGuid(0),
                    reader.IsDBNull(1) ? null : reader.GetGuid(1),
                    reader.IsDBNull(2) ? null : reader.GetGuid(2)));
        }

        return result;
    }

    private static async Task EnsureCompatibleAsync(
        NpgsqlConnection connection,
        Guid recordingId,
        Guid lyricsRevisionId,
        Guid analysisRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                EXISTS (
                    SELECT 1
                    FROM content.lyrics_revision AS lyrics
                    WHERE lyrics.lyrics_revision_id = @lyrics_revision_id
                      AND lyrics.recording_id = @recording_id
                ),
                EXISTS (
                    SELECT 1
                    FROM content.linguistic_analysis_revision AS analysis
                    WHERE analysis.analysis_revision_id = @analysis_revision_id
                      AND analysis.lyrics_revision_id = @lyrics_revision_id
                );
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)
            || !reader.GetBoolean(0)
            || !reader.GetBoolean(1))
        {
            throw new IncompatiblePublicContextualAnalysisException();
        }
    }

    private static async Task<TargetToken?> ReadTargetTokenAsync(
        NpgsqlConnection connection,
        Guid lyricsRevisionId,
        string tokenKey,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                section.display_order,
                section.label,
                line.line_id,
                line.line_no,
                line.japanese_text,
                line.speaker_label,
                token.token_id,
                token.token_no,
                token.surface
            FROM content.lyric_section AS section
            INNER JOIN content.lyric_line AS line
                ON line.section_id = section.section_id
            INNER JOIN content.lyric_token AS token
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

        TargetToken? match = null;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var tokenId = reader.GetGuid(6);
            if (!string.Equals(
                    PublicAnalysisTokenKey.FromTokenId(tokenId),
                    tokenKey,
                    StringComparison.Ordinal))
            {
                continue;
            }

            if (match is not null)
            {
                throw new AmbiguousPublicContextualAnalysisException();
            }

            match = new TargetToken(
                reader.GetInt32(0),
                reader.IsDBNull(1) ? null : reader.GetString(1),
                reader.GetGuid(2),
                reader.GetInt32(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                tokenId,
                reader.GetInt32(7),
                reader.GetString(8));
        }

        return match;
    }

    private static async Task<List<PublicContextualReading>> ReadReadingsAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                reading.reading_kana,
                reading.furigana,
                reading.romaji,
                reading.reading_type
            FROM content.token_reading AS reading
            INNER JOIN content.lyric_token AS token
                ON token.token_id = reading.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            WHERE reading.analysis_revision_id = @analysis_revision_id
              AND reading.token_id = @token_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                CASE upper(reading.reading_type)
                    WHEN 'PRIMARY' THEN 0
                    WHEN 'CONTEXTUAL' THEN 1
                    ELSE 2
                END,
                reading.reading_type,
                reading.token_reading_id;
            """;

        var result = new List<PublicContextualReading>();

        await using var command = new NpgsqlCommand(sql, connection);
        AddAnalysisTokenParameters(
            command,
            analysisRevisionId,
            lyricsRevisionId,
            tokenId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new PublicContextualReading(
                    reader.GetString(0),
                    reader.IsDBNull(1) ? null : reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3)));
        }

        return result;
    }

    private static async Task<List<PublicContextualVocabulary>> ReadVocabularyAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId,
        string language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                occurrence.occurrence_id,
                entry.lemma,
                entry.reading,
                entry.part_of_speech,
                entry.sense_key,
                occurrence.inflection,
                occurrence.confidence_code,
                sense.language_tag,
                sense.definition,
                sense.usage_note,
                sense.display_order
            FROM content.vocabulary_occurrence AS occurrence
            INNER JOIN content.lyric_token AS token
                ON token.token_id = occurrence.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            INNER JOIN content.vocabulary_entry AS entry
                ON entry.vocabulary_id = occurrence.vocabulary_id
            LEFT JOIN content.vocabulary_sense AS sense
                ON sense.vocabulary_id = entry.vocabulary_id
               AND lower(sense.language_tag) = lower(@language)
            WHERE occurrence.analysis_revision_id = @analysis_revision_id
              AND occurrence.token_id = @token_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                occurrence.occurrence_id,
                sense.display_order,
                sense.sense_id;
            """;

        var builders = new Dictionary<Guid, VocabularyBuilder>();
        var order = new List<Guid>();

        await using var command = new NpgsqlCommand(sql, connection);
        AddAnalysisTokenParameters(
            command,
            analysisRevisionId,
            lyricsRevisionId,
            tokenId);
        command.Parameters.AddWithValue("language", NpgsqlDbType.Varchar, language);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var occurrenceId = reader.GetGuid(0);
            if (!builders.TryGetValue(occurrenceId, out var builder))
            {
                builder = new VocabularyBuilder(
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetString(5),
                    reader.GetString(6));
                builders.Add(occurrenceId, builder);
                order.Add(occurrenceId);
            }

            if (!reader.IsDBNull(7))
            {
                builder.Senses.Add(
                    new PublicContextualVocabularySense(
                        reader.GetString(7),
                        reader.GetString(8),
                        reader.IsDBNull(9) ? null : reader.GetString(9),
                        reader.GetInt32(10)));
            }
        }

        return order.Select(id => builders[id].Build()).ToList();
    }

    private static async Task<List<PublicContextualKanji>> ReadKanjiAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId,
        string language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                occurrence.occurrence_id,
                entry.character,
                occurrence.char_offset,
                entry.grade_code,
                entry.jlpt_code,
                reading.reading,
                reading.reading_type,
                reading.language_tag,
                reading.meaning,
                reading.display_order
            FROM content.kanji_occurrence AS occurrence
            INNER JOIN content.lyric_token AS token
                ON token.token_id = occurrence.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            INNER JOIN content.kanji_entry AS entry
                ON entry.kanji_id = occurrence.kanji_id
            LEFT JOIN content.kanji_reading AS reading
                ON reading.kanji_id = entry.kanji_id
               AND lower(reading.language_tag) = lower(@language)
            WHERE occurrence.analysis_revision_id = @analysis_revision_id
              AND occurrence.token_id = @token_id
              AND section.lyrics_revision_id = @lyrics_revision_id
              AND substring(
                    token.surface
                    FROM occurrence.char_offset + 1
                    FOR char_length(entry.character)
                  ) = entry.character
            ORDER BY
                occurrence.char_offset,
                occurrence.occurrence_id,
                reading.display_order,
                reading.kanji_reading_id;
            """;

        var builders = new Dictionary<Guid, KanjiBuilder>();
        var order = new List<Guid>();

        await using var command = new NpgsqlCommand(sql, connection);
        AddAnalysisTokenParameters(
            command,
            analysisRevisionId,
            lyricsRevisionId,
            tokenId);
        command.Parameters.AddWithValue("language", NpgsqlDbType.Varchar, language);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var occurrenceId = reader.GetGuid(0);
            if (!builders.TryGetValue(occurrenceId, out var builder))
            {
                builder = new KanjiBuilder(
                    reader.GetString(1),
                    reader.GetInt32(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4));
                builders.Add(occurrenceId, builder);
                order.Add(occurrenceId);
            }

            if (!reader.IsDBNull(5))
            {
                builder.Readings.Add(
                    new PublicContextualKanjiReading(
                        reader.GetString(5),
                        reader.GetString(6),
                        reader.GetString(7),
                        reader.GetString(8),
                        reader.GetInt32(9)));
            }
        }

        return order.Select(id => builders[id].Build()).ToList();
    }

    private static async Task<List<PublicContextualMorphology>> ReadMorphologyAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                annotation.lemma,
                annotation.pos_code,
                annotation.conjugation_code
            FROM content.morphology_annotation AS annotation
            INNER JOIN content.lyric_token AS token
                ON token.token_id = annotation.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            WHERE annotation.analysis_revision_id = @analysis_revision_id
              AND annotation.token_id = @token_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY annotation.annotation_id;
            """;

        var result = new List<PublicContextualMorphology>();

        await using var command = new NpgsqlCommand(sql, connection);
        AddAnalysisTokenParameters(
            command,
            analysisRevisionId,
            lyricsRevisionId,
            tokenId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new PublicContextualMorphology(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2)));
        }

        return result;
    }

    private static async Task<List<PublicContextualGrammar>> ReadGrammarAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid lineId,
        int tokenNo,
        string language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                point.grammar_code,
                point.title,
                point.level_code,
                occurrence.note,
                explanation.explanation,
                explanation.examples
            FROM content.grammar_occurrence AS occurrence
            INNER JOIN content.lyric_line AS line
                ON line.line_id = occurrence.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            INNER JOIN content.grammar_point AS point
                ON point.grammar_point_id = occurrence.grammar_point_id
            LEFT JOIN content.lyric_token AS start_token
                ON start_token.token_id = occurrence.start_token_id
               AND start_token.line_id = occurrence.line_id
            LEFT JOIN content.lyric_token AS end_token
                ON end_token.token_id = occurrence.end_token_id
               AND end_token.line_id = occurrence.line_id
            LEFT JOIN LATERAL (
                SELECT
                    item.explanation,
                    item.examples
                FROM content.grammar_explanation AS item
                WHERE item.grammar_point_id = point.grammar_point_id
                  AND lower(item.language_tag) = lower(@language)
                ORDER BY item.revision_no DESC, item.explanation_id DESC
                LIMIT 1
            ) AS explanation ON true
            WHERE occurrence.analysis_revision_id = @analysis_revision_id
              AND occurrence.line_id = @line_id
              AND section.lyrics_revision_id = @lyrics_revision_id
              AND (
                    occurrence.start_token_id IS NULL
                    OR start_token.token_no <= @token_no
                  )
              AND (
                    occurrence.end_token_id IS NULL
                    OR end_token.token_no >= @token_no
                  )
            ORDER BY occurrence.occurrence_id;
            """;

        var result = new List<PublicContextualGrammar>();

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue("line_id", NpgsqlDbType.Uuid, lineId);
        command.Parameters.AddWithValue("token_no", NpgsqlDbType.Integer, tokenNo);
        command.Parameters.AddWithValue("language", NpgsqlDbType.Varchar, language);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new PublicContextualGrammar(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetString(5)));
        }

        return result;
    }

    private static async Task<List<PublicContextualProvenance>> ReadProvenanceAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                source.source_type,
                source.citation,
                source.locator,
                provenance.contribution_type
            FROM editorial.provenance_record AS provenance
            INNER JOIN catalog.source_reference AS source
                ON source.source_reference_id = provenance.source_reference_id
            WHERE provenance.object_type = 'LINGUISTIC_ANALYSIS_REVISION'
              AND provenance.object_id = @analysis_revision_id
            ORDER BY
                provenance.recorded_at,
                provenance.provenance_id;
            """;

        var result = new List<PublicContextualProvenance>();

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new PublicContextualProvenance(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3)));
        }

        return result;
    }

    private static void AddAnalysisTokenParameters(
        NpgsqlCommand command,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId)
    {
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue("token_id", NpgsqlDbType.Uuid, tokenId);
    }

    private static string ExtractSlugKey(string slug)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(slug);

        var normalized = slug.Trim();
        if (normalized.Length > MaximumSlugLength)
        {
            throw new ArgumentException(
                $"El slug no puede superar {MaximumSlugLength} caracteres.",
                nameof(slug));
        }

        var separator = normalized.LastIndexOf('-');
        if (separator <= 0 || separator == normalized.Length - 1)
        {
            throw new ArgumentException(
                "El slug público no tiene el formato esperado.",
                nameof(slug));
        }

        var key = normalized[(separator + 1)..].ToUpperInvariant();
        if (key.Length != PublicSongKeyLength
            || key.Any(static character =>
                character is not (>= '0' and <= '9')
                && character is not (>= 'A' and <= 'F')))
        {
            throw new ArgumentException(
                $"La clave pública debe contener {PublicSongKeyLength} caracteres hexadecimales.",
                nameof(slug));
        }

        return key;
    }

    private static string NormalizeCode(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length is < 1 or > 64
            || !IsUpperAsciiLetterOrDigit(normalized[0]))
        {
            throw new ArgumentException(
                "El código debe usar formato [A-Z0-9][A-Z0-9._-]*.",
                parameterName);
        }

        for (var index = 1; index < normalized.Length; index++)
        {
            var character = normalized[index];
            if (!(IsUpperAsciiLetterOrDigit(character)
                  || character is '.' or '_' or '-'))
            {
                throw new ArgumentException(
                    "El código debe usar formato [A-Z0-9][A-Z0-9._-]*.",
                    parameterName);
            }
        }

        return normalized;
    }

    private static string? NormalizeLanguageTag(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = value.Trim();
        if (normalized.Length > 35)
        {
            throw new ArgumentException(
                "La etiqueta de idioma excede 35 caracteres.",
                nameof(value));
        }

        var parts = normalized.Split('-', StringSplitOptions.None);
        if (parts.Length == 0
            || parts[0].Length is < 2 or > 8
            || !parts[0].All(char.IsAsciiLetter))
        {
            throw new ArgumentException(
                "La etiqueta de idioma no cumple el formato BCP-47 mínimo esperado.",
                nameof(value));
        }

        foreach (var part in parts.Skip(1))
        {
            if (part.Length is < 1 or > 8
                || !part.All(char.IsAsciiLetterOrDigit))
            {
                throw new ArgumentException(
                    "La etiqueta de idioma no cumple el formato BCP-47 mínimo esperado.",
                    nameof(value));
            }
        }

        return normalized;
    }

    private static bool IsUpperAsciiLetterOrDigit(char character) =>
        character is >= 'A' and <= 'Z' || char.IsAsciiDigit(character);

    private sealed record EligibleHeader(
        Guid RecordingId,
        Guid? LyricsRevisionId,
        Guid? AnalysisRevisionId);

    private sealed record TargetToken(
        int SectionOrder,
        string? SectionLabel,
        Guid LineId,
        int LineNo,
        string JapaneseText,
        string? SpeakerLabel,
        Guid TokenId,
        int TokenNo,
        string Surface);

    private sealed class VocabularyBuilder(
        string lemma,
        string? reading,
        string? partOfSpeech,
        string senseKey,
        string? inflection,
        string confidenceCode)
    {
        public List<PublicContextualVocabularySense> Senses { get; } = [];

        public PublicContextualVocabulary Build() =>
            new(
                lemma,
                reading,
                partOfSpeech,
                senseKey,
                inflection,
                confidenceCode,
                Senses);
    }

    private sealed class KanjiBuilder(
        string character,
        int charOffset,
        string? gradeCode,
        string? jlptCode)
    {
        public List<PublicContextualKanjiReading> Readings { get; } = [];

        public PublicContextualKanji Build() =>
            new(
                character,
                charOffset,
                gradeCode,
                jlptCode,
                Readings);
    }
}
