using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Administration;

public sealed record SongDraftInput(
    Guid ArtistId,
    string CanonicalTitle,
    string LanguageTag,
    string? RecordingTitle,
    long? RecordingDurationMs,
    string YouTubeReference,
    long? SourceDurationMs,
    long OffsetMs,
    bool ExactRecordingConfirmed);

public sealed record SongDraftDuplicateCandidate(
    Guid RecordingId,
    Guid WorkId,
    Guid ArtistId,
    string ArtistName,
    string CanonicalTitle,
    string? RecordingTitle,
    string? ExternalRef,
    double Similarity,
    bool ExactSourceMatch);

public sealed record SongDraftDuplicateReview(
    IReadOnlyList<SongDraftDuplicateCandidate> Candidates,
    bool RequiresAcknowledgement,
    bool HasExactSourceConflict);

public sealed record SongDraftCreatedResult(
    Guid WorkId,
    Guid RecordingId,
    Guid SourceId,
    Guid ArtistId,
    string CanonicalTitle,
    string? RecordingTitle,
    string ProviderCode,
    string ExternalRef,
    string StatusCode,
    bool DuplicateWarningAcknowledged,
    bool AlreadyApplied);

public sealed record SongDraftDetails(
    Guid WorkId,
    Guid RecordingId,
    Guid SourceId,
    Guid ArtistId,
    string ArtistName,
    string CanonicalTitle,
    string LanguageTag,
    string? RecordingTitle,
    long? RecordingDurationMs,
    string ProviderCode,
    string ExternalRef,
    long? SourceDurationMs,
    long OffsetMs,
    string WorkStatusCode,
    string RecordingStatusCode,
    string SourceStatusCode);

public sealed class SongDraftAdministrationException(
    string code,
    string message,
    IReadOnlyList<SongDraftDuplicateCandidate>? duplicates = null)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;

    public IReadOnlyList<SongDraftDuplicateCandidate> Duplicates { get; } =
        duplicates ?? [];
}

public sealed partial class SongDraftAdministrationService(
    ISongDraftAdministrationTransactionExecutor transactionExecutor)
{
    private const int MaxTextLength = 512;
    private const double DuplicateSimilarity = 0.72;
    private const string ProviderCode = "YOUTUBE";
    private const string DraftStatus = "DRAFT";
    private const string PrimaryArtistRole = "PRIMARY";
    private const string OriginalTitleType = "ORIGINAL";

    [GeneratedRegex(
        "^[A-Za-z0-9_-]{11}$",
        RegexOptions.CultureInvariant)]
    private static partial Regex YouTubeVideoIdPattern();

    [GeneratedRegex(
        "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex LanguageTagPattern();

    [GeneratedRegex(
        "\\s+",
        RegexOptions.CultureInvariant)]
    private static partial Regex WhitespacePattern();

    public Task<SongDraftDuplicateReview> CheckDuplicatesAsync(
        Guid actorAccountId,
        SongDraftInput input,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                var prepared = Prepare(input);
                await EnsureArtistExistsAsync(
                    connection,
                    transaction,
                    prepared.ArtistId,
                    token);

                var candidates = await FindDuplicatesAsync(
                    connection,
                    transaction,
                    prepared,
                    excludedRecordingId: null,
                    token);

                return new SongDraftDuplicateReview(
                    candidates,
                    candidates.Any(static candidate => !candidate.ExactSourceMatch),
                    candidates.Any(static candidate => candidate.ExactSourceMatch));
            },
            cancellationToken);
    }

    public Task<SongDraftCreatedResult> CreateAsync(
        Guid actorAccountId,
        SongDraftInput input,
        string idempotencyKey,
        bool acknowledgePotentialDuplicates,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);

        if (string.IsNullOrWhiteSpace(idempotencyKey)
            || idempotencyKey.Trim().Length > 128)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.idempotency-key.invalid",
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
                    input,
                    idempotencyKey.Trim(),
                    acknowledgePotentialDuplicates,
                    correlationId,
                    token),
            cancellationToken);
    }

    public Task<SongDraftDetails> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (recordingId == Guid.Empty)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.recording.invalid",
                "La grabación solicitada no es válida.");
        }

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                var result = await ReadDetailsAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                return result
                    ?? throw new SongDraftAdministrationException(
                        "catalog.song-draft.not-found",
                        "No existe un borrador de canción con ese identificador.");
            },
            cancellationToken);
    }

    private static async Task<SongDraftCreatedResult> CreateCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        SongDraftInput input,
        string idempotencyKey,
        bool acknowledgePotentialDuplicates,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var prepared = Prepare(input);

        await AcquireLockAsync(
            connection,
            transaction,
            $"SONG-DRAFT:IDEMPOTENCY:{actorAccountId:D}:{idempotencyKey}",
            cancellationToken);
        await AcquireLockAsync(
            connection,
            transaction,
            $"SONG-DRAFT:TITLE:{prepared.ArtistId:D}:{prepared.NormalizedTitle}",
            cancellationToken);
        await AcquireLockAsync(
            connection,
            transaction,
            $"SONG-DRAFT:YOUTUBE:{prepared.ExternalRef}",
            cancellationToken);

        await EnsureArtistExistsAsync(
            connection,
            transaction,
            prepared.ArtistId,
            cancellationToken);

        var workId = CreateDeterministicId(
            actorAccountId,
            idempotencyKey,
            "WORK");
        var recordingId = CreateDeterministicId(
            actorAccountId,
            idempotencyKey,
            "RECORDING");
        var sourceId = CreateDeterministicId(
            actorAccountId,
            idempotencyKey,
            "SOURCE");

        var existing = await ReadExistingAsync(
            connection,
            transaction,
            recordingId,
            prepared.ArtistId,
            cancellationToken);

        if (existing is not null)
        {
            if (!Matches(existing, prepared))
            {
                throw new SongDraftAdministrationException(
                    "catalog.song-draft.idempotency-conflict",
                    "La clave de idempotencia ya se utilizó para un borrador diferente.");
            }

            return ToCreatedResult(
                existing,
                duplicateWarningAcknowledged:
                    acknowledgePotentialDuplicates,
                alreadyApplied: true);
        }

        var duplicates = await FindDuplicatesAsync(
            connection,
            transaction,
            prepared,
            recordingId,
            cancellationToken);

        var exactSource = duplicates
            .Where(static candidate => candidate.ExactSourceMatch)
            .ToArray();

        if (exactSource.Length > 0)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.youtube-source-conflict",
                "La referencia de YouTube ya pertenece a otra grabación. Debe reutilizarse o resolverse antes de continuar.",
                exactSource);
        }

        if (duplicates.Count > 0
            && !acknowledgePotentialDuplicates)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.duplicate-review-required",
                "Hay posibles grabaciones duplicadas. Revísalas y confirma explícitamente que se trata de una versión distinta.",
                duplicates);
        }

        await InsertWorkAsync(
            connection,
            transaction,
            workId,
            prepared,
            cancellationToken);

        await InsertWorkTitleAsync(
            connection,
            transaction,
            CreateDeterministicId(
                actorAccountId,
                idempotencyKey,
                "WORK-TITLE"),
            workId,
            prepared,
            cancellationToken);

        await InsertWorkArtistAsync(
            connection,
            transaction,
            workId,
            prepared.ArtistId,
            cancellationToken);

        await InsertRecordingAsync(
            connection,
            transaction,
            recordingId,
            workId,
            prepared,
            cancellationToken);

        await InsertSourceAsync(
            connection,
            transaction,
            sourceId,
            recordingId,
            prepared,
            cancellationToken);

        await InsertInitialStatusHistoryAsync(
            connection,
            transaction,
            CreateDeterministicId(
                actorAccountId,
                idempotencyKey,
                "STATUS-HISTORY"),
            recordingId,
            actorAccountId,
            cancellationToken);

        await WriteAuditAsync(
            connection,
            transaction,
            actorAccountId,
            recordingId,
            prepared,
            acknowledgePotentialDuplicates,
            correlationId,
            cancellationToken);

        return new SongDraftCreatedResult(
            workId,
            recordingId,
            sourceId,
            prepared.ArtistId,
            prepared.CanonicalTitle,
            prepared.RecordingTitle,
            ProviderCode,
            prepared.ExternalRef,
            DraftStatus,
            acknowledgePotentialDuplicates,
            AlreadyApplied: false);
    }

    private static async Task AcquireLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string lockKey,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended(@lock_key, 0)
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "lock_key",
            lockKey);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task EnsureArtistExistsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid artistId,
        CancellationToken cancellationToken)
    {
        if (artistId == Guid.Empty)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.artist.invalid",
                "Debe seleccionarse una identidad de artista válida.");
        }

        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.artist
                WHERE artist_id = @artist_id
                  AND status_code = 'ACTIVE'
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "artist_id",
            NpgsqlDbType.Uuid,
            artistId);

        var exists = (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);

        if (!exists)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.artist.not-found",
                "El artista seleccionado no existe o no está activo.");
        }
    }

    private static async Task<List<SongDraftDuplicateCandidate>> FindDuplicatesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        PreparedSongDraft prepared,
        Guid? excludedRecordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                r.recording_id,
                w.work_id,
                wa.artist_id,
                a.canonical_name,
                w.canonical_title,
                r.recording_title,
                (
                    SELECT rs.external_ref
                    FROM catalog.recording_source rs
                    WHERE rs.recording_id = r.recording_id
                    ORDER BY
                        CASE WHEN rs.external_ref = @external_ref THEN 0 ELSE 1 END,
                        rs.source_id
                    LIMIT 1
                ) AS external_ref,
                public.similarity(
                    upper(btrim(w.canonical_title)),
                    @normalized_title
                )::double precision AS similarity,
                EXISTS (
                    SELECT 1
                    FROM catalog.recording_source exact_rs
                    WHERE exact_rs.recording_id = r.recording_id
                      AND exact_rs.provider_code = 'YOUTUBE'
                      AND exact_rs.external_ref = @external_ref
                ) AS exact_source
            FROM catalog.recording r
            JOIN catalog.musical_work w
              ON w.work_id = r.work_id
            JOIN catalog.work_artist wa
              ON wa.work_id = w.work_id
             AND wa.role_code = 'PRIMARY'
             AND wa.display_order = 0
            JOIN catalog.artist a
              ON a.artist_id = wa.artist_id
            WHERE
                (@excluded_recording_id IS NULL
                    OR r.recording_id <> @excluded_recording_id)
                AND (
                    EXISTS (
                        SELECT 1
                        FROM catalog.recording_source exact_rs
                        WHERE exact_rs.recording_id = r.recording_id
                          AND exact_rs.provider_code = 'YOUTUBE'
                          AND exact_rs.external_ref = @external_ref
                    )
                    OR (
                        wa.artist_id = @artist_id
                        AND public.similarity(
                            upper(btrim(w.canonical_title)),
                            @normalized_title
                        ) >= @threshold
                    )
                )
            ORDER BY
                exact_source DESC,
                similarity DESC,
                w.canonical_title,
                r.recording_id
            LIMIT 10;
            """;

        var candidates = new List<SongDraftDuplicateCandidate>();
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "external_ref",
            prepared.ExternalRef);
        command.Parameters.AddWithValue(
            "normalized_title",
            prepared.NormalizedTitle);
        command.Parameters.AddWithValue(
            "artist_id",
            NpgsqlDbType.Uuid,
            prepared.ArtistId);
        command.Parameters.AddWithValue(
            "threshold",
            DuplicateSimilarity);

        var excludedParameter = command.Parameters.Add(
            "excluded_recording_id",
            NpgsqlDbType.Uuid);
        excludedParameter.Value = excludedRecordingId is { } id
            ? id
            : DBNull.Value;

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            candidates.Add(
                new SongDraftDuplicateCandidate(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetGuid(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetString(5),
                    reader.IsDBNull(6) ? null : reader.GetString(6),
                    Convert.ToDouble(
                        reader.GetValue(7),
                        CultureInfo.InvariantCulture),
                    reader.GetBoolean(8)));
        }

        return candidates;
    }

    private static async Task InsertWorkAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid workId,
        PreparedSongDraft prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO catalog.musical_work (
                work_id,
                canonical_title,
                language_tag,
                release_date,
                status_code,
                version
            )
            VALUES (
                @work_id,
                @canonical_title,
                @language_tag,
                NULL,
                'DRAFT',
                1
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("work_id", workId);
        command.Parameters.AddWithValue(
            "canonical_title",
            prepared.CanonicalTitle);
        command.Parameters.AddWithValue(
            "language_tag",
            prepared.LanguageTag);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertWorkTitleAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid workTitleId,
        Guid workId,
        PreparedSongDraft prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO catalog.work_title (
                work_title_id,
                work_id,
                title_text,
                normalized_text,
                language_tag,
                title_type,
                preferred
            )
            VALUES (
                @work_title_id,
                @work_id,
                @title_text,
                @normalized_text,
                @language_tag,
                'ORIGINAL',
                true
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "work_title_id",
            workTitleId);
        command.Parameters.AddWithValue(
            "work_id",
            workId);
        command.Parameters.AddWithValue(
            "title_text",
            prepared.CanonicalTitle);
        command.Parameters.AddWithValue(
            "normalized_text",
            prepared.NormalizedTitle);
        command.Parameters.AddWithValue(
            "language_tag",
            prepared.LanguageTag);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertWorkArtistAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid workId,
        Guid artistId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO catalog.work_artist (
                work_id,
                artist_id,
                role_code,
                display_order
            )
            VALUES (
                @work_id,
                @artist_id,
                'PRIMARY',
                0
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("work_id", workId);
        command.Parameters.AddWithValue("artist_id", artistId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertRecordingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid workId,
        PreparedSongDraft prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO catalog.recording (
                recording_id,
                work_id,
                recording_title,
                duration_ms,
                release_date,
                status_code,
                version
            )
            VALUES (
                @recording_id,
                @work_id,
                @recording_title,
                @duration_ms,
                NULL,
                'DRAFT',
                1
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            recordingId);
        command.Parameters.AddWithValue(
            "work_id",
            workId);
        command.Parameters.Add(
            new NpgsqlParameter(
                "recording_title",
                NpgsqlDbType.Text)
            {
                Value = prepared.RecordingTitle is { } title
                    ? title
                    : DBNull.Value
            });
        command.Parameters.Add(
            new NpgsqlParameter(
                "duration_ms",
                NpgsqlDbType.Bigint)
            {
                Value = prepared.RecordingDurationMs is { } duration
                    ? duration
                    : DBNull.Value
            });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertSourceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid sourceId,
        Guid recordingId,
        PreparedSongDraft prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO catalog.recording_source (
                source_id,
                recording_id,
                provider_code,
                external_ref,
                duration_ms,
                offset_ms,
                status_code,
                version
            )
            VALUES (
                @source_id,
                @recording_id,
                'YOUTUBE',
                @external_ref,
                @duration_ms,
                @offset_ms,
                'DRAFT',
                1
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "source_id",
            sourceId);
        command.Parameters.AddWithValue(
            "recording_id",
            recordingId);
        command.Parameters.AddWithValue(
            "external_ref",
            prepared.ExternalRef);
        command.Parameters.Add(
            new NpgsqlParameter(
                "duration_ms",
                NpgsqlDbType.Bigint)
            {
                Value = prepared.SourceDurationMs is { } duration
                    ? duration
                    : DBNull.Value
            });
        command.Parameters.AddWithValue(
            "offset_ms",
            prepared.OffsetMs);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertInitialStatusHistoryAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid historyId,
        Guid recordingId,
        Guid actorAccountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO catalog.recording_status_history (
                history_id,
                recording_id,
                from_status,
                to_status,
                changed_at,
                changed_by,
                reason
            )
            VALUES (
                @history_id,
                @recording_id,
                NULL,
                'DRAFT',
                CURRENT_TIMESTAMP,
                @actor_id,
                'Alta editorial inicial de obra, grabación y fuente de YouTube.'
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "history_id",
            historyId);
        command.Parameters.AddWithValue(
            "recording_id",
            recordingId);
        command.Parameters.AddWithValue(
            "actor_id",
            actorAccountId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<ExistingSongDraft?> ReadExistingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid artistId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                w.work_id,
                r.recording_id,
                rs.source_id,
                wa.artist_id,
                w.canonical_title,
                w.language_tag,
                r.recording_title,
                r.duration_ms,
                rs.provider_code,
                rs.external_ref,
                rs.duration_ms,
                rs.offset_ms,
                w.status_code,
                r.status_code,
                rs.status_code
            FROM catalog.recording r
            JOIN catalog.musical_work w
              ON w.work_id = r.work_id
            JOIN catalog.work_artist wa
              ON wa.work_id = w.work_id
             AND wa.artist_id = @artist_id
             AND wa.role_code = 'PRIMARY'
             AND wa.display_order = 0
            JOIN catalog.recording_source rs
              ON rs.recording_id = r.recording_id
            WHERE r.recording_id = @recording_id
            ORDER BY rs.source_id
            LIMIT 1
            FOR UPDATE OF r, w, rs;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            recordingId);
        command.Parameters.AddWithValue(
            "artist_id",
            artistId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new ExistingSongDraft(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2),
            reader.GetGuid(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetInt64(7),
            reader.GetString(8),
            reader.GetString(9),
            reader.IsDBNull(10) ? null : reader.GetInt64(10),
            reader.GetInt64(11),
            reader.GetString(12),
            reader.GetString(13),
            reader.GetString(14));
    }

    private static async Task<SongDraftDetails?> ReadDetailsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                w.work_id,
                r.recording_id,
                rs.source_id,
                a.artist_id,
                a.canonical_name,
                w.canonical_title,
                w.language_tag,
                r.recording_title,
                r.duration_ms,
                rs.provider_code,
                rs.external_ref,
                rs.duration_ms,
                rs.offset_ms,
                w.status_code,
                r.status_code,
                rs.status_code
            FROM catalog.recording r
            JOIN catalog.musical_work w
              ON w.work_id = r.work_id
            JOIN catalog.work_artist wa
              ON wa.work_id = w.work_id
             AND wa.role_code = 'PRIMARY'
             AND wa.display_order = 0
            JOIN catalog.artist a
              ON a.artist_id = wa.artist_id
            JOIN catalog.recording_source rs
              ON rs.recording_id = r.recording_id
            WHERE r.recording_id = @recording_id
            ORDER BY a.artist_id, rs.source_id
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new SongDraftDetails(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2),
            reader.GetGuid(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetString(7),
            reader.IsDBNull(8) ? null : reader.GetInt64(8),
            reader.GetString(9),
            reader.GetString(10),
            reader.IsDBNull(11) ? null : reader.GetInt64(11),
            reader.GetInt64(12),
            reader.GetString(13),
            reader.GetString(14),
            reader.GetString(15));
    }

    private static bool Matches(
        ExistingSongDraft existing,
        PreparedSongDraft prepared)
    {
        return existing.ArtistId == prepared.ArtistId
            && string.Equals(
                existing.CanonicalTitle,
                prepared.CanonicalTitle,
                StringComparison.Ordinal)
            && string.Equals(
                existing.LanguageTag,
                prepared.LanguageTag,
                StringComparison.Ordinal)
            && string.Equals(
                existing.RecordingTitle,
                prepared.RecordingTitle,
                StringComparison.Ordinal)
            && existing.RecordingDurationMs
                == prepared.RecordingDurationMs
            && string.Equals(
                existing.ProviderCode,
                ProviderCode,
                StringComparison.Ordinal)
            && string.Equals(
                existing.ExternalRef,
                prepared.ExternalRef,
                StringComparison.Ordinal)
            && existing.SourceDurationMs
                == prepared.SourceDurationMs
            && existing.OffsetMs == prepared.OffsetMs
            && string.Equals(
                existing.WorkStatusCode,
                DraftStatus,
                StringComparison.Ordinal)
            && string.Equals(
                existing.RecordingStatusCode,
                DraftStatus,
                StringComparison.Ordinal)
            && string.Equals(
                existing.SourceStatusCode,
                DraftStatus,
                StringComparison.Ordinal);
    }

    private static PreparedSongDraft Prepare(
        SongDraftInput input)
    {
        if (input.ArtistId == Guid.Empty)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.artist.invalid",
                "Debe seleccionarse una identidad de artista válida.");
        }

        if (!input.ExactRecordingConfirmed)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.correspondence.required",
                "Debe confirmarse que la referencia de YouTube corresponde exactamente a la grabación registrada.");
        }

        var canonicalTitle = NormalizeDisplayText(
            input.CanonicalTitle,
            "Título original de la obra");
        var languageTag = NormalizeLanguageTag(
            input.LanguageTag);
        var recordingTitle = NormalizeOptionalDisplayText(
            input.RecordingTitle,
            "Título de la grabación");

        ValidateDuration(
            input.RecordingDurationMs,
            "Duración de referencia de la grabación");
        ValidateDuration(
            input.SourceDurationMs,
            "Duración de la fuente");

        if (input.OffsetMs < 0)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.offset.invalid",
                "El desplazamiento de la fuente no puede ser negativo.");
        }

        if (input.SourceDurationMs is { } sourceDuration
            && input.OffsetMs >= sourceDuration)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.offset.out-of-range",
                "El desplazamiento debe ser menor que la duración conocida de la fuente.");
        }

        var externalRef = NormalizeYouTubeReference(
            input.YouTubeReference);

        return new PreparedSongDraft(
            input.ArtistId,
            canonicalTitle,
            NormalizeForMatch(canonicalTitle),
            languageTag,
            recordingTitle,
            input.RecordingDurationMs,
            externalRef,
            input.SourceDurationMs,
            input.OffsetMs);
    }

    private static string NormalizeYouTubeReference(
        string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.youtube.required",
                "La referencia de YouTube es obligatoria.");
        }

        var trimmed = value.Trim();
        if (YouTubeVideoIdPattern().IsMatch(trimmed))
        {
            return trimmed;
        }

        if (!Uri.TryCreate(
                trimmed,
                UriKind.Absolute,
                out var uri)
            || !string.Equals(
                uri.Scheme,
                Uri.UriSchemeHttps,
                StringComparison.OrdinalIgnoreCase)
            || !uri.IsDefaultPort
            || !string.IsNullOrEmpty(uri.UserInfo))
        {
            throw InvalidYouTubeReference();
        }

        var host = uri.Host.TrimEnd('.').ToLowerInvariant();
        string? candidate = null;

        if (host is "youtu.be" or "www.youtu.be")
        {
            var segments = PathSegments(uri);
            if (segments.Length == 1)
            {
                candidate = segments[0];
            }
        }
        else if (host is "youtube.com"
            or "www.youtube.com"
            or "m.youtube.com"
            or "music.youtube.com")
        {
            var segments = PathSegments(uri);
            if (segments.Length == 1
                && string.Equals(
                    segments[0],
                    "watch",
                    StringComparison.OrdinalIgnoreCase))
            {
                candidate = QueryValue(uri.Query, "v");
            }
            else if (segments.Length == 2
                && (string.Equals(
                        segments[0],
                        "embed",
                        StringComparison.OrdinalIgnoreCase)
                    || string.Equals(
                        segments[0],
                        "shorts",
                        StringComparison.OrdinalIgnoreCase)))
            {
                candidate = segments[1];
            }
        }
        else if (host is "youtube-nocookie.com"
            or "www.youtube-nocookie.com")
        {
            var segments = PathSegments(uri);
            if (segments.Length == 2
                && string.Equals(
                    segments[0],
                    "embed",
                    StringComparison.OrdinalIgnoreCase))
            {
                candidate = segments[1];
            }
        }

        candidate = candidate?.Trim();
        if (candidate is null
            || !YouTubeVideoIdPattern().IsMatch(candidate))
        {
            throw InvalidYouTubeReference();
        }

        return candidate;
    }

    private static string[] PathSegments(
        Uri uri) =>
        uri.AbsolutePath
            .Split(
                '/',
                StringSplitOptions.RemoveEmptyEntries
                    | StringSplitOptions.TrimEntries)
            .Select(Uri.UnescapeDataString)
            .ToArray();

    private static string? QueryValue(
        string query,
        string key)
    {
        foreach (var part in query.TrimStart('?')
            .Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var pair = part.Split('=', 2);
            if (pair.Length == 2
                && string.Equals(
                    Uri.UnescapeDataString(pair[0]),
                    key,
                    StringComparison.Ordinal))
            {
                return Uri.UnescapeDataString(pair[1]);
            }
        }

        return null;
    }

    private static SongDraftAdministrationException InvalidYouTubeReference() =>
        new(
            "catalog.song-draft.youtube.invalid",
            "Usa un identificador de video válido o una URL HTTPS de YouTube admitida. No se consultan servicios externos para completar la referencia.");

    private static string NormalizeDisplayText(
        string value,
        string label)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.text.required",
                $"{label} es obligatorio.");
        }

        var normalized = WhitespacePattern().Replace(
            value.Normalize(NormalizationForm.FormC).Trim(),
            " ");

        if (normalized.Length > MaxTextLength)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.text.too-long",
                $"{label} supera {MaxTextLength} caracteres.");
        }

        return normalized;
    }

    private static string? NormalizeOptionalDisplayText(
        string? value,
        string label)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return NormalizeDisplayText(value, label);
    }

    private static string NormalizeForMatch(
        string value) =>
        WhitespacePattern().Replace(
                value.Normalize(NormalizationForm.FormKC).Trim(),
                " ")
            .ToUpperInvariant();

    private static string NormalizeLanguageTag(
        string value)
    {
        var languageTag = value?.Trim()
            ?? string.Empty;

        if (!LanguageTagPattern().IsMatch(languageTag))
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.language.invalid",
                "La etiqueta de idioma no cumple el formato BCP-47 admitido.");
        }

        return languageTag;
    }

    private static void ValidateDuration(
        long? value,
        string label)
    {
        if (value.HasValue
            && value.Value <= 0)
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.duration.invalid",
                $"{label} debe ser positiva cuando se informa.");
        }
    }

    private static Guid CreateDeterministicId(
        Guid actorAccountId,
        string idempotencyKey,
        string kind)
    {
        var material =
            $"{actorAccountId:D}\nCATALOG.SONG_DRAFT.CREATE\n{idempotencyKey}\n{kind}";
        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(material));

        Span<byte> bytes = stackalloc byte[16];
        digest.AsSpan(0, 16).CopyTo(bytes);

        bytes[6] =
            (byte)((bytes[6] & 0x0f) | 0x50);
        bytes[8] =
            (byte)((bytes[8] & 0x3f) | 0x80);

        var id = new Guid(bytes);
        return id != Guid.Empty
            ? id
            : throw new InvalidOperationException(
                "No se pudo derivar una identidad estable.");
    }

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        PreparedSongDraft prepared,
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
                'RECORDING',
                @recording_id,
                'CATALOG.SONG_DRAFT.CREATE',
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
            "recording_id",
            recordingId);
        command.Parameters.AddWithValue(
            "after_digest",
            afterDigest);
        command.Parameters.AddWithValue(
            "reason",
            duplicateWarningAcknowledged
                ? "Alta editorial de obra, grabación y fuente; posibles duplicados revisados explícitamente."
                : "Alta editorial de obra, grabación y fuente; sin duplicados potenciales pendientes.");
        command.Parameters.AddWithValue(
            "correlation_id",
            CorrelationGuid(correlationId));

        await command.ExecuteNonQueryAsync(cancellationToken);
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
            await command.ExecuteScalarAsync(cancellationToken);

        if (value is not string roleCode
            || string.IsNullOrWhiteSpace(roleCode))
        {
            throw new SongDraftAdministrationException(
                "catalog.song-draft.audit-role.missing",
                "No se pudo resolver la función editorial vigente para la auditoría.");
        }

        return roleCode;
    }

    private static string RequestFingerprint(
        PreparedSongDraft prepared) =>
        string.Join(
            "\n",
            prepared.ArtistId.ToString("D"),
            prepared.CanonicalTitle,
            prepared.NormalizedTitle,
            prepared.LanguageTag,
            prepared.RecordingTitle ?? string.Empty,
            prepared.RecordingDurationMs?.ToString(
                CultureInfo.InvariantCulture) ?? string.Empty,
            ProviderCode,
            prepared.ExternalRef,
            prepared.SourceDurationMs?.ToString(
                CultureInfo.InvariantCulture) ?? string.Empty,
            prepared.OffsetMs.ToString(
                CultureInfo.InvariantCulture));

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

    private static SongDraftCreatedResult ToCreatedResult(
        ExistingSongDraft existing,
        bool duplicateWarningAcknowledged,
        bool alreadyApplied) =>
        new(
            existing.WorkId,
            existing.RecordingId,
            existing.SourceId,
            existing.ArtistId,
            existing.CanonicalTitle,
            existing.RecordingTitle,
            existing.ProviderCode,
            existing.ExternalRef,
            existing.RecordingStatusCode,
            duplicateWarningAcknowledged,
            alreadyApplied);

    private sealed record PreparedSongDraft(
        Guid ArtistId,
        string CanonicalTitle,
        string NormalizedTitle,
        string LanguageTag,
        string? RecordingTitle,
        long? RecordingDurationMs,
        string ExternalRef,
        long? SourceDurationMs,
        long OffsetMs);

    private sealed record ExistingSongDraft(
        Guid WorkId,
        Guid RecordingId,
        Guid SourceId,
        Guid ArtistId,
        string CanonicalTitle,
        string LanguageTag,
        string? RecordingTitle,
        long? RecordingDurationMs,
        string ProviderCode,
        string ExternalRef,
        long? SourceDurationMs,
        long OffsetMs,
        string WorkStatusCode,
        string RecordingStatusCode,
        string SourceStatusCode);
}
