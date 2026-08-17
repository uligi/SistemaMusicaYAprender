using System.Security.Cryptography;
using System.Text;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Editorial.Infrastructure.Administration;

public sealed record EducationalPackageSubmissionInput(string Reason);

public sealed record EducationalPackageSubmissionSnapshot(
    Guid RecordingId,
    bool Exists,
    Guid? PackageId,
    int? PackageNo,
    string? PackageStatusCode,
    long PackageVersion,
    string? PackageChecksumSha256,
    DateTime? FrozenAt,
    Guid? SubmissionId,
    string? SubmissionStatusCode,
    DateTime? SubmittedAt,
    string? ChecklistVersion,
    string ETag,
    string Message);

public sealed class EducationalPackageSubmissionException(
    string code,
    string message) : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed class EducationalPackageSubmissionService(
    ICompatibleEducationalPackageTransactionExecutor transactions)
{
    public const string ChecklistVersion = "BL-MVP-048.v1";

    private static readonly HashSet<string> TerminalRevisionStatuses =
        new(StringComparer.Ordinal)
        {
            "REJECTED",
            "WITHDRAWN",
            "SUPERSEDED"
        };

    public Task<EducationalPackageSubmissionSnapshot> ReadLatestAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(actorAccountId, recordingId, correlationId);

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ReadLatestCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    token),
            cancellationToken);
    }

    public Task<EducationalPackageSubmissionSnapshot> SubmitAsync(
        Guid actorAccountId,
        Guid recordingId,
        EducationalPackageSubmissionInput input,
        string ifMatch,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);
        ValidateIdentity(actorAccountId, recordingId, correlationId);

        if (string.IsNullOrWhiteSpace(ifMatch))
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.precondition-required",
                "Recarga el paquete compatible antes de someterlo a revisión.");
        }

        var reason = NormalizeReason(input.Reason);

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await AcquireRecordingLockAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                var draft = await ReadDraftHeaderAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                if (draft is null)
                {
                    throw new EducationalPackageSubmissionException(
                        "editorial.package.submit.draft-required",
                        "No existe un paquete DRAFT actual para congelar y someter.");
                }

                var expectedEtag =
                    CompatibleEducationalPackageService.ETagFor(
                        recordingId,
                        draft.PackageId,
                        draft.Version,
                        Convert.ToHexString(draft.Checksum)
                            .ToLowerInvariant());

                if (!string.Equals(
                        expectedEtag,
                        ifMatch.Trim(),
                        StringComparison.Ordinal))
                {
                    throw new EducationalPackageSubmissionException(
                        "editorial.package.submit.source-changed",
                        "El paquete DRAFT cambió. Recarga y confirma nuevamente antes de congelar.");
                }

                await ValidateDraftForSubmissionAsync(
                    connection,
                    transaction,
                    recordingId,
                    draft,
                    token);

                var frozenVersion = await FreezePackageAsync(
                    connection,
                    transaction,
                    draft.PackageId,
                    token);

                var submission = await InsertSubmissionAsync(
                    connection,
                    transaction,
                    draft.PackageId,
                    actorAccountId,
                    token);

                await WriteAuditAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    draft.PackageId,
                    draft.Checksum,
                    BuildSubmissionDigest(
                        draft.Checksum,
                        submission.SubmissionId),
                    reason,
                    correlationId,
                    token);

                var result = await ReadLatestCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                if (!result.Exists
                    || result.SubmissionId != submission.SubmissionId
                    || result.PackageId != draft.PackageId
                    || result.PackageVersion != frozenVersion)
                {
                    throw new InvalidOperationException(
                        "El sometimiento confirmado no pudo releerse de forma consistente.");
                }

                return result;
            },
            cancellationToken);
    }

    private static async Task ValidateDraftForSubmissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        PackageHeader draft,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(
                draft.StatusCode,
                "DRAFT",
                StringComparison.Ordinal)
            || draft.FrozenAt is not null)
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.not-mutable",
                "Solo un paquete DRAFT no congelado puede someterse.");
        }

        var catalogVersion = await ReadRecordingVersionAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var componentCount = await ReadPackageComponentCountAsync(
            connection,
            transaction,
            draft.PackageId,
            cancellationToken);

        var components = await ReadCurrentComponentsAsync(
            connection,
            transaction,
            draft.PackageId,
            cancellationToken);

        if (componentCount != components.Count)
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.broken-link",
                "El paquete contiene referencias que ya no pueden validarse.");
        }

        RequireComponentCount(components, "LYRICS", 1, 1);
        RequireComponentCount(components, "TIMING", 1, 1);
        RequireComponentCount(components, "TRANSLATION", 1, 1);
        RequireComponentCount(components, "ANALYSIS", 1, 1);
        RequireComponentCount(components, "EXERCISE", 1, 100);

        foreach (var component in components)
        {
            if (TerminalRevisionStatuses.Contains(component.StatusCode))
            {
                throw new EducationalPackageSubmissionException(
                    "editorial.package.submit.component-terminal",
                    $"{component.ComponentKind} está en estado {component.StatusCode} y ya no puede someterse.");
            }

            if (!component.StoredChecksum
                    .AsSpan()
                    .SequenceEqual(component.CurrentChecksum))
            {
                throw new EducationalPackageSubmissionException(
                    "editorial.package.submit.component-changed",
                    $"{component.ComponentKind} cambió después del ensamblaje. Crea o guarda un nuevo DRAFT.");
            }
        }

        var lyrics = components.Single(component =>
            component.ComponentKind == "LYRICS");

        if (components
            .Where(component => component.ComponentKind != "LYRICS")
            .Any(component =>
                component.SourceLyricsRevisionId != lyrics.RevisionId))
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.source-incompatible",
                "Uno o más componentes ya no pertenecen a la revisión japonesa exacta del paquete.");
        }

        foreach (var exercise in components.Where(component =>
                     component.ComponentKind == "EXERCISE"))
        {
            if (!await HasExerciseProvenanceAsync(
                    connection,
                    transaction,
                    exercise.RevisionId,
                    cancellationToken))
            {
                throw new EducationalPackageSubmissionException(
                    "editorial.package.submit.exercise-provenance-required",
                    "Un ejercicio perdió la procedencia editorial requerida antes del sometimiento.");
            }
        }

        if (!await HasActiveRightsAsync(
                connection,
                transaction,
                recordingId,
                cancellationToken))
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.rights-required",
                "Los derechos vigentes deben seguir activos al momento de congelar.");
        }

        var currentPackageChecksum = BuildPackageChecksum(
            recordingId,
            catalogVersion,
            components);

        var packageChecksumCurrent =
            draft.Checksum.AsSpan()
                .SequenceEqual(currentPackageChecksum);

        if (!packageChecksumCurrent)
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.checksum-changed",
                "El catálogo o un componente cambió después del último guardado. Vuelve a ensamblar el DRAFT.");
        }

        return;
    }

    private static void RequireComponentCount(
        IReadOnlyList<PackageComponentState> components,
        string componentKind,
        int minimum,
        int maximum)
    {
        var count = components.Count(component =>
            component.ComponentKind == componentKind);

        if (count < minimum || count > maximum)
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.components-incomplete",
                $"El paquete requiere {componentKind} dentro del conjunto compatible.");
        }
    }

    private static async Task<int> ReadPackageComponentCountAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT COUNT(*)::integer
            FROM editorial.package_component
            WHERE package_id = @package_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);

        return Convert.ToInt32(
            await command.ExecuteScalarAsync(cancellationToken) ?? 0,
            System.Globalization.CultureInfo.InvariantCulture);
    }

    private static async Task<IReadOnlyList<PackageComponentState>>
        ReadCurrentComponentsAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid packageId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                pc.component_kind,
                l.lyrics_revision_id,
                l.lyrics_revision_id,
                pc.checksum,
                l.checksum,
                l.status_code
            FROM editorial.package_component pc
            JOIN content.lyrics_revision l
              ON l.lyrics_revision_id = pc.lyrics_revision_id
            WHERE pc.package_id = @package_id
              AND pc.component_kind = 'LYRICS'

            UNION ALL

            SELECT
                pc.component_kind,
                t.timing_revision_id,
                t.lyrics_revision_id,
                pc.checksum,
                t.checksum,
                t.status_code
            FROM editorial.package_component pc
            JOIN content.timing_revision t
              ON t.timing_revision_id = pc.timing_revision_id
            WHERE pc.package_id = @package_id
              AND pc.component_kind = 'TIMING'

            UNION ALL

            SELECT
                pc.component_kind,
                tr.translation_revision_id,
                tr.lyrics_revision_id,
                pc.checksum,
                tr.checksum,
                tr.status_code
            FROM editorial.package_component pc
            JOIN content.translation_revision tr
              ON tr.translation_revision_id = pc.translation_revision_id
            WHERE pc.package_id = @package_id
              AND pc.component_kind = 'TRANSLATION'

            UNION ALL

            SELECT
                pc.component_kind,
                a.analysis_revision_id,
                a.lyrics_revision_id,
                pc.checksum,
                a.checksum,
                a.status_code
            FROM editorial.package_component pc
            JOIN content.linguistic_analysis_revision a
              ON a.analysis_revision_id = pc.analysis_revision_id
            WHERE pc.package_id = @package_id
              AND pc.component_kind = 'ANALYSIS'

            UNION ALL

            SELECT
                pc.component_kind,
                er.exercise_revision_id,
                section.lyrics_revision_id,
                pc.checksum,
                er.checksum,
                er.status_code
            FROM editorial.package_component pc
            JOIN learning.exercise_revision er
              ON er.exercise_revision_id = pc.exercise_revision_id
            JOIN learning.exercise_definition definition
              ON definition.exercise_id = er.exercise_id
            JOIN content.lyric_line line
              ON line.line_id = definition.line_id
            JOIN content.lyric_section section
              ON section.section_id = line.section_id
            WHERE pc.package_id = @package_id
              AND pc.component_kind = 'EXERCISE'

            ORDER BY 1, 2;
            """;

        var results = new List<PackageComponentState>();

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(
                new PackageComponentState(
                    reader.GetString(0),
                    reader.GetGuid(1),
                    reader.GetGuid(2),
                    (byte[])reader.GetValue(3),
                    (byte[])reader.GetValue(4),
                    reader.GetString(5)));
        }

        return results;
    }

    private static async Task<PackageHeader?> ReadDraftHeaderAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                package_id,
                status_code,
                frozen_at,
                checksum,
                version
            FROM editorial.editorial_package
            WHERE recording_id = @recording_id
              AND status_code = 'DRAFT'
              AND frozen_at IS NULL
            ORDER BY package_no DESC, package_id DESC;
            """;

        var results = new List<PackageHeader>();

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(
                new PackageHeader(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.IsDBNull(2)
                        ? null
                        : reader.GetDateTime(2),
                    (byte[])reader.GetValue(3),
                    reader.GetInt64(4)));
        }

        if (results.Count > 1)
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.multiple-drafts",
                "Existe más de un DRAFT abierto para esta grabación.");
        }

        return results.SingleOrDefault();
    }

    private static async Task<long> FreezePackageAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE editorial.editorial_package
            SET
                status_code = 'SUBMITTED',
                frozen_at = CURRENT_TIMESTAMP
            WHERE package_id = @package_id
              AND status_code = 'DRAFT'
              AND frozen_at IS NULL
            RETURNING version;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.concurrent-change",
                "El paquete dejó de estar disponible para congelar. Recarga antes de continuar.");
        }

        return reader.GetInt64(0);
    }

    private static async Task<SubmissionRow> InsertSubmissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        Guid actorAccountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.review_submission (
                package_id,
                submitted_by,
                submitted_at,
                status_code,
                checklist_version
            )
            VALUES (
                @package_id,
                @submitted_by,
                CURRENT_TIMESTAMP,
                'SUBMITTED',
                @checklist_version
            )
            RETURNING submission_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);
        command.Parameters.AddWithValue(
            "submitted_by",
            NpgsqlDbType.Uuid,
            actorAccountId);
        command.Parameters.AddWithValue(
            "checklist_version",
            ChecklistVersion);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "No se pudo crear el sometimiento editorial.");
        }

        return new SubmissionRow(reader.GetGuid(0));
    }

    private static async Task<EducationalPackageSubmissionSnapshot>
        ReadLatestCoreAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid recordingId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                p.package_id,
                p.package_no,
                p.status_code,
                p.version,
                encode(p.checksum, 'hex'),
                p.frozen_at,
                s.submission_id,
                s.status_code,
                s.submitted_at,
                s.checklist_version
            FROM editorial.review_submission s
            JOIN editorial.editorial_package p
              ON p.package_id = s.package_id
            WHERE p.recording_id = @recording_id
            ORDER BY s.submitted_at DESC, s.submission_id DESC
            LIMIT 1;
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
            return new EducationalPackageSubmissionSnapshot(
                recordingId,
                false,
                null,
                null,
                null,
                0,
                null,
                null,
                null,
                null,
                null,
                null,
                $"\"submission-{recordingId:N}-none\"",
                "Todavía no existe un paquete sometido a revisión.");
        }

        var packageId = reader.GetGuid(0);
        var packageNo = reader.GetInt32(1);
        var packageStatus = reader.GetString(2);
        var packageVersion = reader.GetInt64(3);
        var checksum = reader.GetString(4);
        DateTime? frozenAt = reader.IsDBNull(5)
            ? null
            : reader.GetDateTime(5);
        var submissionId = reader.GetGuid(6);
        var submissionStatus = reader.GetString(7);
        var submittedAt = reader.GetDateTime(8);
        var checklistVersion = reader.GetString(9);

        return new EducationalPackageSubmissionSnapshot(
            recordingId,
            true,
            packageId,
            packageNo,
            packageStatus,
            packageVersion,
            checksum,
            frozenAt,
            submissionId,
            submissionStatus,
            submittedAt,
            checklistVersion,
            $"\"submission-{submissionId:N}-package-v{packageVersion}\"",
            $"Paquete {packageNo} congelado y sometido a revisión. La publicación sigue pendiente de BL-MVP-049/050.");
    }

    private static async Task<long> ReadRecordingVersionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT version
            FROM catalog.recording
            WHERE recording_id = @recording_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        var value =
            await command.ExecuteScalarAsync(cancellationToken);

        if (value is not long version || version <= 0)
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.recording-not-found",
                "La grabación editorial solicitada no existe.");
        }

        return version;
    }

    private static async Task<bool> HasActiveRightsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM editorial.rights_record rights
                WHERE rights.object_type = 'RECORDING'
                  AND rights.object_id = @recording_id
                  AND rights.status_code = 'ACTIVE'
                  AND (rights.valid_from IS NULL OR rights.valid_from <= CURRENT_TIMESTAMP)
                  AND (rights.valid_to IS NULL OR rights.valid_to > CURRENT_TIMESTAMP)
                  AND EXISTS (
                      SELECT 1
                      FROM editorial.rights_scope scope
                      WHERE scope.rights_record_id = rights.rights_record_id
                  )
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        return (bool)(
            await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static async Task<bool> HasExerciseProvenanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid exerciseRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM editorial.provenance_record
                WHERE object_type = 'EXERCISE_REVISION'
                  AND object_id = @revision_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "revision_id",
            NpgsqlDbType.Uuid,
            exerciseRevisionId);

        return (bool)(
            await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static byte[] BuildPackageChecksum(
        Guid recordingId,
        long catalogVersion,
        IReadOnlyList<PackageComponentState> components)
    {
        var material = new StringBuilder();
        material.Append(recordingId.ToString("N"));
        material.Append("|catalog-v");
        material.Append(
            catalogVersion.ToString(
                System.Globalization.CultureInfo.InvariantCulture));

        foreach (var component in components
                     .OrderBy(
                         component => component.ComponentKind,
                         StringComparer.Ordinal)
                     .ThenBy(component => component.RevisionId))
        {
            material.Append('\n');
            material.Append(component.ComponentKind);
            material.Append('|');
            material.Append(component.RevisionId.ToString("N"));
            material.Append('|');
            material.Append(
                Convert.ToHexString(component.CurrentChecksum)
                    .ToLowerInvariant());
        }

        return SHA256.HashData(
            Encoding.UTF8.GetBytes(material.ToString()));
    }

    private static byte[] BuildSubmissionDigest(
        byte[] packageChecksum,
        Guid submissionId)
    {
        var material =
            $"{Convert.ToHexString(packageChecksum)}|SUBMITTED|{submissionId:N}|{ChecklistVersion}";

        return SHA256.HashData(
            Encoding.UTF8.GetBytes(material));
    }

    private static async Task AcquireRecordingLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql =
            "SELECT pg_advisory_xact_lock(hashtextextended(@key, 0));";

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "key",
            $"EDITORIAL-PACKAGE:{recordingId:D}");

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid packageId,
        byte[] beforeDigest,
        byte[] afterDigest,
        string reason,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var roleCode = await ReadAuditRoleCodeAsync(
            connection,
            transaction,
            actorAccountId,
            cancellationToken);

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
                'EDITORIAL_PACKAGE',
                @package_id,
                'EDITORIAL.PACKAGE.SUBMIT',
                @before_digest,
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
            NpgsqlDbType.Uuid,
            actorAccountId);
        command.Parameters.AddWithValue(
            "role_code",
            roleCode);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);
        command.Parameters.AddWithValue(
            "before_digest",
            NpgsqlDbType.Bytea,
            beforeDigest);
        command.Parameters.AddWithValue(
            "after_digest",
            NpgsqlDbType.Bytea,
            afterDigest);
        command.Parameters.AddWithValue(
            "reason",
            reason);
        command.Parameters.AddWithValue(
            "correlation_id",
            NpgsqlDbType.Uuid,
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
              AND p.permission_code = 'EDITORIAL.SUBMIT'
              AND r.status_code = 'ACTIVE'
              AND a.valid_from <= CURRENT_TIMESTAMP
              AND (a.valid_to IS NULL OR a.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL OR rp.valid_to > CURRENT_TIMESTAMP)
            ORDER BY r.role_code
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "actor_id",
            NpgsqlDbType.Uuid,
            actorAccountId);

        var value =
            await command.ExecuteScalarAsync(cancellationToken);

        return value as string
            ?? throw new EducationalPackageSubmissionException(
                "editorial.package.submit.permission-lost",
                "La capacidad EDITORIAL.SUBMIT dejó de estar vigente.");
    }

    private static string NormalizeReason(string? value)
    {
        var reason = value?.Trim() ?? string.Empty;

        if (reason.Length < 3)
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.reason-required",
                "Explica brevemente por qué el paquete está listo para revisión.");
        }

        if (reason.Length > 1000)
        {
            throw new EducationalPackageSubmissionException(
                "editorial.package.submit.reason-too-long",
                "El motivo del sometimiento no puede superar 1000 caracteres.");
        }

        return reason;
    }

    private static void ValidateIdentity(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException(
                "Actor inválido.",
                nameof(actorAccountId));
        }

        if (recordingId == Guid.Empty)
        {
            throw new ArgumentException(
                "Grabación inválida.",
                nameof(recordingId));
        }

        if (string.IsNullOrWhiteSpace(correlationId))
        {
            throw new ArgumentException(
                "Correlación requerida.",
                nameof(correlationId));
        }
    }

    private static Guid CorrelationGuid(string correlationId)
    {
        if (Guid.TryParse(correlationId, out var parsed)
            && parsed != Guid.Empty)
        {
            return parsed;
        }

        var digest =
            SHA256.HashData(
                Encoding.UTF8.GetBytes(correlationId));

        return new Guid(digest.AsSpan(0, 16));
    }

    private sealed record PackageHeader(
        Guid PackageId,
        string StatusCode,
        DateTime? FrozenAt,
        byte[] Checksum,
        long Version);

    private sealed record PackageComponentState(
        string ComponentKind,
        Guid RevisionId,
        Guid SourceLyricsRevisionId,
        byte[] StoredChecksum,
        byte[] CurrentChecksum,
        string StatusCode);

    private sealed record SubmissionRow(Guid SubmissionId);
}
