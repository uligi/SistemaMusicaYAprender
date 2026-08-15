using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

public sealed record PublicLearningReading(
    string ReadingKana,
    string? Furigana,
    string? Romaji,
    string ReadingType);

public sealed record PublicLearningToken(
    int TokenNo,
    string Surface,
    int StartOffset,
    int EndOffset,
    IReadOnlyList<PublicLearningReading> Readings);

public sealed record PublicLearningTranslation(
    string VariantCode,
    string TranslatedText,
    int DisplayOrder);

public sealed record PublicLearningLine(
    int SectionOrder,
    string? SectionLabel,
    int LineNo,
    string JapaneseText,
    string? SpeakerLabel,
    IReadOnlyList<PublicLearningToken> Tokens,
    IReadOnlyList<PublicLearningTranslation> Translations);

public sealed record PublicSongLearningLayers(
    bool Available,
    string TargetLanguage,
    bool HasFurigana,
    bool HasRomaji,
    bool HasSpanish,
    IReadOnlyList<PublicLearningLine> Lines);

public sealed class AmbiguousPublicLearningLayersException : Exception
{
    public AmbiguousPublicLearningLayersException()
        : base("Las capas educativas coinciden con más de una publicación elegible.")
    {
    }
}

public sealed class IncompatiblePublicLearningLayersException : Exception
{
    public IncompatiblePublicLearningLayersException()
        : base("Las revisiones publicadas de letra, traducción o análisis no son compatibles.")
    {
    }
}

public sealed class PublicSongLearningLayersService
{
    private const int PublicKeyLength = 20;
    private const int MaximumSlugLength = 160;
    private readonly string _connectionString;

    public PublicSongLearningLayersService(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        _connectionString = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para las capas educativas públicas.");
    }

    public async Task<PublicSongLearningLayers?> ReadAsync(
        string slug,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken = default)
    {
        var slugKey = ExtractSlugKey(slug);
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
            throw new AmbiguousPublicLearningLayersException();
        }

        var header = headers[0];

        if (header.LyricsRevisionId is not { } lyricsRevisionId)
        {
            return Empty(normalizedLanguage);
        }

        await EnsureCompatibleAsync(
            connection,
            header.RecordingId,
            lyricsRevisionId,
            header.TranslationRevisionId,
            header.AnalysisRevisionId,
            cancellationToken);

        var lines = await ReadLinesAsync(
            connection,
            lyricsRevisionId,
            cancellationToken);

        if (lines.Count == 0)
        {
            return Empty(normalizedLanguage);
        }

        var translations = header.TranslationRevisionId is { } translationRevisionId
            ? await ReadTranslationsAsync(
                connection,
                translationRevisionId,
                lyricsRevisionId,
                normalizedLanguage,
                cancellationToken)
            : [];

        var readings = header.AnalysisRevisionId is { } analysisRevisionId
            ? await ReadReadingsAsync(
                connection,
                analysisRevisionId,
                lyricsRevisionId,
                cancellationToken)
            : [];

        var translationsByLine = translations
            .GroupBy(static item => item.LineId)
            .ToDictionary(
                static group => group.Key,
                static group => (IReadOnlyList<PublicLearningTranslation>)group
                    .OrderBy(static item => item.DisplayOrder)
                    .ThenBy(static item => item.VariantCode, StringComparer.Ordinal)
                    .Select(static item => new PublicLearningTranslation(
                        item.VariantCode,
                        item.TranslatedText,
                        item.DisplayOrder))
                    .ToList());

        var readingsByToken = readings
            .GroupBy(static item => item.TokenId)
            .ToDictionary(
                static group => group.Key,
                static group => (IReadOnlyList<PublicLearningReading>)group
                    .OrderBy(static item => ReadingRank(item.ReadingType))
                    .ThenBy(static item => item.ReadingType, StringComparer.Ordinal)
                    .ThenBy(static item => item.TokenReadingId)
                    .Select(static item => new PublicLearningReading(
                        item.ReadingKana,
                        item.Furigana,
                        item.Romaji,
                        item.ReadingType))
                    .ToList());

        var publicLines = lines
            .Select(line => new PublicLearningLine(
                line.SectionOrder,
                line.SectionLabel,
                line.LineNo,
                line.JapaneseText,
                line.SpeakerLabel,
                line.Tokens
                    .OrderBy(static token => token.TokenNo)
                    .Select(token => new PublicLearningToken(
                        token.TokenNo,
                        token.Surface,
                        token.StartOffset,
                        token.EndOffset,
                        readingsByToken.TryGetValue(token.TokenId, out var tokenReadings)
                            ? tokenReadings
                            : Array.Empty<PublicLearningReading>()))
                    .ToList(),
                translationsByLine.TryGetValue(line.LineId, out var lineTranslations)
                    ? lineTranslations
                    : Array.Empty<PublicLearningTranslation>()))
            .ToList();

        var hasReadings = readings.Count > 0;
        var hasSpanish = translations.Count > 0;

        return new PublicSongLearningLayers(
            true,
            normalizedLanguage,
            hasReadings,
            hasReadings,
            hasSpanish,
            publicLines);
    }

    private static PublicSongLearningLayers Empty(string targetLanguage) =>
        new(
            false,
            targetLanguage,
            false,
            false,
            false,
            Array.Empty<PublicLearningLine>());

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
                translation_component.translation_revision_id,
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
                SELECT package_component.translation_revision_id
                FROM editorial.publication_component AS published_component
                INNER JOIN editorial.package_component AS package_component
                    ON package_component.package_component_id =
                         published_component.source_component_id
                   AND package_component.package_id = publication.package_id
                   AND package_component.component_kind = 'TRANSLATION'
                WHERE published_component.publication_id = publication.publication_id
                  AND published_component.component_kind = 'TRANSLATION'
                  AND package_component.translation_revision_id IS NOT NULL
                ORDER BY
                    published_component.display_order,
                    published_component.publication_component_id
                LIMIT 1
            ) AS translation_component ON true
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
                    reader.IsDBNull(2) ? null : reader.GetGuid(2),
                    reader.IsDBNull(3) ? null : reader.GetGuid(3)));
        }

        return result;
    }

    private static async Task EnsureCompatibleAsync(
        NpgsqlConnection connection,
        Guid recordingId,
        Guid lyricsRevisionId,
        Guid? translationRevisionId,
        Guid? analysisRevisionId,
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
                @translation_revision_id IS NULL OR EXISTS (
                    SELECT 1
                    FROM content.translation_revision AS translation
                    WHERE translation.translation_revision_id = @translation_revision_id
                      AND translation.lyrics_revision_id = @lyrics_revision_id
                ),
                @analysis_revision_id IS NULL OR EXISTS (
                    SELECT 1
                    FROM content.linguistic_analysis_revision AS analysis
                    WHERE analysis.analysis_revision_id = @analysis_revision_id
                      AND analysis.lyrics_revision_id = @lyrics_revision_id
                );
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.Add(
            new NpgsqlParameter("translation_revision_id", NpgsqlDbType.Uuid)
            {
                Value = translationRevisionId is { } translationId
                    ? translationId
                    : DBNull.Value
            });
        command.Parameters.Add(
            new NpgsqlParameter("analysis_revision_id", NpgsqlDbType.Uuid)
            {
                Value = analysisRevisionId is { } analysisId
                    ? analysisId
                    : DBNull.Value
            });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)
            || !reader.GetBoolean(0)
            || !reader.GetBoolean(1)
            || !reader.GetBoolean(2))
        {
            throw new IncompatiblePublicLearningLayersException();
        }
    }

    private static async Task<List<LineRow>> ReadLinesAsync(
        NpgsqlConnection connection,
        Guid lyricsRevisionId,
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
                token.surface,
                token.start_offset,
                token.end_offset
            FROM content.lyric_section AS section
            INNER JOIN content.lyric_line AS line
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

        var builders = new Dictionary<Guid, LineBuilder>();
        var order = new List<Guid>();

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var lineId = reader.GetGuid(2);

            if (!builders.TryGetValue(lineId, out var builder))
            {
                builder = new LineBuilder(
                    reader.GetInt32(0),
                    reader.IsDBNull(1) ? null : reader.GetString(1),
                    lineId,
                    reader.GetInt32(3),
                    reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetString(5));
                builders.Add(lineId, builder);
                order.Add(lineId);
            }

            if (!reader.IsDBNull(6))
            {
                builder.Tokens.Add(
                    new TokenRow(
                        reader.GetGuid(6),
                        reader.GetInt32(7),
                        reader.GetString(8),
                        reader.GetInt32(9),
                        reader.GetInt32(10)));
            }
        }

        return order.Select(lineId => builders[lineId].Build()).ToList();
    }

    private static async Task<List<TranslationRow>> ReadTranslationsAsync(
        NpgsqlConnection connection,
        Guid translationRevisionId,
        Guid lyricsRevisionId,
        string targetLanguage,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                translated.line_id,
                translated.variant_code,
                translated.translated_text,
                translated.display_order
            FROM content.translation_revision AS revision
            INNER JOIN content.translation_line AS translated
                ON translated.translation_revision_id =
                     revision.translation_revision_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = translated.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
               AND section.lyrics_revision_id = @lyrics_revision_id
            WHERE revision.translation_revision_id = @translation_revision_id
              AND revision.lyrics_revision_id = @lyrics_revision_id
              AND lower(revision.target_language) = lower(@target_language)
            ORDER BY
                translated.display_order,
                translated.translation_line_id;
            """;

        var result = new List<TranslationRow>();

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "translation_revision_id",
            NpgsqlDbType.Uuid,
            translationRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue(
            "target_language",
            NpgsqlDbType.Varchar,
            targetLanguage);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new TranslationRow(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetInt32(3)));
        }

        return result;
    }

    private static async Task<List<ReadingRow>> ReadReadingsAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                reading.token_reading_id,
                reading.token_id,
                reading.reading_kana,
                reading.furigana,
                reading.romaji,
                reading.reading_type
            FROM content.linguistic_analysis_revision AS analysis
            INNER JOIN content.token_reading AS reading
                ON reading.analysis_revision_id = analysis.analysis_revision_id
            INNER JOIN content.lyric_token AS token
                ON token.token_id = reading.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
               AND section.lyrics_revision_id = @lyrics_revision_id
            WHERE analysis.analysis_revision_id = @analysis_revision_id
              AND analysis.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                section.display_order,
                section.section_id,
                line.line_no,
                line.line_id,
                token.token_no,
                token.token_id,
                CASE upper(reading.reading_type)
                    WHEN 'PRIMARY' THEN 0
                    WHEN 'CONTEXTUAL' THEN 1
                    ELSE 2
                END,
                reading.reading_type,
                reading.token_reading_id;
            """;

        var result = new List<ReadingRow>();

        await using var command = new NpgsqlCommand(sql, connection);
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
                new ReadingRow(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetString(5)));
        }

        return result;
    }

    private static int ReadingRank(string readingType)
    {
        if (string.Equals(readingType, "PRIMARY", StringComparison.OrdinalIgnoreCase))
        {
            return 0;
        }

        return string.Equals(readingType, "CONTEXTUAL", StringComparison.OrdinalIgnoreCase)
            ? 1
            : 2;
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
        if (key.Length != PublicKeyLength
            || key.Any(static character =>
                character is not (>= '0' and <= '9')
                && character is not (>= 'A' and <= 'F')))
        {
            throw new ArgumentException(
                $"La clave pública debe contener {PublicKeyLength} caracteres hexadecimales.",
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
        Guid? TranslationRevisionId,
        Guid? AnalysisRevisionId);

    private sealed record TokenRow(
        Guid TokenId,
        int TokenNo,
        string Surface,
        int StartOffset,
        int EndOffset);

    private sealed record LineRow(
        int SectionOrder,
        string? SectionLabel,
        Guid LineId,
        int LineNo,
        string JapaneseText,
        string? SpeakerLabel,
        IReadOnlyList<TokenRow> Tokens);

    private sealed record TranslationRow(
        Guid LineId,
        string VariantCode,
        string TranslatedText,
        int DisplayOrder);

    private sealed record ReadingRow(
        Guid TokenReadingId,
        Guid TokenId,
        string ReadingKana,
        string? Furigana,
        string? Romaji,
        string ReadingType);

    private sealed class LineBuilder(
        int sectionOrder,
        string? sectionLabel,
        Guid lineId,
        int lineNo,
        string japaneseText,
        string? speakerLabel)
    {
        public List<TokenRow> Tokens { get; } = [];

        public LineRow Build() =>
            new(
                sectionOrder,
                sectionLabel,
                lineId,
                lineNo,
                japaneseText,
                speakerLabel,
                Tokens);
    }
}
