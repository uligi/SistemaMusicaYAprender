using Npgsql;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Administration;

public sealed record EditorialInboxCandidate(
    Guid RecordingId,
    string CanonicalTitle,
    string? RecordingTitle,
    string ArtistName,
    string RecordingStatusCode,
    Guid? PackageId,
    string? PackageStatusCode,
    Guid? SubmissionId,
    string? SubmissionStatusCode,
    Guid? PublicationId,
    string? PublicationStatusCode,
    Guid? OwnerActorId,
    DateTime? LastActivityAt,
    string? LockOperationCode,
    DateTime? LockExpiresAt,
    bool HasProvenance,
    string? ProviderCode);

public sealed class EditorialInboxService(
    IEditorialInboxTransactionExecutor transactionExecutor)
{
    public Task<IReadOnlyList<EditorialInboxCandidate>> ReadCandidatesAsync(
        Guid actorAccountId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException(
                "ActorAccountId no puede ser Guid.Empty.",
                nameof(actorAccountId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);

        return transactionExecutor.ExecuteAsync<IReadOnlyList<EditorialInboxCandidate>>(
            actorAccountId,
            correlationId,
            ReadCandidatesCoreAsync,
            cancellationToken);
    }

    private static async Task<IReadOnlyList<EditorialInboxCandidate>>
        ReadCandidatesCoreAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                recording.recording_id,
                work.canonical_title,
                recording.recording_title,
                COALESCE(primary_artist.artist_name, 'Artista sin identificar') AS artist_name,
                recording.status_code,
                latest_package.package_id,
                latest_package.status_code,
                latest_submission.submission_id,
                latest_submission.status_code,
                latest_publication.publication_id,
                latest_publication.status_code,
                latest_audit.actor_id,
                COALESCE(
                    latest_audit.occurred_at,
                    latest_publication.published_at,
                    latest_submission.submitted_at,
                    latest_package.created_at
                ) AS last_activity_at,
                active_lock.operation_code,
                active_lock.expires_at,
                EXISTS (
                    SELECT 1
                    FROM catalog.recording_credit AS credit
                    INNER JOIN editorial.provenance_record AS provenance
                        ON provenance.object_type = 'RECORDING_CREDIT'
                       AND provenance.object_id = credit.credit_id
                    WHERE credit.recording_id = recording.recording_id
                ) AS has_provenance,
                source.provider_code
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
                    package.package_id,
                    package.status_code,
                    package.created_at
                FROM editorial.editorial_package AS package
                WHERE package.recording_id = recording.recording_id
                ORDER BY
                    package.package_no DESC,
                    package.created_at DESC,
                    package.package_id DESC
                LIMIT 1
            ) AS latest_package ON true
            LEFT JOIN LATERAL (
                SELECT
                    submission.submission_id,
                    submission.status_code,
                    submission.submitted_at
                FROM editorial.review_submission AS submission
                WHERE submission.package_id = latest_package.package_id
                ORDER BY
                    submission.submitted_at DESC,
                    submission.submission_id DESC
                LIMIT 1
            ) AS latest_submission ON true
            LEFT JOIN LATERAL (
                SELECT
                    publication.publication_id,
                    publication.status_code,
                    publication.published_at
                FROM editorial.publication AS publication
                WHERE publication.recording_id = recording.recording_id
                ORDER BY
                    publication.publication_no DESC,
                    publication.published_at DESC,
                    publication.publication_id DESC
                LIMIT 1
            ) AS latest_publication ON true
            LEFT JOIN LATERAL (
                SELECT
                    audit.actor_id,
                    audit.occurred_at
                FROM security.audit_event AS audit
                WHERE audit.object_type = 'RECORDING'
                  AND audit.object_id = recording.recording_id
                ORDER BY
                    audit.occurred_at DESC,
                    audit.audit_id DESC
                LIMIT 1
            ) AS latest_audit ON true
            LEFT JOIN LATERAL (
                SELECT
                    editorial_lock.operation_code,
                    editorial_lock.expires_at
                FROM editorial.editorial_lock
                WHERE editorial_lock.recording_id = recording.recording_id
                  AND editorial_lock.expires_at > CURRENT_TIMESTAMP
                ORDER BY
                    editorial_lock.expires_at DESC,
                    editorial_lock.lock_id DESC
                LIMIT 1
            ) AS active_lock ON true
            LEFT JOIN LATERAL (
                SELECT recording_source.provider_code
                FROM catalog.recording_source
                WHERE recording_source.recording_id = recording.recording_id
                ORDER BY
                    CASE
                        WHEN recording_source.status_code IN ('ACTIVE', 'PUBLISHED')
                        THEN 0
                        ELSE 1
                    END,
                    recording_source.version DESC,
                    recording_source.source_id DESC
                LIMIT 1
            ) AS source ON true
            ORDER BY
                last_activity_at DESC NULLS LAST,
                lower(work.canonical_title),
                recording.recording_id
            LIMIT 100;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction)
            {
                CommandTimeout = 15
            };

        var rows = new List<EditorialInboxCandidate>();

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new EditorialInboxCandidate(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetGuid(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.IsDBNull(7) ? null : reader.GetGuid(7),
                reader.IsDBNull(8) ? null : reader.GetString(8),
                reader.IsDBNull(9) ? null : reader.GetGuid(9),
                reader.IsDBNull(10) ? null : reader.GetString(10),
                reader.IsDBNull(11) ? null : reader.GetGuid(11),
                reader.IsDBNull(12) ? null : reader.GetDateTime(12),
                reader.IsDBNull(13) ? null : reader.GetString(13),
                reader.IsDBNull(14) ? null : reader.GetDateTime(14),
                reader.GetBoolean(15),
                reader.IsDBNull(16) ? null : reader.GetString(16)));
        }

        return rows;
    }
}
