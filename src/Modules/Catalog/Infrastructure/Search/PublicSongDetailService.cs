using System.Text;
using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Search;

public sealed record PublicSongDetail(
    string Slug,
    string CanonicalTitle,
    string? RecordingTitle,
    long? RecordingDurationMs,
    string ArtistName,
    string ProviderCode,
    string TerritoryCode,
    string? LanguageTag,
    DateTime AvailabilityValidFrom,
    DateTime? AvailabilityValidTo,
    IReadOnlyList<string> AvailableComponents,
    string SourceExternalRef);

public sealed class AmbiguousPublicSongException : Exception
{
    public AmbiguousPublicSongException()
        : base("La ficha publica coincide con mas de una publicacion elegible.")
    {
    }
}

public static class PublicSongSlug
{
    public const int KeyLength = 20;
    private const int MaximumStemLength = 80;
    private const int MaximumSlugLength = 160;

    public static string Compose(string canonicalTitle, string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(canonicalTitle);
        var normalizedKey = NormalizeKey(key);
        var stem = BuildStem(canonicalTitle);
        return $"{stem}-{normalizedKey}";
    }

    public static string ExtractKey(string slug)
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
                "El slug publico no tiene el formato esperado.",
                nameof(slug));
        }

        return NormalizeKey(normalized[(separator + 1)..]);
    }

    private static string NormalizeKey(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        var normalized = key.Trim().ToLowerInvariant();

        if (normalized.Length != KeyLength
            || normalized.Any(static character => !IsLowerHex(character)))
        {
            throw new ArgumentException(
                $"La clave publica debe contener {KeyLength} caracteres hexadecimales.",
                nameof(key));
        }

        return normalized;
    }

    private static string BuildStem(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormKC).Trim().ToLowerInvariant();
        var builder = new StringBuilder(Math.Min(normalized.Length, MaximumStemLength));
        var pendingSeparator = false;

        foreach (var character in normalized)
        {
            if (char.IsLetterOrDigit(character))
            {
                if (pendingSeparator && builder.Length > 0)
                {
                    builder.Append('-');
                }

                pendingSeparator = false;
                builder.Append(character);
                if (builder.Length >= MaximumStemLength)
                {
                    break;
                }

                continue;
            }

            if (builder.Length > 0)
            {
                pendingSeparator = true;
            }
        }

        var stem = builder.ToString().Trim('-');
        return string.IsNullOrWhiteSpace(stem) ? "cancion" : stem;
    }

    private static bool IsLowerHex(char character)
    {
        return character is >= '0' and <= '9'
            || character is >= 'a' and <= 'f';
    }
}

public sealed class PublicSongDetailService
{
    private readonly string _connectionString;

    public PublicSongDetailService(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        _connectionString = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para la ficha publica de cancion.");
    }

    public async Task<PublicSongDetail?> ReadAsync(
        string slug,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken = default)
    {
        var slugKey = PublicSongSlug.ExtractKey(slug);
        var normalizedTerritory = NormalizeCode(territoryCode, nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag);

        const string sql = """
            SELECT
                work.canonical_title,
                recording.recording_title,
                recording.duration_ms,
                primary_artist.canonical_name,
                source.provider_code,
                availability.territory_code,
                availability.language_tag,
                availability.valid_from,
                availability.valid_to,
                substring(
                    md5(recording.recording_id::text || ':public-song-v1')
                    from 1 for 20
                ) AS slug_key,
                COALESCE(
                    (
                        SELECT array_agg(component.kind ORDER BY component.kind)
                        FROM (
                            SELECT DISTINCT element ->> 'kind' AS kind
                            FROM jsonb_array_elements(
                                COALESCE(
                                    projection.component_versions -> 'components',
                                    '[]'::jsonb
                                )
                            ) AS element
                            WHERE COALESCE(element ->> 'kind', '') <> ''
                        ) AS component
                    ),
                    ARRAY[]::text[]
                ) AS component_kinds,
                source.external_ref
            FROM editorial.published_package_projection AS projection
            INNER JOIN editorial.publication AS publication
                ON publication.publication_id = projection.publication_id
               AND publication.recording_id = projection.recording_id
            INNER JOIN catalog.recording AS recording
                ON recording.recording_id = publication.recording_id
            INNER JOIN catalog.musical_work AS work
                ON work.work_id = recording.work_id
            INNER JOIN LATERAL (
                SELECT artist.canonical_name
                FROM catalog.work_artist AS work_artist
                INNER JOIN catalog.artist AS artist
                    ON artist.artist_id = work_artist.artist_id
                WHERE work_artist.work_id = work.work_id
                  AND work_artist.role_code = 'PRIMARY'
                  AND artist.status_code = 'ACTIVE'
                ORDER BY work_artist.display_order, work_artist.artist_id
                LIMIT 1
            ) AS primary_artist ON true
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

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection)
        {
            CommandTimeout = 15
        };

        command.Parameters.AddWithValue("slug_key", NpgsqlDbType.Varchar, slugKey);
        command.Parameters.AddWithValue(
            "territory_code",
            NpgsqlDbType.Varchar,
            normalizedTerritory);
        command.Parameters.Add(
            new NpgsqlParameter("language_tag", NpgsqlDbType.Varchar)
            {
                Value = normalizedLanguage is null ? DBNull.Value : normalizedLanguage
            });

        var rows = new List<PublicSongDetail>(2);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var canonicalTitle = reader.GetString(0);
            var currentKey = reader.GetString(9);
            rows.Add(new PublicSongDetail(
                PublicSongSlug.Compose(canonicalTitle, currentKey),
                canonicalTitle,
                reader.IsDBNull(1) ? null : reader.GetString(1),
                reader.IsDBNull(2) ? null : reader.GetInt64(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.GetDateTime(7),
                reader.IsDBNull(8) ? null : reader.GetDateTime(8),
                reader.GetFieldValue<string[]>(10),
                reader.GetString(11)));
        }

        return rows.Count switch
        {
            0 => null,
            1 => rows[0],
            _ => throw new AmbiguousPublicSongException()
        };
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
