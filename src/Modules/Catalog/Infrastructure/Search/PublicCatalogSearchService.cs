using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Search;

public sealed record PublicCatalogSearchIndexRebuildResult(
    long EligibleDocuments,
    long InsertedOrUpdated,
    long Removed);

public sealed record PublicCatalogSearchItem(
    string Slug,
    string CanonicalTitle,
    string? RecordingTitle,
    string ArtistName,
    string ProviderCode,
    string TerritoryCode,
    string? LanguageTag,
    DateTime IndexedAt);

public sealed record PublicCatalogSearchPage(
    IReadOnlyList<PublicCatalogSearchItem> Items,
    string? NextCursor,
    int PageSize,
    bool HasMore);

public sealed class PublicCatalogSearchService
{
    private const int DefaultPageSize = 20;
    private const int MaximumPageSize = 50;
    private const int MaximumQueryLength = 256;
    private const int MaximumCursorLength = 2048;

    private readonly string _connectionString;

    public PublicCatalogSearchService(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        _connectionString = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para la busqueda publica.");
    }

    public async Task<PublicCatalogSearchIndexRebuildResult> RebuildIndexAsync(
        CancellationToken cancellationToken = default)
    {
        const string sql = """
            WITH eligible AS (
                SELECT
                    projection.publication_id,
                    projection.recording_id,
                    projection.projection_version AS eligibility_version,
                    lower(
                        pg_catalog.regexp_replace(
                            pg_catalog.string_agg(
                                DISTINCT term.term,
                                ' ' ORDER BY term.term
                            ),
                            '\s+',
                            ' ',
                            'g'
                        )
                    ) AS normalized_terms
                FROM editorial.published_package_projection AS projection
                INNER JOIN catalog.recording AS recording
                    ON recording.recording_id = projection.recording_id
                INNER JOIN catalog.musical_work AS work
                    ON work.work_id = recording.work_id
                CROSS JOIN LATERAL (
                    SELECT work.canonical_title AS term
                    UNION ALL
                    SELECT recording.recording_title
                    WHERE recording.recording_title IS NOT NULL
                    UNION ALL
                    SELECT title.title_text
                    FROM catalog.work_title AS title
                    WHERE title.work_id = work.work_id
                    UNION ALL
                    SELECT title.normalized_text
                    FROM catalog.work_title AS title
                    WHERE title.work_id = work.work_id
                    UNION ALL
                    SELECT artist.canonical_name
                    FROM catalog.work_artist AS work_artist
                    INNER JOIN catalog.artist AS artist
                        ON artist.artist_id = work_artist.artist_id
                    WHERE work_artist.work_id = work.work_id
                      AND artist.status_code = 'ACTIVE'
                    UNION ALL
                    SELECT alias.alias_text
                    FROM catalog.work_artist AS work_artist
                    INNER JOIN catalog.artist AS artist
                        ON artist.artist_id = work_artist.artist_id
                    INNER JOIN catalog.artist_alias AS alias
                        ON alias.artist_id = artist.artist_id
                    WHERE work_artist.work_id = work.work_id
                      AND artist.status_code = 'ACTIVE'
                    UNION ALL
                    SELECT alias.normalized_text
                    FROM catalog.work_artist AS work_artist
                    INNER JOIN catalog.artist AS artist
                        ON artist.artist_id = work_artist.artist_id
                    INNER JOIN catalog.artist_alias AS alias
                        ON alias.artist_id = artist.artist_id
                    WHERE work_artist.work_id = work.work_id
                      AND artist.status_code = 'ACTIVE'
                    UNION ALL
                    SELECT credit.display_name
                    FROM catalog.recording_credit AS credit
                    WHERE credit.recording_id = recording.recording_id
                      AND credit.display_name IS NOT NULL
                ) AS term
                WHERE pg_catalog.btrim(term.term) <> ''
                GROUP BY
                    projection.publication_id,
                    projection.recording_id,
                    projection.projection_version
            ),
            upserted AS (
                INSERT INTO catalog.song_search_document (
                    recording_id,
                    publication_id,
                    normalized_terms,
                    eligibility_version,
                    indexed_at
                )
                SELECT
                    eligible.recording_id,
                    eligible.publication_id,
                    eligible.normalized_terms,
                    eligible.eligibility_version,
                    CURRENT_TIMESTAMP
                FROM eligible
                ON CONFLICT (recording_id) DO UPDATE
                SET publication_id = EXCLUDED.publication_id,
                    normalized_terms = EXCLUDED.normalized_terms,
                    eligibility_version = EXCLUDED.eligibility_version,
                    indexed_at = EXCLUDED.indexed_at
                WHERE catalog.song_search_document.publication_id
                          IS DISTINCT FROM EXCLUDED.publication_id
                   OR catalog.song_search_document.normalized_terms
                          IS DISTINCT FROM EXCLUDED.normalized_terms
                   OR catalog.song_search_document.eligibility_version
                          IS DISTINCT FROM EXCLUDED.eligibility_version
                RETURNING recording_id
            ),
            removed AS (
                DELETE FROM catalog.song_search_document AS document
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM eligible
                    WHERE eligible.recording_id = document.recording_id
                      AND eligible.publication_id = document.publication_id
                )
                RETURNING recording_id
            )
            SELECT
                (SELECT count(*) FROM eligible),
                (SELECT count(*) FROM upserted),
                (SELECT count(*) FROM removed);
            """;

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        await AcquireSearchIndexLockAsync(
            connection,
            transaction,
            cancellationToken);

        await using var command = new NpgsqlCommand(sql, connection, transaction)
        {
            CommandTimeout = 30
        };

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "La reconstruccion del indice publico no devolvio su resumen.");
        }

        var result = new PublicCatalogSearchIndexRebuildResult(
            reader.GetInt64(0),
            reader.GetInt64(1),
            reader.GetInt64(2));

        await reader.DisposeAsync();
        await transaction.CommitAsync(cancellationToken);

        return result;
    }

    public async Task<PublicCatalogSearchPage> SearchAsync(
        string? query,
        string territoryCode,
        string? languageTag,
        int? pageSize,
        string? cursor,
        CancellationToken cancellationToken = default)
    {
        var normalizedQuery = NormalizeQuery(query);
        var normalizedTerritory = NormalizeCode(
            territoryCode,
            nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag);
        var normalizedPageSize = NormalizePageSize(pageSize);
        var decodedCursor = DecodeCursor(
            cursor,
            normalizedQuery,
            normalizedTerritory,
            normalizedLanguage);

        const string sql = """
            WITH candidates AS (
                SELECT
                    document.publication_id,
                    document.recording_id,
                    work.work_id,
                    work.canonical_title,
                    recording.recording_title,
                    primary_artist.artist_id,
                    primary_artist.canonical_name AS artist_name,
                    source.provider_code,
                    source.external_ref,
                    availability.territory_code,
                    availability.language_tag,
                    document.indexed_at,
                    substring(
                        md5(recording.recording_id::text || ':public-song-v1')
                        from 1 for 20
                    ) AS slug_key,
                    CASE
                        WHEN @query = '' THEN 0
                        WHEN lower(work.canonical_title) = @query THEN 0
                        WHEN lower(primary_artist.canonical_name) = @query THEN 0
                        WHEN left(
                            lower(work.canonical_title),
                            length(@query)
                        ) = @query THEN 1
                        WHEN left(
                            lower(primary_artist.canonical_name),
                            length(@query)
                        ) = @query THEN 1
                        WHEN document.search_vector
                             @@ plainto_tsquery('simple'::regconfig, @query)
                        THEN 2
                        ELSE 3
                    END AS match_priority,
                    lower(work.canonical_title) AS sort_title,
                    lower(primary_artist.canonical_name) AS sort_artist,
                    lower(
                        COALESCE(recording.recording_title, '')
                    ) AS sort_recording
                FROM catalog.song_search_document AS document
                INNER JOIN editorial.published_package_projection AS projection
                    ON projection.publication_id = document.publication_id
                   AND projection.recording_id = document.recording_id
                   AND projection.projection_version =
                       document.eligibility_version
                INNER JOIN editorial.publication AS publication
                    ON publication.publication_id = projection.publication_id
                   AND publication.recording_id = projection.recording_id
                INNER JOIN catalog.recording AS recording
                    ON recording.recording_id = projection.recording_id
                INNER JOIN catalog.musical_work AS work
                    ON work.work_id = recording.work_id
                INNER JOIN LATERAL (
                    SELECT
                        work_artist.artist_id,
                        artist.canonical_name
                    FROM catalog.work_artist AS work_artist
                    INNER JOIN catalog.artist AS artist
                        ON artist.artist_id = work_artist.artist_id
                    WHERE work_artist.work_id = work.work_id
                      AND work_artist.role_code = 'PRIMARY'
                      AND artist.status_code = 'ACTIVE'
                    ORDER BY
                        work_artist.display_order,
                        work_artist.artist_id
                    LIMIT 1
                ) AS primary_artist ON true
                INNER JOIN catalog.recording_source AS source
                    ON source.source_id = NULLIF(
                        projection.component_versions
                            #>> '{source,sourceId}',
                        ''
                    )::uuid
                   AND source.recording_id = recording.recording_id
                   AND source.provider_code =
                       projection.component_versions
                           #>> '{source,providerCode}'
                   AND source.external_ref =
                       projection.component_versions
                           #>> '{source,externalRef}'
                   AND source.version = NULLIF(
                        projection.component_versions
                            #>> '{source,version}',
                        ''
                    )::bigint
                INNER JOIN LATERAL (
                    SELECT
                        availability_row.territory_code,
                        availability_row.language_tag
                    FROM editorial.publication_availability
                        AS availability_row
                    WHERE availability_row.publication_id =
                          publication.publication_id
                      AND availability_row.territory_code = @territory_code
                      AND availability_row.audience_code = 'PUBLIC'
                      AND availability_row.status_code = 'ACTIVE'
                      AND availability_row.valid_from <= CURRENT_TIMESTAMP
                      AND (
                          availability_row.valid_to IS NULL
                          OR availability_row.valid_to > CURRENT_TIMESTAMP
                      )
                      AND (
                          (
                              @language_tag IS NULL
                              AND availability_row.language_tag IS NULL
                          )
                          OR (
                              @language_tag IS NOT NULL
                              AND (
                                  availability_row.language_tag IS NULL
                                  OR lower(availability_row.language_tag) =
                                      lower(@language_tag)
                              )
                          )
                      )
                    ORDER BY
                        CASE
                            WHEN @language_tag IS NOT NULL
                                 AND availability_row.language_tag IS NOT NULL
                                 AND lower(availability_row.language_tag) =
                                     lower(@language_tag)
                            THEN 0
                            ELSE 1
                        END,
                        availability_row.valid_from DESC,
                        availability_row.availability_id
                    LIMIT 1
                ) AS availability ON true
                WHERE publication.status_code = 'ACTIVE'
                  AND publication.active_from <= CURRENT_TIMESTAMP
                  AND (
                      publication.active_to IS NULL
                      OR publication.active_to > CURRENT_TIMESTAMP
                  )
                  AND source.provider_code = 'YOUTUBE'
                  AND source.status_code IN ('ACTIVE', 'PUBLISHED')
                  AND source.external_ref ~ '^[A-Za-z0-9_-]{11}$'
                  AND (
                      @query = ''
                      OR document.search_vector
                         @@ plainto_tsquery('simple'::regconfig, @query)
                      OR document.normalized_terms % @query
                      OR position(@query in document.normalized_terms) > 0
                  )
            )
            SELECT
                publication_id,
                recording_id,
                work_id,
                canonical_title,
                recording_title,
                artist_id,
                artist_name,
                provider_code,
                external_ref,
                territory_code,
                language_tag,
                indexed_at,
                slug_key,
                match_priority,
                sort_title,
                sort_artist,
                sort_recording
            FROM candidates
            WHERE
                @cursor_priority IS NULL
                OR match_priority > @cursor_priority
                OR (
                    match_priority = @cursor_priority
                    AND sort_title > @cursor_title
                )
                OR (
                    match_priority = @cursor_priority
                    AND sort_title = @cursor_title
                    AND sort_artist > @cursor_artist
                )
                OR (
                    match_priority = @cursor_priority
                    AND sort_title = @cursor_title
                    AND sort_artist = @cursor_artist
                    AND sort_recording > @cursor_recording
                )
                OR (
                    match_priority = @cursor_priority
                    AND sort_title = @cursor_title
                    AND sort_artist = @cursor_artist
                    AND sort_recording = @cursor_recording
                    AND recording_id > @cursor_recording_id
                )
            ORDER BY
                match_priority,
                sort_title,
                sort_artist,
                sort_recording,
                recording_id
            LIMIT @take;
            """;

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(sql, connection)
        {
            CommandTimeout = 15
        };

        command.Parameters.AddWithValue(
            "query",
            NpgsqlDbType.Text,
            normalizedQuery);
        command.Parameters.AddWithValue(
            "territory_code",
            NpgsqlDbType.Varchar,
            normalizedTerritory);
        command.Parameters.Add(
            new NpgsqlParameter("language_tag", NpgsqlDbType.Varchar)
            {
                Value = normalizedLanguage is null
                    ? DBNull.Value
                    : normalizedLanguage
            });
        command.Parameters.Add(
            new NpgsqlParameter("cursor_priority", NpgsqlDbType.Integer)
            {
                Value = decodedCursor is null
                    ? DBNull.Value
                    : decodedCursor.Priority
            });
        command.Parameters.Add(
            new NpgsqlParameter("cursor_title", NpgsqlDbType.Text)
            {
                Value = decodedCursor is null
                    ? DBNull.Value
                    : decodedCursor.Title
            });
        command.Parameters.Add(
            new NpgsqlParameter("cursor_artist", NpgsqlDbType.Text)
            {
                Value = decodedCursor is null
                    ? DBNull.Value
                    : decodedCursor.Artist
            });
        command.Parameters.Add(
            new NpgsqlParameter("cursor_recording", NpgsqlDbType.Text)
            {
                Value = decodedCursor is null
                    ? DBNull.Value
                    : decodedCursor.Recording
            });
        command.Parameters.Add(
            new NpgsqlParameter("cursor_recording_id", NpgsqlDbType.Uuid)
            {
                Value = decodedCursor is null
                    ? DBNull.Value
                    : decodedCursor.RecordingId
            });
        command.Parameters.AddWithValue(
            "take",
            NpgsqlDbType.Integer,
            normalizedPageSize + 1);

        var rows = new List<SearchRow>(normalizedPageSize + 1);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new SearchRow(
                new PublicCatalogSearchItem(
                    PublicSongSlug.Compose(reader.GetString(3), reader.GetString(12)),
                    reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetString(6),
                    reader.GetString(7),
                    reader.GetString(9),
                    reader.IsDBNull(10) ? null : reader.GetString(10),
                    reader.GetDateTime(11)),
                reader.GetGuid(1),
                reader.GetInt32(13),
                reader.GetString(14),
                reader.GetString(15),
                reader.GetString(16)));
        }

        var hasMore = rows.Count > normalizedPageSize;
        if (hasMore)
        {
            rows.RemoveAt(rows.Count - 1);
        }

        string? nextCursor = null;
        if (hasMore && rows.Count > 0)
        {
            var last = rows[^1];
            nextCursor = EncodeCursor(new SearchCursor(
                normalizedQuery,
                normalizedTerritory,
                normalizedLanguage,
                last.Priority,
                last.Title,
                last.Artist,
                last.Recording,
                last.RecordingId));
        }

        return new PublicCatalogSearchPage(
            rows.Select(static row => row.Item).ToArray(),
            nextCursor,
            normalizedPageSize,
            hasMore);
    }

    private static async Task AcquireSearchIndexLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended(
                    'BL-MVP-042:PUBLIC-CATALOG-SEARCH',
                    0
                )
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static string NormalizeQuery(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var normalized = value
            .Normalize(NormalizationForm.FormKC)
            .Trim()
            .ToLowerInvariant();

        normalized = string.Join(
            ' ',
            normalized.Split(
                (char[]?)null,
                StringSplitOptions.RemoveEmptyEntries));

        if (normalized.Length > MaximumQueryLength)
        {
            throw new ArgumentException(
                $"La consulta no puede superar {MaximumQueryLength} caracteres.",
                nameof(value));
        }

        return normalized;
    }

    private static int NormalizePageSize(int? value)
    {
        if (value is null)
        {
            return DefaultPageSize;
        }

        if (value is < 1 or > MaximumPageSize)
        {
            throw new ArgumentException(
                $"PageSize debe estar entre 1 y {MaximumPageSize}.",
                nameof(value));
        }

        return value.Value;
    }

    private static string NormalizeCode(
        string value,
        string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length is < 1 or > 64
            || !IsUpperAsciiLetterOrDigit(normalized[0]))
        {
            throw new ArgumentException(
                "El codigo debe usar formato [A-Z0-9][A-Z0-9._-]*.",
                parameterName);
        }

        for (var index = 1; index < normalized.Length; index++)
        {
            var character = normalized[index];
            if (!(IsUpperAsciiLetterOrDigit(character)
                  || character is '.' or '_' or '-'))
            {
                throw new ArgumentException(
                    "El codigo debe usar formato [A-Z0-9][A-Z0-9._-]*.",
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
                "La etiqueta de idioma no cumple el formato BCP-47 minimo esperado.",
                nameof(value));
        }

        foreach (var part in parts.Skip(1))
        {
            if (part.Length is < 1 or > 8
                || !part.All(char.IsAsciiLetterOrDigit))
            {
                throw new ArgumentException(
                    "La etiqueta de idioma no cumple el formato BCP-47 minimo esperado.",
                    nameof(value));
            }
        }

        return normalized;
    }

    private static SearchCursor? DecodeCursor(
        string? token,
        string query,
        string territory,
        string? language)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return null;
        }

        if (token.Length > MaximumCursorLength)
        {
            throw new ArgumentException(
                "El cursor excede la longitud permitida.",
                nameof(token));
        }

        try
        {
            var bytes = Convert.FromBase64String(
                RestoreBase64Padding(
                    token.Replace('-', '+').Replace('_', '/')));

            var cursor = JsonSerializer.Deserialize<SearchCursor>(bytes)
                ?? throw new JsonException("Cursor vacio.");

            if (!string.Equals(cursor.Query, query, StringComparison.Ordinal)
                || !string.Equals(
                    cursor.Territory,
                    territory,
                    StringComparison.Ordinal)
                || !string.Equals(
                    cursor.Language,
                    language,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new ArgumentException(
                    "El cursor pertenece a otra consulta o contexto territorial.",
                    nameof(token));
            }

            return cursor;
        }
        catch (ArgumentException)
        {
            throw;
        }
        catch (Exception exception)
            when (exception is FormatException or JsonException)
        {
            throw new ArgumentException(
                "El cursor de paginacion no es valido.",
                nameof(token),
                exception);
        }
    }

    private static string EncodeCursor(SearchCursor cursor)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(cursor);
        return Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    private static string RestoreBase64Padding(string value)
    {
        return (value.Length % 4) switch
        {
            0 => value,
            2 => value + "==",
            3 => value + "=",
            _ => throw new FormatException("Longitud base64 invalida.")
        };
    }

    private static bool IsUpperAsciiLetterOrDigit(char character)
    {
        return character is >= 'A' and <= 'Z'
            || char.IsAsciiDigit(character);
    }

    private sealed record SearchCursor(
        string Query,
        string Territory,
        string? Language,
        int Priority,
        string Title,
        string Artist,
        string Recording,
        Guid RecordingId);

    private sealed record SearchRow(
        PublicCatalogSearchItem Item,
        Guid RecordingId,
        int Priority,
        string Title,
        string Artist,
        string Recording);
}
