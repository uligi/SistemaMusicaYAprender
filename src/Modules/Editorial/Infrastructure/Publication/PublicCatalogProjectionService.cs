using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;

public sealed record PublicCatalogProjectionRebuildResult(
    long EligiblePublications,
    long InsertedOrUpdated,
    long Removed);

public sealed record PublicCatalogPublication(
    Guid PublicationId,
    Guid RecordingId,
    Guid WorkId,
    string CanonicalTitle,
    string? RecordingTitle,
    long? RecordingDurationMs,
    Guid ArtistId,
    string ArtistName,
    Guid SourceId,
    string ProviderCode,
    string ExternalRef,
    long? SourceDurationMs,
    long SourceOffsetMs,
    string TerritoryCode,
    string? LanguageTag,
    DateTime AvailabilityValidFrom,
    DateTime? AvailabilityValidTo,
    DateTime PublicationActiveFrom,
    DateTime? PublicationActiveTo,
    long ProjectionVersion,
    DateTime ProjectionBuiltAt);

public sealed class PublicCatalogProjectionService
{
    private const string PublicAudienceCode = "PUBLIC";
    private readonly string _connectionString;

    public PublicCatalogProjectionService(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        _connectionString = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para la proyeccion publica de catalogo.");
    }

    public async Task<PublicCatalogProjectionRebuildResult> RebuildAsync(
        CancellationToken cancellationToken = default)
    {
        const string sql = """
            WITH eligible AS (
                SELECT
                    p.publication_id,
                    p.recording_id,
                    jsonb_build_object(
                        'schemaVersion', 1,
                        'publicationNo', p.publication_no,
                        'publicationChecksum', encode(p.checksum, 'hex'),
                        'source', jsonb_build_object(
                            'sourceId', source.source_id,
                            'providerCode', source.provider_code,
                            'externalRef', source.external_ref,
                            'version', source.version
                        ),
                        'components', COALESCE(
                            (
                                SELECT jsonb_agg(
                                    jsonb_build_object(
                                        'kind', pc.component_kind,
                                        'sourceComponentId', pc.source_component_id,
                                        'checksum', encode(pc.component_checksum, 'hex'),
                                        'displayOrder', pc.display_order
                                    )
                                    ORDER BY
                                        pc.display_order,
                                        pc.component_kind,
                                        pc.publication_component_id
                                )
                                FROM editorial.publication_component AS pc
                                WHERE pc.publication_id = p.publication_id
                            ),
                            '[]'::jsonb
                        )
                    ) AS component_versions
                FROM editorial.publication AS p
                INNER JOIN catalog.recording AS r
                    ON r.recording_id = p.recording_id
                INNER JOIN catalog.musical_work AS w
                    ON w.work_id = r.work_id
                INNER JOIN LATERAL (
                    SELECT
                        wa.artist_id,
                        a.canonical_name
                    FROM catalog.work_artist AS wa
                    INNER JOIN catalog.artist AS a
                        ON a.artist_id = wa.artist_id
                    WHERE wa.work_id = w.work_id
                      AND wa.role_code = 'PRIMARY'
                      AND a.status_code = 'ACTIVE'
                    ORDER BY wa.display_order, wa.artist_id
                    LIMIT 1
                ) AS primary_artist ON true
                INNER JOIN LATERAL (
                    SELECT
                        rs.source_id,
                        rs.provider_code,
                        rs.external_ref,
                        rs.version
                    FROM catalog.recording_source AS rs
                    WHERE rs.recording_id = r.recording_id
                      AND rs.provider_code = 'YOUTUBE'
                      AND rs.status_code IN ('ACTIVE', 'PUBLISHED')
                      AND rs.external_ref ~ '^[A-Za-z0-9_-]{11}$'
                    ORDER BY rs.version DESC, rs.source_id DESC
                    LIMIT 1
                ) AS source ON true
                WHERE p.status_code = 'ACTIVE'
                  AND p.active_from <= CURRENT_TIMESTAMP
                  AND (p.active_to IS NULL OR p.active_to > CURRENT_TIMESTAMP)
                  AND EXISTS (
                      SELECT 1
                      FROM editorial.publication_availability AS pa
                      WHERE pa.publication_id = p.publication_id
                        AND pa.audience_code = 'PUBLIC'
                        AND pa.status_code = 'ACTIVE'
                        AND pa.valid_from <= CURRENT_TIMESTAMP
                        AND (pa.valid_to IS NULL OR pa.valid_to > CURRENT_TIMESTAMP)
                  )
            ),
            upserted AS (
                INSERT INTO editorial.published_package_projection (
                    publication_id,
                    recording_id,
                    component_versions,
                    payload_ref,
                    projection_version,
                    built_at
                )
                SELECT
                    e.publication_id,
                    e.recording_id,
                    e.component_versions,
                    NULL,
                    1,
                    CURRENT_TIMESTAMP
                FROM eligible AS e
                ON CONFLICT (publication_id) DO UPDATE
                SET recording_id = EXCLUDED.recording_id,
                    component_versions = EXCLUDED.component_versions,
                    projection_version =
                        editorial.published_package_projection.projection_version + 1,
                    built_at = EXCLUDED.built_at
                WHERE editorial.published_package_projection.recording_id
                          IS DISTINCT FROM EXCLUDED.recording_id
                   OR editorial.published_package_projection.component_versions
                          IS DISTINCT FROM EXCLUDED.component_versions
                RETURNING publication_id
            ),
            removed AS (
                DELETE FROM editorial.published_package_projection AS projection
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM eligible AS e
                    WHERE e.publication_id = projection.publication_id
                )
                RETURNING publication_id
            )
            SELECT
                (SELECT count(*) FROM eligible),
                (SELECT count(*) FROM upserted),
                (SELECT count(*) FROM removed);
            """;

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await AcquireProjectionLockAsync(connection, transaction, cancellationToken);

        await using var command = new NpgsqlCommand(sql, connection, transaction)
        {
            CommandTimeout = 30
        };

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "La reconstruccion de la proyeccion publica no devolvio su resumen.");
        }

        var result = new PublicCatalogProjectionRebuildResult(
            reader.GetInt64(0),
            reader.GetInt64(1),
            reader.GetInt64(2));

        await reader.DisposeAsync();
        await transaction.CommitAsync(cancellationToken);

        return result;
    }

    public async Task<PublicCatalogPublication?> ReadEligibleAsync(
        Guid publicationId,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken = default)
    {
        if (publicationId == Guid.Empty)
        {
            throw new ArgumentException(
                "PublicationId no puede ser Guid.Empty.",
                nameof(publicationId));
        }

        var normalizedTerritory = NormalizeCode(
            territoryCode,
            nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag);

        const string sql = """
            SELECT
                p.publication_id,
                p.recording_id,
                w.work_id,
                w.canonical_title,
                r.recording_title,
                r.duration_ms,
                primary_artist.artist_id,
                primary_artist.canonical_name,
                source.source_id,
                source.provider_code,
                source.external_ref,
                source.duration_ms,
                source.offset_ms,
                pa.territory_code,
                pa.language_tag,
                pa.valid_from,
                pa.valid_to,
                p.active_from,
                p.active_to,
                projection.projection_version,
                projection.built_at
            FROM editorial.published_package_projection AS projection
            INNER JOIN editorial.publication AS p
                ON p.publication_id = projection.publication_id
               AND p.recording_id = projection.recording_id
            INNER JOIN catalog.recording AS r
                ON r.recording_id = p.recording_id
            INNER JOIN catalog.musical_work AS w
                ON w.work_id = r.work_id
            INNER JOIN LATERAL (
                SELECT
                    wa.artist_id,
                    a.canonical_name
                FROM catalog.work_artist AS wa
                INNER JOIN catalog.artist AS a
                    ON a.artist_id = wa.artist_id
                WHERE wa.work_id = w.work_id
                  AND wa.role_code = 'PRIMARY'
                  AND a.status_code = 'ACTIVE'
                ORDER BY wa.display_order, wa.artist_id
                LIMIT 1
            ) AS primary_artist ON true
            INNER JOIN catalog.recording_source AS source
                ON source.source_id = NULLIF(
                    projection.component_versions #>> '{source,sourceId}',
                    ''
                )::uuid
               AND source.recording_id = r.recording_id
               AND source.provider_code =
                    projection.component_versions #>> '{source,providerCode}'
               AND source.external_ref =
                    projection.component_versions #>> '{source,externalRef}'
               AND source.version = NULLIF(
                    projection.component_versions #>> '{source,version}',
                    ''
                )::bigint
            INNER JOIN editorial.publication_availability AS pa
                ON pa.publication_id = p.publication_id
            WHERE p.publication_id = @publication_id
              AND p.status_code = 'ACTIVE'
              AND p.active_from <= CURRENT_TIMESTAMP
              AND (p.active_to IS NULL OR p.active_to > CURRENT_TIMESTAMP)
              AND pa.territory_code = @territory_code
              AND pa.audience_code = 'PUBLIC'
              AND pa.status_code = 'ACTIVE'
              AND pa.valid_from <= CURRENT_TIMESTAMP
              AND (pa.valid_to IS NULL OR pa.valid_to > CURRENT_TIMESTAMP)
              AND (
                  (@language_tag IS NULL AND pa.language_tag IS NULL)
                  OR (
                      @language_tag IS NOT NULL
                      AND (
                          pa.language_tag IS NULL
                          OR lower(pa.language_tag) = lower(@language_tag)
                      )
                  )
              )
              AND source.provider_code = 'YOUTUBE'
              AND source.status_code IN ('ACTIVE', 'PUBLISHED')
              AND source.external_ref ~ '^[A-Za-z0-9_-]{11}$'
            ORDER BY
                CASE
                    WHEN @language_tag IS NOT NULL
                         AND pa.language_tag IS NOT NULL
                         AND lower(pa.language_tag) = lower(@language_tag)
                    THEN 0
                    ELSE 1
                END,
                pa.valid_from DESC,
                pa.availability_id
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection)
        {
            CommandTimeout = 15
        };

        command.Parameters.AddWithValue(
            "publication_id",
            NpgsqlDbType.Uuid,
            publicationId);
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

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new PublicCatalogPublication(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2),
            reader.GetString(3),
            reader.IsDBNull(4) ? null : reader.GetString(4),
            reader.IsDBNull(5) ? null : reader.GetInt64(5),
            reader.GetGuid(6),
            reader.GetString(7),
            reader.GetGuid(8),
            reader.GetString(9),
            reader.GetString(10),
            reader.IsDBNull(11) ? null : reader.GetInt64(11),
            reader.GetInt64(12),
            reader.GetString(13),
            reader.IsDBNull(14) ? null : reader.GetString(14),
            reader.GetDateTime(15),
            reader.IsDBNull(16) ? null : reader.GetDateTime(16),
            reader.GetDateTime(17),
            reader.IsDBNull(18) ? null : reader.GetDateTime(18),
            reader.GetInt64(19),
            reader.GetDateTime(20));
    }

    private static async Task AcquireProjectionLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended('BL-MVP-041:PUBLIC-CATALOG-PROJECTION', 0)
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static string NormalizeCode(string value, string parameterName)
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

    private static bool IsUpperAsciiLetterOrDigit(char character)
    {
        return character is >= 'A' and <= 'Z'
            || char.IsAsciiDigit(character);
    }
}
