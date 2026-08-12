using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Administration;

public sealed record ArtistAliasDraft(
    string AliasText,
    string LanguageTag,
    string ScriptCode,
    bool Preferred);

public sealed record ArtistDraft(
    string CanonicalName,
    string SortName,
    string ArtistType,
    string CanonicalLanguageTag,
    string CanonicalScriptCode,
    IReadOnlyList<ArtistAliasDraft> Aliases);

public sealed record ArtistDuplicateCandidate(
    Guid ArtistId,
    string CanonicalName,
    string ArtistType,
    string StatusCode,
    string MatchedText,
    double Similarity);

public sealed record ArtistSearchResult(
    Guid ArtistId,
    string CanonicalName,
    string ArtistType,
    string StatusCode,
    string MatchedText,
    double Similarity);

public sealed record ArtistDuplicateReview(
    IReadOnlyList<ArtistDuplicateCandidate> Candidates,
    bool RequiresAcknowledgement);

public sealed record ArtistCreatedResult(
    Guid ArtistId,
    string CanonicalName,
    string ArtistType,
    string StatusCode,
    IReadOnlyList<ArtistAliasDraft> Aliases,
    bool DuplicateWarningAcknowledged,
    bool AlreadyApplied);

public sealed class ArtistAdministrationException(
    string code,
    string message,
    IReadOnlyList<ArtistDuplicateCandidate>? duplicates = null)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;

    public IReadOnlyList<ArtistDuplicateCandidate> Duplicates { get; } =
        duplicates ?? [];
}

public sealed partial class ArtistAdministrationService(
    IArtistAdministrationTransactionExecutor transactionExecutor)
{
    private const int MaxTextLength = 512;
    private const int MaxAliasCount = 32;
    private const double DuplicateSimilarity = 0.72;
    private const double SearchSimilarity = 0.30;

    [GeneratedRegex(
        "^[A-Z0-9][A-Z0-9._-]{0,63}$",
        RegexOptions.CultureInvariant)]
    private static partial Regex CodePattern();

    [GeneratedRegex(
        "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex LanguageTagPattern();

    [GeneratedRegex(
        "\\s+",
        RegexOptions.CultureInvariant)]
    private static partial Regex WhitespacePattern();

    public Task<IReadOnlyList<ArtistSearchResult>> SearchAsync(
        Guid actorAccountId,
        string query,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                SearchCoreAsync(
                    connection,
                    transaction,
                    query,
                    token),
            cancellationToken);
    }

    public Task<ArtistDuplicateReview> CheckDuplicatesAsync(
        Guid actorAccountId,
        ArtistDraft draft,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(draft);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                var prepared = PrepareDraft(draft);
                var candidates = await FindDuplicatesAsync(
                    connection,
                    transaction,
                    prepared,
                    excludedArtistId: null,
                    token);

                return new ArtistDuplicateReview(
                    candidates,
                    candidates.Count > 0);
            },
            cancellationToken);
    }

    public Task<ArtistCreatedResult> CreateAsync(
        Guid actorAccountId,
        ArtistDraft draft,
        string idempotencyKey,
        bool acknowledgePotentialDuplicates,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(draft);

        if (string.IsNullOrWhiteSpace(idempotencyKey)
            || idempotencyKey.Trim().Length > 128)
        {
            throw new ArtistAdministrationException(
                "catalog.artist.idempotency-key.invalid",
                "La creación requiere una clave de idempotencia válida.");
        }

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                CreateCoreAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    draft,
                    idempotencyKey.Trim(),
                    acknowledgePotentialDuplicates,
                    correlationId,
                    token),
            cancellationToken);
    }

    private static async Task<IReadOnlyList<ArtistSearchResult>> SearchCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string query,
        CancellationToken cancellationToken)
    {
        var normalized = NormalizeForMatch(query);
        var minimumLength = await ReadMinimumSearchLengthAsync(
            connection,
            transaction,
            cancellationToken);

        if (normalized.Length < minimumLength)
        {
            throw new ArtistAdministrationException(
                "catalog.artist.search.too-short",
                $"La búsqueda requiere al menos {minimumLength} caracteres.");
        }

        const string sql = """
            WITH matches AS (
                SELECT
                    a.artist_id,
                    a.canonical_name,
                    a.artist_type,
                    a.status_code,
                    aa.alias_text AS matched_text,
                    GREATEST(
                        CASE
                            WHEN aa.normalized_text = @query THEN 1.0
                            ELSE 0.0
                        END,
                        public.similarity(
                            aa.normalized_text,
                            @query
                        )
                    )::double precision AS score
                FROM catalog.artist a
                JOIN catalog.artist_alias aa
                  ON aa.artist_id = a.artist_id
                WHERE
                    aa.normalized_text = @query
                    OR position(@query in aa.normalized_text) > 0
                    OR public.similarity(
                        aa.normalized_text,
                        @query
                    ) >= @threshold

                UNION ALL

                SELECT
                    a.artist_id,
                    a.canonical_name,
                    a.artist_type,
                    a.status_code,
                    a.canonical_name AS matched_text,
                    GREATEST(
                        CASE
                            WHEN upper(btrim(a.canonical_name)) = @query
                                THEN 1.0
                            ELSE 0.0
                        END,
                        public.similarity(
                            upper(btrim(a.canonical_name)),
                            @query
                        )
                    )::double precision AS score
                FROM catalog.artist a
                WHERE
                    upper(btrim(a.canonical_name)) = @query
                    OR position(
                        @query in upper(a.canonical_name)
                    ) > 0
                    OR public.similarity(
                        upper(btrim(a.canonical_name)),
                        @query
                    ) >= @threshold
            ),
            best AS (
                SELECT DISTINCT ON (artist_id)
                    artist_id,
                    canonical_name,
                    artist_type,
                    status_code,
                    matched_text,
                    score
                FROM matches
                ORDER BY artist_id, score DESC, matched_text
            )
            SELECT
                artist_id,
                canonical_name,
                artist_type,
                status_code,
                matched_text,
                score
            FROM best
            ORDER BY score DESC, canonical_name, artist_id
            LIMIT 20;
            """;

        var results = new List<ArtistSearchResult>();
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("query", normalized);
        command.Parameters.AddWithValue(
            "threshold",
            SearchSimilarity);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(
                new ArtistSearchResult(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    Convert.ToDouble(
                        reader.GetValue(5),
                        CultureInfo.InvariantCulture)));
        }

        return results;
    }

    private static async Task<ArtistCreatedResult> CreateCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        ArtistDraft draft,
        string idempotencyKey,
        bool acknowledgePotentialDuplicates,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var prepared = PrepareDraft(draft);
        var artistId = CreateDeterministicArtistId(
            actorAccountId,
            idempotencyKey);

        var existing = await ReadExistingArtistAsync(
            connection,
            transaction,
            artistId,
            cancellationToken);

        if (existing is not null)
        {
            if (!MatchesPrepared(existing, prepared))
            {
                throw new ArtistAdministrationException(
                    "catalog.artist.idempotency-conflict",
                    "La clave de idempotencia ya se utilizó para un artista diferente.");
            }

            return ToResult(
                existing,
                duplicateWarningAcknowledged:
                    acknowledgePotentialDuplicates,
                alreadyApplied: true);
        }

        var duplicates = await FindDuplicatesAsync(
            connection,
            transaction,
            prepared,
            artistId,
            cancellationToken);

        if (duplicates.Count > 0
            && !acknowledgePotentialDuplicates)
        {
            throw new ArtistAdministrationException(
                "catalog.artist.duplicate-review-required",
                "Hay posibles duplicados. Revísalos y confirma explícitamente que la identidad debe ser distinta.",
                duplicates);
        }

        const string artistSql = """
            INSERT INTO catalog.artist (
                artist_id,
                canonical_name,
                sort_name,
                artist_type,
                status_code,
                version
            )
            VALUES (
                @artist_id,
                @canonical_name,
                @sort_name,
                @artist_type,
                'ACTIVE',
                1
            );
            """;

        await using (var command =
            new NpgsqlCommand(
                artistSql,
                connection,
                transaction))
        {
            command.Parameters.AddWithValue(
                "artist_id",
                artistId);
            command.Parameters.AddWithValue(
                "canonical_name",
                prepared.CanonicalName);
            command.Parameters.AddWithValue(
                "sort_name",
                prepared.SortName);
            command.Parameters.AddWithValue(
                "artist_type",
                prepared.ArtistType);
            await command.ExecuteNonQueryAsync(
                cancellationToken);
        }

        const string aliasSql = """
            INSERT INTO catalog.artist_alias (
                alias_id,
                artist_id,
                alias_text,
                normalized_text,
                language_tag,
                script_code,
                preferred
            )
            VALUES (
                uuidv7(),
                @artist_id,
                @alias_text,
                @normalized_text,
                @language_tag,
                @script_code,
                @preferred
            );
            """;

        foreach (var alias in prepared.Aliases)
        {
            await using var command =
                new NpgsqlCommand(
                    aliasSql,
                    connection,
                    transaction);
            command.Parameters.AddWithValue(
                "artist_id",
                artistId);
            command.Parameters.AddWithValue(
                "alias_text",
                alias.AliasText);
            command.Parameters.AddWithValue(
                "normalized_text",
                alias.NormalizedText);
            command.Parameters.AddWithValue(
                "language_tag",
                alias.LanguageTag);
            command.Parameters.AddWithValue(
                "script_code",
                alias.ScriptCode);
            command.Parameters.AddWithValue(
                "preferred",
                alias.Preferred);
            await command.ExecuteNonQueryAsync(
                cancellationToken);
        }

        await WriteAuditAsync(
            connection,
            transaction,
            actorAccountId,
            artistId,
            prepared,
            acknowledgePotentialDuplicates,
            correlationId,
            cancellationToken);

        return new ArtistCreatedResult(
            artistId,
            prepared.CanonicalName,
            prepared.ArtistType,
            "ACTIVE",
            prepared.Aliases
                .Select(static alias =>
                    new ArtistAliasDraft(
                        alias.AliasText,
                        alias.LanguageTag,
                        alias.ScriptCode,
                        alias.Preferred))
                .ToArray(),
            acknowledgePotentialDuplicates,
            AlreadyApplied: false);
    }

    private static async Task<List<ArtistDuplicateCandidate>> FindDuplicatesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        PreparedArtistDraft draft,
        Guid? excludedArtistId,
        CancellationToken cancellationToken)
    {
        var normalizedCandidates = draft.Aliases
            .Select(static alias => alias.NormalizedText)
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        const string sql = """
            WITH candidates AS (
                SELECT DISTINCT
                    unnest(@candidate_normals::text[]) AS normalized_text
            ),
            matches AS (
                SELECT
                    a.artist_id,
                    a.canonical_name,
                    a.artist_type,
                    a.status_code,
                    aa.alias_text AS matched_text,
                    GREATEST(
                        CASE
                            WHEN aa.normalized_text = c.normalized_text
                                THEN 1.0
                            ELSE 0.0
                        END,
                        public.similarity(
                            aa.normalized_text,
                            c.normalized_text
                        )
                    )::double precision AS score
                FROM catalog.artist a
                JOIN catalog.artist_alias aa
                  ON aa.artist_id = a.artist_id
                CROSS JOIN candidates c
                WHERE
                    (@excluded_id IS NULL
                        OR a.artist_id <> @excluded_id)
                    AND (
                        aa.normalized_text = c.normalized_text
                        OR public.similarity(
                            aa.normalized_text,
                            c.normalized_text
                        ) >= @threshold
                    )

                UNION ALL

                SELECT
                    a.artist_id,
                    a.canonical_name,
                    a.artist_type,
                    a.status_code,
                    a.canonical_name AS matched_text,
                    GREATEST(
                        CASE
                            WHEN upper(btrim(a.canonical_name))
                                = c.normalized_text
                                THEN 1.0
                            ELSE 0.0
                        END,
                        public.similarity(
                            upper(btrim(a.canonical_name)),
                            c.normalized_text
                        )
                    )::double precision AS score
                FROM catalog.artist a
                CROSS JOIN candidates c
                WHERE
                    (@excluded_id IS NULL
                        OR a.artist_id <> @excluded_id)
                    AND (
                        upper(btrim(a.canonical_name))
                            = c.normalized_text
                        OR public.similarity(
                            upper(btrim(a.canonical_name)),
                            c.normalized_text
                        ) >= @threshold
                    )
            ),
            best AS (
                SELECT DISTINCT ON (artist_id)
                    artist_id,
                    canonical_name,
                    artist_type,
                    status_code,
                    matched_text,
                    score
                FROM matches
                ORDER BY artist_id, score DESC, matched_text
            )
            SELECT
                artist_id,
                canonical_name,
                artist_type,
                status_code,
                matched_text,
                score
            FROM best
            ORDER BY score DESC, canonical_name, artist_id
            LIMIT 10;
            """;

        var candidates = new List<ArtistDuplicateCandidate>();
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        var candidateNormalsParameter =
            command.Parameters.Add(
                "candidate_normals",
                NpgsqlDbType.Array | NpgsqlDbType.Text);
        candidateNormalsParameter.Value =
            normalizedCandidates;

        var excludedParameter =
            command.Parameters.Add(
                "excluded_id",
                NpgsqlDbType.Uuid);
        excludedParameter.Value =
            excludedArtistId is { } value
                ? value
                : DBNull.Value;

        command.Parameters.AddWithValue(
            "threshold",
            DuplicateSimilarity);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            candidates.Add(
                new ArtistDuplicateCandidate(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    Convert.ToDouble(
                        reader.GetValue(5),
                        CultureInfo.InvariantCulture)));
        }

        return candidates;
    }

    private static async Task<ExistingArtist?> ReadExistingArtistAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid artistId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                artist_id,
                canonical_name,
                sort_name,
                artist_type,
                status_code
            FROM catalog.artist
            WHERE artist_id = @artist_id
            FOR UPDATE;
            """;

        ExistingArtist? artist = null;

        await using (var command =
            new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue(
                "artist_id",
                artistId);

            await using var reader =
                await command.ExecuteReaderAsync(
                    cancellationToken);

            if (await reader.ReadAsync(cancellationToken))
            {
                artist = new ExistingArtist(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    []);
            }
        }

        if (artist is null)
        {
            return null;
        }

        const string aliasesSql = """
            SELECT
                alias_text,
                normalized_text,
                language_tag,
                script_code,
                preferred
            FROM catalog.artist_alias
            WHERE artist_id = @artist_id
            ORDER BY language_tag, normalized_text, script_code, alias_id;
            """;

        var aliases = new List<PreparedAlias>();
        await using (var command =
            new NpgsqlCommand(
                aliasesSql,
                connection,
                transaction))
        {
            command.Parameters.AddWithValue(
                "artist_id",
                artistId);

            await using var reader =
                await command.ExecuteReaderAsync(
                    cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                aliases.Add(
                    new PreparedAlias(
                        reader.GetString(0),
                        reader.GetString(1),
                        reader.GetString(2),
                        reader.GetString(3),
                        reader.GetBoolean(4)));
            }
        }

        return artist with
        {
            Aliases = aliases
        };
    }

    private static bool MatchesPrepared(
        ExistingArtist existing,
        PreparedArtistDraft prepared)
    {
        if (!string.Equals(
                existing.CanonicalName,
                prepared.CanonicalName,
                StringComparison.Ordinal)
            || !string.Equals(
                existing.SortName,
                prepared.SortName,
                StringComparison.Ordinal)
            || !string.Equals(
                existing.ArtistType,
                prepared.ArtistType,
                StringComparison.Ordinal)
            || !string.Equals(
                existing.StatusCode,
                "ACTIVE",
                StringComparison.Ordinal))
        {
            return false;
        }

        var existingAliases = existing.Aliases
            .Select(AliasFingerprint)
            .Order(StringComparer.Ordinal)
            .ToArray();

        var preparedAliases = prepared.Aliases
            .Select(AliasFingerprint)
            .Order(StringComparer.Ordinal)
            .ToArray();

        return existingAliases.SequenceEqual(
            preparedAliases,
            StringComparer.Ordinal);
    }

    private static string AliasFingerprint(
        PreparedAlias alias) =>
        string.Join(
            "\u001f",
            alias.AliasText,
            alias.NormalizedText,
            alias.LanguageTag,
            alias.ScriptCode,
            alias.Preferred
                ? "1"
                : "0");

    private static PreparedArtistDraft PrepareDraft(
        ArtistDraft draft)
    {
        var canonicalName = NormalizeDisplayText(
            draft.CanonicalName,
            "Nombre canónico");
        var sortName = string.IsNullOrWhiteSpace(
                draft.SortName)
            ? canonicalName
            : NormalizeDisplayText(
                draft.SortName,
                "Nombre de ordenación");

        var artistType = NormalizeCode(
            draft.ArtistType,
            "Tipo de artista");
        var languageTag = NormalizeLanguageTag(
            draft.CanonicalLanguageTag);
        var scriptCode = NormalizeCode(
            draft.CanonicalScriptCode,
            "Sistema de escritura");

        if (draft.Aliases.Count > MaxAliasCount)
        {
            throw new ArtistAdministrationException(
                "catalog.artist.aliases.too-many",
                $"No se admiten más de {MaxAliasCount} formas de nombre en una sola alta.");
        }

        var preparedAliases = new List<PreparedAlias>
        {
            new(
                canonicalName,
                NormalizeForMatch(canonicalName),
                languageTag,
                scriptCode,
                Preferred: true)
        };

        foreach (var alias in draft.Aliases)
        {
            var aliasText = NormalizeDisplayText(
                alias.AliasText,
                "Alias");
            preparedAliases.Add(
                new PreparedAlias(
                    aliasText,
                    NormalizeForMatch(aliasText),
                    NormalizeLanguageTag(
                        alias.LanguageTag),
                    NormalizeCode(
                        alias.ScriptCode,
                        "Sistema de escritura del alias"),
                    alias.Preferred));
        }

        var deduplicated = preparedAliases
            .GroupBy(
                static alias =>
                    $"{alias.NormalizedText}\u001f{alias.LanguageTag}",
                StringComparer.Ordinal)
            .Select(static group =>
            {
                var first = group.First();
                return first with
                {
                    Preferred =
                        group.Any(static alias =>
                            alias.Preferred)
                };
            })
            .ToList();

        var duplicatePreferredLanguage =
            deduplicated
                .Where(static alias => alias.Preferred)
                .GroupBy(
                    static alias => alias.LanguageTag,
                    StringComparer.OrdinalIgnoreCase)
                .FirstOrDefault(
                    static group => group.Count() > 1);

        if (duplicatePreferredLanguage is not null)
        {
            throw new ArtistAdministrationException(
                "catalog.artist.alias.preferred-conflict",
                $"Solo puede existir una forma preferida para el idioma {duplicatePreferredLanguage.Key}.");
        }

        return new PreparedArtistDraft(
            canonicalName,
            sortName,
            artistType,
            deduplicated);
    }

    private static string NormalizeDisplayText(
        string value,
        string label)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArtistAdministrationException(
                "catalog.artist.text.required",
                $"{label} es obligatorio.");
        }

        var normalized = WhitespacePattern().Replace(
            value.Normalize(NormalizationForm.FormC).Trim(),
            " ");

        if (normalized.Length > MaxTextLength)
        {
            throw new ArtistAdministrationException(
                "catalog.artist.text.too-long",
                $"{label} supera {MaxTextLength} caracteres.");
        }

        return normalized;
    }

    private static string NormalizeForMatch(
        string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        return WhitespacePattern().Replace(
                value.Normalize(NormalizationForm.FormKC).Trim(),
                " ")
            .ToUpperInvariant();
    }

    private static string NormalizeCode(
        string value,
        string label)
    {
        var code = value?.Trim().ToUpperInvariant()
            ?? string.Empty;

        if (!CodePattern().IsMatch(code))
        {
            throw new ArtistAdministrationException(
                "catalog.artist.code.invalid",
                $"{label} no cumple el formato canónico.");
        }

        return code;
    }

    private static string NormalizeLanguageTag(
        string value)
    {
        var languageTag = value?.Trim().ToUpperInvariant()
            ?? string.Empty;

        if (!LanguageTagPattern().IsMatch(languageTag))
        {
            throw new ArtistAdministrationException(
                "catalog.artist.language.invalid",
                "La etiqueta de idioma no cumple el formato BCP-47 admitido.");
        }

        return languageTag;
    }

    private static async Task<int> ReadMinimumSearchLengthAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT typed_value #>> '{}'
            FROM configuration.effective_parameter
            WHERE parameter_key = 'SEARCH_MIN_QUERY_LENGTH'
              AND scope_code = 'GLOBAL'
              AND scope_value IS NULL
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        var result =
            await command.ExecuteScalarAsync(
                cancellationToken);

        return int.TryParse(
                Convert.ToString(
                    result,
                    CultureInfo.InvariantCulture),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var minimum)
            && minimum is >= 1 and <= 64
                ? minimum
                : 2;
    }

    private static Guid CreateDeterministicArtistId(
        Guid actorAccountId,
        string idempotencyKey)
    {
        var material =
            $"{actorAccountId:D}\nCATALOG.ARTIST.CREATE\n{idempotencyKey}";
        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(material));

        Span<byte> bytes = stackalloc byte[16];
        digest.AsSpan(0, 16).CopyTo(bytes);

        bytes[6] =
            (byte)((bytes[6] & 0x0f) | 0x50);
        bytes[8] =
            (byte)((bytes[8] & 0x3f) | 0x80);

        var id = new Guid(bytes);
        if (id == Guid.Empty)
        {
            throw new InvalidOperationException(
                "No se pudo derivar una identidad estable.");
        }

        return id;
    }

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid artistId,
        PreparedArtistDraft prepared,
        bool duplicateWarningAcknowledged,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var roleCode = await ReadAuditRoleCodeAsync(
            connection,
            transaction,
            actorAccountId,
            cancellationToken);

        var afterDigest = SHA256.HashData(
            Encoding.UTF8.GetBytes(
                RequestFingerprint(prepared)));

        const string sql = """
            INSERT INTO security.audit_event (
                actor_id,
                role_code,
                object_type,
                object_id,
                action_code,
                before_digest,
                after_digest,
                reason,
                occurred_at,
                correlation_id
            )
            VALUES (
                @actor_id,
                @role_code,
                'ARTIST',
                @artist_id,
                'CATALOG.ARTIST.CREATE',
                NULL,
                @after_digest,
                @reason,
                CURRENT_TIMESTAMP,
                @correlation_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "actor_id",
            actorAccountId);
        command.Parameters.AddWithValue(
            "role_code",
            roleCode);
        command.Parameters.AddWithValue(
            "artist_id",
            artistId);
        command.Parameters.AddWithValue(
            "after_digest",
            afterDigest);
        command.Parameters.AddWithValue(
            "reason",
            duplicateWarningAcknowledged
                ? "Alta editorial de artista; posibles duplicados revisados explícitamente."
                : "Alta editorial de artista; no se detectaron duplicados potenciales.");
        command.Parameters.AddWithValue(
            "correlation_id",
            CorrelationGuid(correlationId));

        await command.ExecuteNonQueryAsync(
            cancellationToken);
    }

    private static async Task<string> ReadAuditRoleCodeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT r.role_code
            FROM security.role_assignment a
            JOIN security.role r
              ON r.role_id = a.role_id
            JOIN security.role_permission rp
              ON rp.role_id = r.role_id
            JOIN security.permission p
              ON p.permission_id = rp.permission_id
            WHERE a.account_id = @actor_id
              AND p.permission_code = 'EDITORIAL.DRAFT'
              AND r.status_code = 'ACTIVE'
              AND a.valid_from <= CURRENT_TIMESTAMP
              AND (a.valid_to IS NULL
                   OR a.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL
                   OR rp.valid_to > CURRENT_TIMESTAMP)
            ORDER BY r.role_code
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "actor_id",
            actorAccountId);

        var value =
            await command.ExecuteScalarAsync(
                cancellationToken);

        if (value is not string roleCode
            || string.IsNullOrWhiteSpace(roleCode))
        {
            throw new ArtistAdministrationException(
                "catalog.artist.audit-role.missing",
                "No se pudo resolver la función editorial vigente para la auditoría.");
        }

        return roleCode;
    }

    private static string RequestFingerprint(
        PreparedArtistDraft prepared)
    {
        var builder = new StringBuilder();
        builder.Append(prepared.CanonicalName);
        builder.Append('\n');
        builder.Append(prepared.SortName);
        builder.Append('\n');
        builder.Append(prepared.ArtistType);

        foreach (var alias in prepared.Aliases
            .OrderBy(AliasFingerprint, StringComparer.Ordinal))
        {
            builder.Append('\n');
            builder.Append(AliasFingerprint(alias));
        }

        return builder.ToString();
    }

    private static Guid CorrelationGuid(
        string correlationId)
    {
        if (Guid.TryParse(
                correlationId,
                out var parsed)
            && parsed != Guid.Empty)
        {
            return parsed;
        }

        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(correlationId));
        Span<byte> bytes = stackalloc byte[16];
        digest.AsSpan(0, 16).CopyTo(bytes);
        return new Guid(bytes);
    }

    private static ArtistCreatedResult ToResult(
        ExistingArtist artist,
        bool duplicateWarningAcknowledged,
        bool alreadyApplied) =>
        new(
            artist.ArtistId,
            artist.CanonicalName,
            artist.ArtistType,
            artist.StatusCode,
            artist.Aliases
                .Select(static alias =>
                    new ArtistAliasDraft(
                        alias.AliasText,
                        alias.LanguageTag,
                        alias.ScriptCode,
                        alias.Preferred))
                .ToArray(),
            duplicateWarningAcknowledged,
            alreadyApplied);

    private sealed record PreparedAlias(
        string AliasText,
        string NormalizedText,
        string LanguageTag,
        string ScriptCode,
        bool Preferred);

    private sealed record PreparedArtistDraft(
        string CanonicalName,
        string SortName,
        string ArtistType,
        List<PreparedAlias> Aliases);

    private sealed record ExistingArtist(
        Guid ArtistId,
        string CanonicalName,
        string SortName,
        string ArtistType,
        string StatusCode,
        List<PreparedAlias> Aliases);
}
