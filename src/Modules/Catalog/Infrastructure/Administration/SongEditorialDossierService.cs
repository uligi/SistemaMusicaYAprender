using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Administration;

public sealed record SongEditorialCatalogSummary(
    string CanonicalTitle,
    string? RecordingTitle,
    string ArtistName,
    string RecordingStatusCode,
    long RecordingVersion,
    string? ProviderCode,
    string? ExternalRef,
    string? SourceStatusCode);

public sealed record SongEditorialComponentSnapshot(
    string Code,
    string Label,
    string RevisionLabel,
    string StateCode,
    Guid? OwnerActorId,
    Guid? ObjectId,
    bool Exists);

public sealed record SongEditorialRightsSummary(
    int TotalRecords,
    int ActiveRecords,
    int ProvenanceRecords,
    Guid? OwnerActorId,
    Guid? LatestRightsRecordId);

public sealed record SongEditorialIncidentSnapshot(
    string ComponentCode,
    string RuleCode,
    string SeverityCode,
    string StatusCode,
    DateTime DetectedAt);

public sealed record SongEditorialDossier(
    Guid RecordingId,
    SongEditorialCatalogSummary Catalog,
    IReadOnlyList<SongEditorialComponentSnapshot> Components,
    SongEditorialRightsSummary Rights,
    IReadOnlyList<SongEditorialIncidentSnapshot> Incidents);

public sealed class SongEditorialDossierException(
    string code,
    string message) : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed class SongEditorialDossierService(
    ISongEditorialDossierTransactionExecutor transactionExecutor)
{
    public Task<SongEditorialDossier> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException(
                "ActorAccountId no puede ser Guid.Empty.",
                nameof(actorAccountId));
        }

        if (recordingId == Guid.Empty)
        {
            throw new SongEditorialDossierException(
                "editorial.song-dossier.recording.invalid",
                "La grabación solicitada no es válida.");
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ReadCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    token),
            cancellationToken);
    }

    private static async Task<SongEditorialDossier> ReadCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        var catalog = await ReadCatalogAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var components = new List<SongEditorialComponentSnapshot>
        {
            new(
                "CATALOG",
                "Catálogo",
                $"v{catalog.RecordingVersion}",
                catalog.RecordingStatusCode,
                await ReadLatestAuditActorAsync(
                    connection,
                    transaction,
                    recordingId,
                    cancellationToken),
                recordingId,
                Exists: true)
        };

        components.Add(
            await ReadSingleRevisionAsync(
                connection,
                transaction,
                recordingId,
                "LYRICS",
                "Letra japonesa",
                """
                SELECT
                    revision.lyrics_revision_id,
                    revision.revision_no,
                    revision.status_code,
                    revision.created_by
                FROM content.lyrics_revision AS revision
                WHERE revision.recording_id = @recording_id
                ORDER BY
                    revision.revision_no DESC,
                    revision.lyrics_revision_id DESC
                LIMIT 1;
                """,
                cancellationToken));

        components.Add(
            await ReadSingleRevisionAsync(
                connection,
                transaction,
                recordingId,
                "TIMING",
                "Sincronización",
                """
                SELECT
                    timing.timing_revision_id,
                    timing.revision_no,
                    timing.status_code,
                    latest_audit.actor_id
                FROM content.timing_revision AS timing
                INNER JOIN content.lyrics_revision AS lyrics
                    ON lyrics.lyrics_revision_id = timing.lyrics_revision_id
                LEFT JOIN LATERAL (
                    SELECT audit.actor_id
                    FROM security.audit_event AS audit
                    WHERE audit.object_id = timing.timing_revision_id
                    ORDER BY audit.occurred_at DESC, audit.audit_id DESC
                    LIMIT 1
                ) AS latest_audit ON true
                WHERE lyrics.recording_id = @recording_id
                ORDER BY
                    lyrics.revision_no DESC,
                    timing.revision_no DESC,
                    timing.timing_revision_id DESC
                LIMIT 1;
                """,
                cancellationToken));

        components.Add(
            await ReadSingleRevisionAsync(
                connection,
                transaction,
                recordingId,
                "TRANSLATION",
                "Traducción",
                """
                SELECT
                    translation.translation_revision_id,
                    translation.revision_no,
                    translation.status_code,
                    latest_audit.actor_id
                FROM content.translation_revision AS translation
                INNER JOIN content.lyrics_revision AS lyrics
                    ON lyrics.lyrics_revision_id = translation.lyrics_revision_id
                LEFT JOIN LATERAL (
                    SELECT audit.actor_id
                    FROM security.audit_event AS audit
                    WHERE audit.object_id = translation.translation_revision_id
                    ORDER BY audit.occurred_at DESC, audit.audit_id DESC
                    LIMIT 1
                ) AS latest_audit ON true
                WHERE lyrics.recording_id = @recording_id
                ORDER BY
                    CASE WHEN translation.target_language = 'es' THEN 0 ELSE 1 END,
                    lyrics.revision_no DESC,
                    translation.revision_no DESC,
                    translation.translation_revision_id DESC
                LIMIT 1;
                """,
                cancellationToken));

        components.Add(
            await ReadSingleRevisionAsync(
                connection,
                transaction,
                recordingId,
                "ANALYSIS",
                "Análisis lingüístico",
                """
                SELECT
                    analysis.analysis_revision_id,
                    analysis.revision_no,
                    analysis.status_code,
                    latest_audit.actor_id
                FROM content.linguistic_analysis_revision AS analysis
                INNER JOIN content.lyrics_revision AS lyrics
                    ON lyrics.lyrics_revision_id = analysis.lyrics_revision_id
                LEFT JOIN LATERAL (
                    SELECT audit.actor_id
                    FROM security.audit_event AS audit
                    WHERE audit.object_id = analysis.analysis_revision_id
                    ORDER BY audit.occurred_at DESC, audit.audit_id DESC
                    LIMIT 1
                ) AS latest_audit ON true
                WHERE lyrics.recording_id = @recording_id
                ORDER BY
                    lyrics.revision_no DESC,
                    analysis.revision_no DESC,
                    analysis.analysis_revision_id DESC
                LIMIT 1;
                """,
                cancellationToken));

        components.Add(
            await ReadExerciseSummaryAsync(
                connection,
                transaction,
                recordingId,
                cancellationToken));

        var rights = await ReadRightsAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        components.Add(
            new SongEditorialComponentSnapshot(
                "RIGHTS",
                "Derechos y procedencia",
                rights.TotalRecords == 0
                    ? "Sin registros"
                    : $"{rights.TotalRecords} registro(s)",
                rights.ActiveRecords > 0
                    ? "ACTIVE"
                    : rights.TotalRecords > 0
                        ? "INACTIVE"
                        : "NOT_STARTED",
                rights.OwnerActorId,
                rights.LatestRightsRecordId,
                rights.TotalRecords > 0));

        var objectCodes = components
            .Where(static component => component.ObjectId is not null)
            .ToDictionary(
                static component => component.ObjectId!.Value,
                static component => component.Code);

        var incidents = await ReadIncidentsAsync(
            connection,
            transaction,
            objectCodes,
            cancellationToken);

        return new SongEditorialDossier(
            recordingId,
            catalog,
            components,
            rights,
            incidents);
    }

    private static async Task<SongEditorialCatalogSummary> ReadCatalogAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                work.canonical_title,
                recording.recording_title,
                COALESCE(primary_artist.artist_name, 'Artista sin identificar') AS artist_name,
                recording.status_code,
                recording.version,
                source.provider_code,
                source.external_ref,
                source.status_code
            FROM catalog.recording AS recording
            INNER JOIN catalog.musical_work AS work
                ON work.work_id = recording.work_id
            LEFT JOIN LATERAL (
                SELECT artist.canonical_name AS artist_name
                FROM catalog.work_artist AS work_artist
                INNER JOIN catalog.artist AS artist
                    ON artist.artist_id = work_artist.artist_id
                WHERE work_artist.work_id = work.work_id
                ORDER BY
                    CASE WHEN work_artist.role_code = 'PRIMARY' THEN 0 ELSE 1 END,
                    work_artist.display_order,
                    artist.artist_id
                LIMIT 1
            ) AS primary_artist ON true
            LEFT JOIN LATERAL (
                SELECT
                    recording_source.provider_code,
                    recording_source.external_ref,
                    recording_source.status_code
                FROM catalog.recording_source
                WHERE recording_source.recording_id = recording.recording_id
                ORDER BY
                    CASE
                        WHEN recording_source.status_code IN ('ACTIVE', 'PUBLISHED', 'DRAFT')
                        THEN 0
                        ELSE 1
                    END,
                    recording_source.version DESC,
                    recording_source.source_id DESC
                LIMIT 1
            ) AS source ON true
            WHERE recording.recording_id = @recording_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new SongEditorialDossierException(
                "editorial.song-dossier.not-found",
                "No existe una grabación editorial con ese identificador.");
        }

        return new SongEditorialCatalogSummary(
            reader.GetString(0),
            reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetInt64(4),
            reader.IsDBNull(5) ? null : reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetString(7));
    }

    private static async Task<SongEditorialComponentSnapshot>
        ReadSingleRevisionAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid recordingId,
            string code,
            string label,
            string sql,
            CancellationToken cancellationToken)
    {
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return new SongEditorialComponentSnapshot(
                code,
                label,
                "Sin revisión",
                "NOT_STARTED",
                OwnerActorId: null,
                ObjectId: null,
                Exists: false);
        }

        return new SongEditorialComponentSnapshot(
            code,
            label,
            $"r{reader.GetInt32(1)}",
            reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetGuid(3),
            reader.GetGuid(0),
            Exists: true);
    }

    private static async Task<SongEditorialComponentSnapshot>
        ReadExerciseSummaryAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid recordingId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            WITH candidate AS (
                SELECT
                    definition.exercise_id,
                    revision.exercise_revision_id,
                    revision.revision_no,
                    revision.status_code
                FROM learning.exercise_definition AS definition
                LEFT JOIN learning.exercise_revision AS revision
                    ON revision.exercise_id = definition.exercise_id
                WHERE definition.recording_id = @recording_id
            ),
            summary AS (
                SELECT
                    count(DISTINCT exercise_id)::integer AS exercise_count,
                    count(exercise_revision_id)::integer AS revision_count,
                    count(DISTINCT status_code)
                        FILTER (WHERE status_code IS NOT NULL)::integer AS status_count,
                    max(status_code) FILTER (WHERE status_code IS NOT NULL) AS single_status
                FROM candidate
            ),
            latest AS (
                SELECT
                    exercise_revision_id,
                    revision_no,
                    status_code
                FROM candidate
                WHERE exercise_revision_id IS NOT NULL
                ORDER BY
                    revision_no DESC,
                    exercise_revision_id DESC
                LIMIT 1
            )
            SELECT
                summary.exercise_count,
                summary.revision_count,
                summary.status_count,
                summary.single_status,
                latest.exercise_revision_id,
                latest_audit.actor_id
            FROM summary
            LEFT JOIN latest ON true
            LEFT JOIN LATERAL (
                SELECT audit.actor_id
                FROM security.audit_event AS audit
                WHERE audit.object_id = latest.exercise_revision_id
                ORDER BY audit.occurred_at DESC, audit.audit_id DESC
                LIMIT 1
            ) AS latest_audit ON true;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);

        var exerciseCount = reader.GetInt32(0);
        var revisionCount = reader.GetInt32(1);
        var statusCount = reader.GetInt32(2);
        var state = revisionCount == 0
            ? "NOT_STARTED"
            : statusCount == 1 && !reader.IsDBNull(3)
                ? reader.GetString(3)
                : "MIXED";

        return new SongEditorialComponentSnapshot(
            "EXERCISES",
            "Banco de ejercicios",
            revisionCount == 0
                ? "Sin revisión"
                : $"{revisionCount} revisión(es) / {exerciseCount} ejercicio(s)",
            state,
            reader.IsDBNull(5) ? null : reader.GetGuid(5),
            reader.IsDBNull(4) ? null : reader.GetGuid(4),
            Exists: revisionCount > 0);
    }

    private static async Task<SongEditorialRightsSummary> ReadRightsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                (
                    SELECT count(*)::integer
                    FROM editorial.rights_record AS rights
                    WHERE rights.object_type = 'RECORDING'
                      AND rights.object_id = @recording_id
                ) AS total_records,
                (
                    SELECT count(*)::integer
                    FROM editorial.rights_record AS rights
                    INNER JOIN ops.stored_object AS evidence
                        ON evidence.object_id = rights.evidence_object_id
                    WHERE rights.object_type = 'RECORDING'
                      AND rights.object_id = @recording_id
                      AND rights.status_code = 'ACTIVE'
                      AND (rights.valid_from IS NULL OR rights.valid_from <= CURRENT_TIMESTAMP)
                      AND (rights.valid_to IS NULL OR rights.valid_to > CURRENT_TIMESTAMP)
                      AND evidence.status_code = 'ACTIVE'
                ) AS active_records,
                (
                    SELECT count(*)::integer
                    FROM catalog.recording_credit AS credit
                    INNER JOIN editorial.provenance_record AS provenance
                        ON provenance.object_type = 'RECORDING_CREDIT'
                       AND provenance.object_id = credit.credit_id
                    WHERE credit.recording_id = @recording_id
                ) AS provenance_records,
                latest.actor_id,
                latest.rights_record_id
            FROM (VALUES (1)) AS singleton(dummy)
            LEFT JOIN LATERAL (
                SELECT
                    latest_audit.actor_id,
                    rights.rights_record_id
                FROM editorial.rights_record AS rights
                LEFT JOIN LATERAL (
                    SELECT
                        audit.actor_id,
                        audit.occurred_at,
                        audit.audit_id
                    FROM security.audit_event AS audit
                    WHERE audit.object_id = rights.rights_record_id
                    ORDER BY
                        audit.occurred_at DESC,
                        audit.audit_id DESC
                    LIMIT 1
                ) AS latest_audit ON true
                WHERE rights.object_type = 'RECORDING'
                  AND rights.object_id = @recording_id
                ORDER BY
                    latest_audit.occurred_at DESC NULLS LAST,
                    rights.rights_record_id DESC
                LIMIT 1
            ) AS latest ON true;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);

        return new SongEditorialRightsSummary(
            reader.GetInt32(0),
            reader.GetInt32(1),
            reader.GetInt32(2),
            reader.IsDBNull(3) ? null : reader.GetGuid(3),
            reader.IsDBNull(4) ? null : reader.GetGuid(4));
    }

    private static async Task<Guid?> ReadLatestAuditActorAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid objectId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT actor_id
            FROM security.audit_event
            WHERE object_id = @object_id
            ORDER BY occurred_at DESC, audit_id DESC
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "object_id",
            NpgsqlDbType.Uuid,
            objectId);

        var value =
            await command.ExecuteScalarAsync(cancellationToken);
        return value is Guid actorId ? actorId : null;
    }

    private static async Task<IReadOnlyList<SongEditorialIncidentSnapshot>>
        ReadIncidentsAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            IReadOnlyDictionary<Guid, string> objectCodes,
            CancellationToken cancellationToken)
    {
        if (objectCodes.Count == 0)
        {
            return [];
        }

        const string sql = """
            SELECT
                object_id,
                rule_code,
                severity_code,
                status_code,
                detected_at
            FROM ops.data_quality_issue
            WHERE object_id = ANY(@object_ids)
              AND status_code IN ('OPEN', 'ACKNOWLEDGED')
            ORDER BY
                detected_at DESC,
                issue_id DESC
            LIMIT 50;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            new NpgsqlParameter(
                "object_ids",
                NpgsqlDbType.Array | NpgsqlDbType.Uuid)
            {
                Value = objectCodes.Keys.ToArray()
            });

        var rows = new List<SongEditorialIncidentSnapshot>();

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var objectId = reader.GetGuid(0);
            rows.Add(
                new SongEditorialIncidentSnapshot(
                    objectCodes.GetValueOrDefault(
                        objectId,
                        "UNKNOWN"),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetDateTime(4)));
        }

        return rows;
    }
}
