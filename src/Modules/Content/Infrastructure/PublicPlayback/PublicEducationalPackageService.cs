using System.Data;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

public sealed record PublicEducationalPackageSource(
    string ProviderCode,
    string ExternalRef,
    long Version);

public sealed record PublicEducationalPackageAvailability(
    string TerritoryCode,
    string? LanguageTag,
    DateTime ValidFrom,
    DateTime? ValidTo);

public sealed record PublicEducationalPackageComponent(
    string Kind,
    int DisplayOrder,
    int RevisionNo,
    string StatusCode,
    string ChecksumSha256,
    string? LanguageTag);

public sealed record PublicEducationalPackageCapabilities(
    bool Lyrics,
    bool Timing,
    bool Translation,
    bool Analysis,
    bool Exercise);

public sealed record PublicEducationalPackage(
    int SchemaVersion,
    string Slug,
    int PublicationNo,
    int PackageNo,
    string PublicationChecksumSha256,
    string PackageChecksumSha256,
    long ProjectionVersion,
    DateTime ProjectionBuiltAt,
    PublicEducationalPackageSource Source,
    PublicEducationalPackageAvailability Availability,
    PublicEducationalPackageCapabilities Capabilities,
    IReadOnlyList<PublicEducationalPackageComponent> Components);

public sealed class AmbiguousPublicEducationalPackageException : Exception
{
    public AmbiguousPublicEducationalPackageException()
        : base("El paquete educativo coincide con más de una publicación elegible.")
    {
    }
}

public sealed class IncompatiblePublicEducationalPackageException : Exception
{
    public IncompatiblePublicEducationalPackageException(string message)
        : base(message)
    {
    }
}

public sealed class PublicEducationalPackageService
{
    private const int PublicKeyLength = 20;
    private const int MaximumSlugLength = 160;
    private readonly string _connectionString;

    public PublicEducationalPackageService(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        _connectionString = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para el paquete educativo público.");
    }

    public async Task<PublicEducationalPackage?> ReadAsync(
        string slug,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken = default)
    {
        var slugKey = ExtractSlugKey(slug);
        var normalizedTerritory = NormalizeCode(
            territoryCode,
            nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag) ?? "es";

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.RepeatableRead,
            cancellationToken);

        await using (var readOnly = new NpgsqlCommand(
                         "SET TRANSACTION READ ONLY;",
                         connection,
                         transaction))
        {
            await readOnly.ExecuteNonQueryAsync(cancellationToken);
        }

        var headers = await ReadEligibleHeadersAsync(
            connection,
            transaction,
            slugKey,
            normalizedTerritory,
            normalizedLanguage,
            cancellationToken);

        if (headers.Count == 0)
        {
            await transaction.CommitAsync(cancellationToken);
            return null;
        }

        if (headers.Count > 1)
        {
            throw new AmbiguousPublicEducationalPackageException();
        }

        var header = headers[0];

        var components = await ReadComponentsAsync(
            connection,
            transaction,
            header.PublicationId,
            header.PackageId,
            cancellationToken);

        ValidateCanonicalComponents(header, components);
        ValidateProjection(header, components);

        await transaction.CommitAsync(cancellationToken);

        var publicComponents = components
            .OrderBy(static component => component.DisplayOrder)
            .ThenBy(static component => component.Kind, StringComparer.Ordinal)
            .Select(static component => new PublicEducationalPackageComponent(
                component.Kind,
                component.DisplayOrder,
                component.RevisionNo!.Value,
                component.StatusCode!,
                component.RevisionChecksumSha256!,
                component.LanguageTag))
            .ToList();

        return new PublicEducationalPackage(
            1,
            slug.Trim(),
            header.PublicationNo,
            header.PackageNo,
            header.PublicationChecksumSha256,
            header.PackageChecksumSha256,
            header.ProjectionVersion,
            header.ProjectionBuiltAt,
            new PublicEducationalPackageSource(
                header.ProviderCode,
                header.ExternalRef,
                header.SourceVersion),
            new PublicEducationalPackageAvailability(
                header.TerritoryCode,
                header.LanguageTag,
                header.AvailabilityValidFrom,
                header.AvailabilityValidTo),
            new PublicEducationalPackageCapabilities(
                publicComponents.Any(
                    static item => item.Kind == "LYRICS"),
                publicComponents.Any(
                    static item => item.Kind == "TIMING"),
                publicComponents.Any(
                    static item => item.Kind == "TRANSLATION"),
                publicComponents.Any(
                    static item => item.Kind == "ANALYSIS"),
                publicComponents.Any(
                    static item => item.Kind == "EXERCISE")),
            publicComponents);
    }

    private static async Task<List<EligibleHeader>> ReadEligibleHeadersAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string slugKey,
        string territoryCode,
        string languageTag,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                publication.publication_id,
                publication.recording_id,
                publication.package_id,
                publication.publication_no,
                package.package_no,
                encode(publication.checksum, 'hex') AS publication_checksum,
                encode(package.checksum, 'hex') AS package_checksum,
                projection.component_versions::text,
                projection.projection_version,
                projection.built_at,
                source.source_id,
                source.provider_code,
                source.external_ref,
                source.version,
                availability.territory_code,
                availability.language_tag,
                availability.valid_from,
                availability.valid_to
            FROM editorial.published_package_projection AS projection
            INNER JOIN editorial.publication AS publication
                ON publication.publication_id = projection.publication_id
               AND publication.recording_id = projection.recording_id
            INNER JOIN editorial.editorial_package AS package
                ON package.package_id = publication.package_id
               AND package.recording_id = publication.recording_id
               AND package.status_code = 'APPROVED'
               AND package.frozen_at IS NOT NULL
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
                      availability_row.language_tag IS NULL
                      OR lower(availability_row.language_tag) =
                         lower(@language_tag)
                  )
                ORDER BY
                    CASE
                        WHEN availability_row.language_tag IS NOT NULL
                         AND lower(availability_row.language_tag) =
                             lower(@language_tag)
                        THEN 0
                        ELSE 1
                    END,
                    availability_row.valid_from DESC,
                    availability_row.availability_id
                LIMIT 1
            ) AS availability ON true
            WHERE upper(
                      substring(
                          md5(
                              recording.recording_id::text
                              || ':public-song-v1'
                          )
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
            ORDER BY
                publication.active_from DESC,
                publication.publication_no DESC
            LIMIT 2;
            """;

        var result = new List<EligibleHeader>(2);

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction)
        {
            CommandTimeout = 15
        };

        command.Parameters.AddWithValue(
            "slug_key",
            NpgsqlDbType.Varchar,
            slugKey);
        command.Parameters.AddWithValue(
            "territory_code",
            NpgsqlDbType.Varchar,
            territoryCode);
        command.Parameters.AddWithValue(
            "language_tag",
            NpgsqlDbType.Varchar,
            languageTag);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new EligibleHeader(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetGuid(2),
                    reader.GetInt32(3),
                    reader.GetInt32(4),
                    reader.GetString(5).ToUpperInvariant(),
                    reader.GetString(6).ToUpperInvariant(),
                    reader.GetString(7),
                    reader.GetInt64(8),
                    reader.GetDateTime(9),
                    reader.GetGuid(10),
                    reader.GetString(11),
                    reader.GetString(12),
                    reader.GetInt64(13),
                    reader.GetString(14),
                    reader.IsDBNull(15) ? null : reader.GetString(15),
                    reader.GetDateTime(16),
                    reader.IsDBNull(17) ? null : reader.GetDateTime(17)));
        }

        return result;
    }

    private static async Task<List<ComponentRow>> ReadComponentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid publicationId,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                published.component_kind,
                published.display_order,
                published.source_component_id,
                encode(published.component_checksum, 'hex'),
                encode(package_component.checksum, 'hex'),
                package_component.lyrics_revision_id,
                package_component.timing_revision_id,
                package_component.translation_revision_id,
                package_component.analysis_revision_id,
                package_component.exercise_revision_id,
                COALESCE(
                    lyrics.revision_no,
                    timing.revision_no,
                    translation.revision_no,
                    analysis.revision_no,
                    exercise.revision_no
                ) AS revision_no,
                COALESCE(
                    lyrics.status_code,
                    timing.status_code,
                    translation.status_code,
                    analysis.status_code,
                    exercise.status_code
                ) AS status_code,
                encode(
                    COALESCE(
                        lyrics.checksum,
                        timing.checksum,
                        translation.checksum,
                        analysis.checksum,
                        exercise.checksum
                    ),
                    'hex'
                ) AS revision_checksum,
                translation.target_language,
                lyrics.recording_id,
                timing.lyrics_revision_id,
                timing.source_id,
                translation.lyrics_revision_id,
                analysis.lyrics_revision_id,
                exercise_definition.recording_id,
                CASE
                    WHEN exercise_definition.line_id IS NULL THEN true
                    ELSE EXISTS (
                        SELECT 1
                        FROM content.lyric_line AS exercise_line
                        INNER JOIN content.lyric_section AS exercise_section
                            ON exercise_section.section_id =
                               exercise_line.section_id
                        WHERE exercise_line.line_id =
                              exercise_definition.line_id
                          AND exercise_section.lyrics_revision_id =
                              lyrics_anchor.lyrics_revision_id
                    )
                END AS exercise_line_compatible
            FROM editorial.publication_component AS published
            INNER JOIN editorial.package_component AS package_component
                ON package_component.package_component_id =
                   published.source_component_id
               AND package_component.package_id = @package_id
               AND package_component.component_kind =
                   published.component_kind
            LEFT JOIN LATERAL (
                SELECT anchor.lyrics_revision_id
                FROM editorial.package_component AS anchor
                WHERE anchor.package_id = @package_id
                  AND anchor.component_kind = 'LYRICS'
                  AND anchor.lyrics_revision_id IS NOT NULL
                ORDER BY anchor.package_component_id
                LIMIT 1
            ) AS lyrics_anchor ON true
            LEFT JOIN content.lyrics_revision AS lyrics
                ON published.component_kind = 'LYRICS'
               AND lyrics.lyrics_revision_id =
                   package_component.lyrics_revision_id
            LEFT JOIN content.timing_revision AS timing
                ON published.component_kind = 'TIMING'
               AND timing.timing_revision_id =
                   package_component.timing_revision_id
            LEFT JOIN content.translation_revision AS translation
                ON published.component_kind = 'TRANSLATION'
               AND translation.translation_revision_id =
                   package_component.translation_revision_id
            LEFT JOIN content.linguistic_analysis_revision AS analysis
                ON published.component_kind = 'ANALYSIS'
               AND analysis.analysis_revision_id =
                   package_component.analysis_revision_id
            LEFT JOIN learning.exercise_revision AS exercise
                ON published.component_kind = 'EXERCISE'
               AND exercise.exercise_revision_id =
                   package_component.exercise_revision_id
            LEFT JOIN learning.exercise_definition AS exercise_definition
                ON exercise_definition.exercise_id = exercise.exercise_id
            WHERE published.publication_id = @publication_id
            ORDER BY
                published.display_order,
                published.publication_component_id;
            """;

        var result = new List<ComponentRow>();

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "publication_id",
            NpgsqlDbType.Uuid,
            publicationId);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new ComponentRow(
                    reader.GetString(0),
                    reader.GetInt32(1),
                    reader.GetGuid(2),
                    reader.GetString(3).ToUpperInvariant(),
                    reader.GetString(4).ToUpperInvariant(),
                    reader.IsDBNull(5) ? null : reader.GetGuid(5),
                    reader.IsDBNull(6) ? null : reader.GetGuid(6),
                    reader.IsDBNull(7) ? null : reader.GetGuid(7),
                    reader.IsDBNull(8) ? null : reader.GetGuid(8),
                    reader.IsDBNull(9) ? null : reader.GetGuid(9),
                    reader.IsDBNull(10) ? null : reader.GetInt32(10),
                    reader.IsDBNull(11) ? null : reader.GetString(11),
                    reader.IsDBNull(12)
                        ? null
                        : reader.GetString(12).ToUpperInvariant(),
                    reader.IsDBNull(13) ? null : reader.GetString(13),
                    reader.IsDBNull(14) ? null : reader.GetGuid(14),
                    reader.IsDBNull(15) ? null : reader.GetGuid(15),
                    reader.IsDBNull(16) ? null : reader.GetGuid(16),
                    reader.IsDBNull(17) ? null : reader.GetGuid(17),
                    reader.IsDBNull(18) ? null : reader.GetGuid(18),
                    reader.IsDBNull(19) ? null : reader.GetGuid(19),
                    !reader.IsDBNull(20) && reader.GetBoolean(20)));
        }

        return result;
    }

    private static void ValidateCanonicalComponents(
        EligibleHeader header,
        IReadOnlyList<ComponentRow> components)
    {
        if (components.Count == 0)
        {
            throw Incompatible("La publicación no contiene componentes.");
        }

        var lyricsRows = components
            .Where(static component => component.Kind == "LYRICS")
            .ToList();

        if (lyricsRows.Count != 1
            || lyricsRows[0].LyricsRevisionId is not { } lyricsRevisionId)
        {
            throw Incompatible(
                "La publicación debe contener una única revisión de letra.");
        }

        var lyrics = lyricsRows[0];

        if (lyrics.LyricsRecordingId != header.RecordingId)
        {
            throw Incompatible(
                "La revisión de letra no pertenece a la grabación publicada.");
        }

        var singleKinds = new[] { "TIMING", "TRANSLATION", "ANALYSIS" };
        foreach (var kind in singleKinds)
        {
            if (components.Count(component => component.Kind == kind) > 1)
            {
                throw Incompatible(
                    $"La publicación contiene más de un componente {kind}.");
            }
        }

        foreach (var component in components)
        {
            if (component.RevisionNo is null
                || string.IsNullOrWhiteSpace(component.StatusCode)
                || string.IsNullOrWhiteSpace(
                    component.RevisionChecksumSha256))
            {
                throw Incompatible(
                    $"El componente {component.Kind} no resuelve una revisión canónica.");
            }

            if (!HexEquals(
                    component.PublicationComponentChecksumSha256,
                    component.PackageComponentChecksumSha256)
                || !HexEquals(
                    component.PackageComponentChecksumSha256,
                    component.RevisionChecksumSha256))
            {
                throw Incompatible(
                    $"El checksum del componente {component.Kind} no coincide con su revisión.");
            }

            switch (component.Kind)
            {
                case "LYRICS":
                    if (component.LyricsRevisionId != lyricsRevisionId)
                    {
                        throw Incompatible(
                            "La revisión de letra publicada es inconsistente.");
                    }

                    break;

                case "TIMING":
                    if (component.TimingRevisionId is null
                        || component.TimingLyricsRevisionId != lyricsRevisionId
                        || component.TimingSourceId != header.SourceId)
                    {
                        throw Incompatible(
                            "La sincronización no corresponde a la letra y fuente publicadas.");
                    }

                    break;

                case "TRANSLATION":
                    if (component.TranslationRevisionId is null
                        || component.TranslationLyricsRevisionId !=
                           lyricsRevisionId)
                    {
                        throw Incompatible(
                            "La traducción no corresponde a la letra publicada.");
                    }

                    break;

                case "ANALYSIS":
                    if (component.AnalysisRevisionId is null
                        || component.AnalysisLyricsRevisionId !=
                           lyricsRevisionId)
                    {
                        throw Incompatible(
                            "El análisis no corresponde a la letra publicada.");
                    }

                    break;

                case "EXERCISE":
                    if (component.ExerciseRevisionId is null
                        || component.ExerciseRecordingId !=
                           header.RecordingId
                        || !component.ExerciseLineCompatible)
                    {
                        throw Incompatible(
                            "El ejercicio no corresponde a la grabación o letra publicadas.");
                    }

                    break;

                default:
                    throw Incompatible(
                        $"Tipo de componente publicado no reconocido: {component.Kind}.");
            }
        }
    }

    private static void ValidateProjection(
        EligibleHeader header,
        IReadOnlyList<ComponentRow> components)
    {
        JsonDocument projection;

        try
        {
            projection = JsonDocument.Parse(header.ComponentVersionsJson);
        }
        catch (JsonException exception)
        {
            throw new IncompatiblePublicEducationalPackageException(
                $"La proyección publicada no es JSON válido: {exception.Message}");
        }

        using (projection)
        {
            var root = projection.RootElement;

            if (!root.TryGetProperty("schemaVersion", out var schemaVersion)
                || schemaVersion.GetInt32() != 1)
            {
                throw Incompatible(
                    "La proyección publicada usa un schemaVersion incompatible.");
            }

            if (!root.TryGetProperty("publicationNo", out var publicationNo)
                || publicationNo.GetInt32() != header.PublicationNo)
            {
                throw Incompatible(
                    "La proyección no corresponde al número de publicación activo.");
            }

            if (!root.TryGetProperty(
                    "publicationChecksum",
                    out var publicationChecksum)
                || !HexEquals(
                    publicationChecksum.GetString(),
                    header.PublicationChecksumSha256))
            {
                throw Incompatible(
                    "La proyección no coincide con el checksum de la publicación activa.");
            }

            if (!root.TryGetProperty("source", out var source)
                || !source.TryGetProperty("sourceId", out var sourceId)
                || !Guid.TryParse(sourceId.GetString(), out var projectedSourceId)
                || projectedSourceId != header.SourceId
                || !source.TryGetProperty(
                    "providerCode",
                    out var providerCode)
                || !string.Equals(
                    providerCode.GetString(),
                    header.ProviderCode,
                    StringComparison.Ordinal)
                || !source.TryGetProperty(
                    "externalRef",
                    out var externalRef)
                || !string.Equals(
                    externalRef.GetString(),
                    header.ExternalRef,
                    StringComparison.Ordinal)
                || !source.TryGetProperty("version", out var sourceVersion)
                || sourceVersion.GetInt64() != header.SourceVersion)
            {
                throw Incompatible(
                    "La fuente de la proyección no coincide con la fuente canónica.");
            }

            if (!root.TryGetProperty("components", out var projectedComponents)
                || projectedComponents.ValueKind != JsonValueKind.Array
                || projectedComponents.GetArrayLength() != components.Count)
            {
                throw Incompatible(
                    "La proyección no contiene exactamente los componentes publicados.");
            }

            var matched = new HashSet<Guid>();

            foreach (var projected in projectedComponents.EnumerateArray())
            {
                if (!projected.TryGetProperty("kind", out var kind)
                    || !projected.TryGetProperty(
                        "sourceComponentId",
                        out var sourceComponentId)
                    || !Guid.TryParse(
                        sourceComponentId.GetString(),
                        out var projectedComponentId)
                    || !projected.TryGetProperty(
                        "checksum",
                        out var checksum)
                    || !projected.TryGetProperty(
                        "displayOrder",
                        out var displayOrder))
                {
                    throw Incompatible(
                        "La proyección contiene un componente incompleto.");
                }

                var canonical = components.SingleOrDefault(
                    component =>
                        component.SourceComponentId == projectedComponentId
                        && string.Equals(
                            component.Kind,
                            kind.GetString(),
                            StringComparison.Ordinal));

                if (canonical is null
                    || canonical.DisplayOrder != displayOrder.GetInt32()
                    || !HexEquals(
                        canonical.PublicationComponentChecksumSha256,
                        checksum.GetString())
                    || !matched.Add(projectedComponentId))
                {
                    throw Incompatible(
                        "La proyección no coincide con la instantánea publicada.");
                }
            }

            if (matched.Count != components.Count)
            {
                throw Incompatible(
                    "La proyección omite componentes de la publicación.");
            }
        }
    }

    private static IncompatiblePublicEducationalPackageException Incompatible(
        string message) =>
        new(message);

    private static bool HexEquals(string? left, string? right) =>
        !string.IsNullOrWhiteSpace(left)
        && !string.IsNullOrWhiteSpace(right)
        && string.Equals(
            left.Trim(),
            right.Trim(),
            StringComparison.OrdinalIgnoreCase);

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

    private static string NormalizeCode(
        string value,
        string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(
            value,
            parameterName);

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
        character is >= 'A' and <= 'Z'
        || char.IsAsciiDigit(character);

    private sealed record EligibleHeader(
        Guid PublicationId,
        Guid RecordingId,
        Guid PackageId,
        int PublicationNo,
        int PackageNo,
        string PublicationChecksumSha256,
        string PackageChecksumSha256,
        string ComponentVersionsJson,
        long ProjectionVersion,
        DateTime ProjectionBuiltAt,
        Guid SourceId,
        string ProviderCode,
        string ExternalRef,
        long SourceVersion,
        string TerritoryCode,
        string? LanguageTag,
        DateTime AvailabilityValidFrom,
        DateTime? AvailabilityValidTo);

    private sealed record ComponentRow(
        string Kind,
        int DisplayOrder,
        Guid SourceComponentId,
        string PublicationComponentChecksumSha256,
        string PackageComponentChecksumSha256,
        Guid? LyricsRevisionId,
        Guid? TimingRevisionId,
        Guid? TranslationRevisionId,
        Guid? AnalysisRevisionId,
        Guid? ExerciseRevisionId,
        int? RevisionNo,
        string? StatusCode,
        string? RevisionChecksumSha256,
        string? LanguageTag,
        Guid? LyricsRecordingId,
        Guid? TimingLyricsRevisionId,
        Guid? TimingSourceId,
        Guid? TranslationLyricsRevisionId,
        Guid? AnalysisLyricsRevisionId,
        Guid? ExerciseRecordingId,
        bool ExerciseLineCompatible);
}
