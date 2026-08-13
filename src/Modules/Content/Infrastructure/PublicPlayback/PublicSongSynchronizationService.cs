using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

public sealed record PublicSynchronizationToken(
    int TokenNo,
    string Surface,
    long StartMs,
    long EndMs);

public sealed record PublicSynchronizationLine(
    int SectionOrder,
    int LineNo,
    string JapaneseText,
    string? SpeakerLabel,
    string PrecisionCode,
    long StartMs,
    long EndMs,
    IReadOnlyList<PublicSynchronizationToken> Tokens);

public sealed record PublicSongSynchronization(
    bool Available,
    string MaximumPrecision,
    long OffsetMs,
    IReadOnlyList<PublicSynchronizationLine> Lines);

public sealed class AmbiguousPublicSynchronizationException : Exception
{
    public AmbiguousPublicSynchronizationException()
        : base("La sincronización pública coincide con más de una publicación elegible.")
    {
    }
}

public sealed class IncompatiblePublicSynchronizationException : Exception
{
    public IncompatiblePublicSynchronizationException()
        : base("La publicación referencia una sincronización que no coincide con su fuente o revisión de letra.")
    {
    }
}

public sealed class PublicSongSynchronizationService
{
    private const int PublicKeyLength = 20;
    private const int MaximumSlugLength = 160;
    private readonly string _connectionString;

    public PublicSongSynchronizationService(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        _connectionString = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para la sincronización pública.");
    }

    public async Task<PublicSongSynchronization?> ReadAsync(
        string slug,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken = default)
    {
        var slugKey = ExtractSlugKey(slug);
        var normalizedTerritory = NormalizeCode(territoryCode, nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag);

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
            throw new AmbiguousPublicSynchronizationException();
        }

        var header = headers[0];

        if (header.ComponentTimingRevisionId is null)
        {
            return Empty();
        }

        if (header.LyricsRevisionId is null || header.OffsetMs is null)
        {
            throw new IncompatiblePublicSynchronizationException();
        }

        var lines = await ReadLinesAsync(
            connection,
            header.ComponentTimingRevisionId.Value,
            header.LyricsRevisionId.Value,
            cancellationToken);

        if (lines.Count == 0)
        {
            return Empty();
        }

        var maximumPrecision = lines.Any(
            static line => string.Equals(
                line.PrecisionCode,
                "TOKEN",
                StringComparison.Ordinal))
            ? "TOKEN"
            : "LINE";

        return new PublicSongSynchronization(
            true,
            maximumPrecision,
            header.OffsetMs.Value,
            lines);
    }

    private static PublicSongSynchronization Empty()
    {
        return new PublicSongSynchronization(
            false,
            "NONE",
            0,
            Array.Empty<PublicSynchronizationLine>());
    }

    private static async Task<List<EligibleHeader>> ReadEligibleHeadersAsync(
        NpgsqlConnection connection,
        string slugKey,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                timing_component.timing_revision_id,
                timing.lyrics_revision_id,
                timing.offset_ms
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
                    availability_row.language_tag,
                    availability_row.valid_from,
                    availability_row.valid_to
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
                      (@language_tag IS NULL AND availability_row.language_tag IS NULL)
                      OR (
                          @language_tag IS NOT NULL
                          AND (
                              availability_row.language_tag IS NULL
                              OR lower(availability_row.language_tag) = lower(@language_tag)
                          )
                      )
                  )
                ORDER BY
                    CASE
                        WHEN @language_tag IS NOT NULL
                             AND availability_row.language_tag IS NOT NULL
                             AND lower(availability_row.language_tag) = lower(@language_tag)
                        THEN 0
                        ELSE 1
                    END,
                    availability_row.valid_from DESC,
                    availability_row.availability_id
                LIMIT 1
            ) AS availability ON true
            LEFT JOIN LATERAL (
                SELECT
                    package_component.timing_revision_id
                FROM jsonb_array_elements(
                    COALESCE(
                        projection.component_versions -> 'components',
                        '[]'::jsonb
                    )
                ) AS component
                INNER JOIN editorial.publication_component AS published_component
                    ON published_component.publication_id = publication.publication_id
                   AND published_component.component_kind = 'TIMING'
                   AND published_component.source_component_id =
                        CASE
                            WHEN COALESCE(component ->> 'sourceComponentId', '') ~
                                 '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-8][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$'
                            THEN (component ->> 'sourceComponentId')::uuid
                            ELSE NULL
                        END
                INNER JOIN editorial.package_component AS package_component
                    ON package_component.package_component_id =
                         published_component.source_component_id
                   AND package_component.package_id = publication.package_id
                   AND package_component.component_kind = 'TIMING'
                   AND package_component.timing_revision_id IS NOT NULL
                WHERE component ->> 'kind' = 'TIMING'
                ORDER BY
                    CASE
                        WHEN COALESCE(component ->> 'displayOrder', '') ~ '^[0-9]+$'
                        THEN (component ->> 'displayOrder')::integer
                        ELSE 2147483647
                    END,
                    component ->> 'sourceComponentId'
                LIMIT 1
            ) AS timing_component ON true
            LEFT JOIN content.timing_revision AS timing
                ON timing.timing_revision_id = timing_component.timing_revision_id
               AND timing.source_id = source.source_id
               AND EXISTS (
                    SELECT 1
                    FROM jsonb_array_elements(
                        COALESCE(
                            projection.component_versions -> 'components',
                            '[]'::jsonb
                        )
                    ) AS lyrics_component
                    INNER JOIN editorial.publication_component AS published_lyrics_component
                        ON published_lyrics_component.publication_id = publication.publication_id
                       AND published_lyrics_component.component_kind = 'LYRICS'
                       AND published_lyrics_component.source_component_id =
                            CASE
                                WHEN COALESCE(lyrics_component ->> 'sourceComponentId', '') ~
                                     '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-8][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$'
                                THEN (lyrics_component ->> 'sourceComponentId')::uuid
                                ELSE NULL
                            END
                    INNER JOIN editorial.package_component AS lyrics_package_component
                        ON lyrics_package_component.package_component_id =
                             published_lyrics_component.source_component_id
                       AND lyrics_package_component.package_id = publication.package_id
                       AND lyrics_package_component.component_kind = 'LYRICS'
                       AND lyrics_package_component.lyrics_revision_id IS NOT NULL
                    WHERE lyrics_component ->> 'kind' = 'LYRICS'
                      AND lyrics_package_component.lyrics_revision_id =
                          timing.lyrics_revision_id
               )
            WHERE substring(
                      md5(recording.recording_id::text || ':public-song-v1')
                      from 1 for 20
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

        var headers = new List<EligibleHeader>(2);

        await using var command = new NpgsqlCommand(sql, connection)
        {
            CommandTimeout = 15
        };

        command.Parameters.AddWithValue("slug_key", NpgsqlDbType.Varchar, slugKey);
        command.Parameters.AddWithValue(
            "territory_code",
            NpgsqlDbType.Varchar,
            territoryCode);
        command.Parameters.Add(
            new NpgsqlParameter("language_tag", NpgsqlDbType.Varchar)
            {
                Value = languageTag is null ? DBNull.Value : languageTag
            });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            headers.Add(
                new EligibleHeader(
                    reader.IsDBNull(0) ? null : reader.GetGuid(0),
                    reader.IsDBNull(1) ? null : reader.GetGuid(1),
                    reader.IsDBNull(2) ? null : reader.GetInt64(2)));
        }

        return headers;
    }

    private static async Task<List<PublicSynchronizationLine>> ReadLinesAsync(
        NpgsqlConnection connection,
        Guid timingRevisionId,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string segmentSql = """
            SELECT
                section.display_order,
                line.line_id,
                line.line_no,
                line.japanese_text,
                line.speaker_label,
                segment.start_ms,
                segment.end_ms,
                segment.display_order
            FROM content.timing_segment AS segment
            INNER JOIN content.lyric_line AS line
                ON line.line_id = segment.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
               AND section.lyrics_revision_id = @lyrics_revision_id
            WHERE segment.timing_revision_id = @timing_revision_id
            ORDER BY
                segment.display_order,
                segment.segment_id;
            """;

        var segments = new List<SegmentRow>();

        await using (var command = new NpgsqlCommand(segmentSql, connection))
        {
            command.Parameters.AddWithValue(
                "lyrics_revision_id",
                NpgsqlDbType.Uuid,
                lyricsRevisionId);
            command.Parameters.AddWithValue(
                "timing_revision_id",
                NpgsqlDbType.Uuid,
                timingRevisionId);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                segments.Add(
                    new SegmentRow(
                        reader.GetInt32(0),
                        reader.GetGuid(1),
                        reader.GetInt32(2),
                        reader.GetString(3),
                        reader.IsDBNull(4) ? null : reader.GetString(4),
                        reader.GetInt64(5),
                        reader.GetInt64(6),
                        reader.GetInt32(7)));
            }
        }

        if (segments.Count == 0)
        {
            return [];
        }

        const string tokenSql = """
            SELECT
                token.line_id,
                token.token_no,
                token.surface
            FROM content.lyric_token AS token
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            WHERE section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                section.display_order,
                line.line_no,
                line.line_id,
                token.token_no,
                token.token_id;
            """;

        var tokenRows = new List<TokenRow>();

        await using (var command = new NpgsqlCommand(tokenSql, connection))
        {
            command.Parameters.AddWithValue(
                "lyrics_revision_id",
                NpgsqlDbType.Uuid,
                lyricsRevisionId);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                tokenRows.Add(
                    new TokenRow(
                        reader.GetGuid(0),
                        reader.GetInt32(1),
                        reader.GetString(2)));
            }
        }

        var result = new List<PublicSynchronizationLine>();

        foreach (var lineGroup in segments
                     .GroupBy(static segment => segment.LineId)
                     .OrderBy(static group => group.First().SectionOrder)
                     .ThenBy(static group => group.First().LineNo)
                     .ThenBy(static group => group.Key))
        {
            var orderedSegments = lineGroup
                .OrderBy(static segment => segment.DisplayOrder)
                .ToList();

            var first = orderedSegments[0];
            var tokens = tokenRows
                .Where(token => token.LineId == lineGroup.Key)
                .OrderBy(static token => token.TokenNo)
                .ToList();

            var tokenPrecision =
                tokens.Count > 1
                && orderedSegments.Count == tokens.Count;

            var publicTokens = new List<PublicSynchronizationToken>();

            if (tokenPrecision)
            {
                for (var index = 0; index < tokens.Count; index++)
                {
                    var token = tokens[index];
                    var segment = orderedSegments[index];

                    publicTokens.Add(
                        new PublicSynchronizationToken(
                            token.TokenNo,
                            token.Surface,
                            segment.StartMs,
                            segment.EndMs));
                }
            }

            result.Add(
                new PublicSynchronizationLine(
                    first.SectionOrder,
                    first.LineNo,
                    first.JapaneseText,
                    first.SpeakerLabel,
                    tokenPrecision ? "TOKEN" : "LINE",
                    orderedSegments.Min(static segment => segment.StartMs),
                    orderedSegments.Max(static segment => segment.EndMs),
                    publicTokens));
        }

        return result;
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

        var key = normalized[(separator + 1)..].ToLowerInvariant();
        if (key.Length != PublicKeyLength
            || key.Any(static character =>
                character is not (>= '0' and <= '9')
                && character is not (>= 'a' and <= 'f')))
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

    private static bool IsUpperAsciiLetterOrDigit(char character)
    {
        return character is >= 'A' and <= 'Z'
            || char.IsAsciiDigit(character);
    }

    private sealed record EligibleHeader(
        Guid? ComponentTimingRevisionId,
        Guid? LyricsRevisionId,
        long? OffsetMs);

    private sealed record SegmentRow(
        int SectionOrder,
        Guid LineId,
        int LineNo,
        string JapaneseText,
        string? SpeakerLabel,
        long StartMs,
        long EndMs,
        int DisplayOrder);

    private sealed record TokenRow(
        Guid LineId,
        int TokenNo,
        string Surface);
}
