using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Editorial.Infrastructure.Administration;

public sealed record EditorialPublicationComponentSnapshot(
    Guid SourceComponentId,
    Guid SourceRevisionId,
    string ComponentKind,
    string ChecksumSha256,
    int DisplayOrder);

public sealed record EditorialPublicationAvailabilitySnapshot(
    string TerritoryCode,
    string? LanguageTag,
    string AudienceCode,
    DateTime ValidFrom,
    DateTime? ValidTo,
    string StatusCode);

public sealed record EditorialPublicationSnapshot(
    Guid PublicationId,
    Guid PackageId,
    int PublicationNo,
    string StatusCode,
    DateTime ActiveFrom,
    DateTime? ActiveTo,
    DateTime PublishedAt,
    string ChecksumSha256,
    IReadOnlyList<EditorialPublicationAvailabilitySnapshot> Availability);

public sealed record EditorialPublicationCandidateSnapshot(
    Guid PackageId,
    int PackageNo,
    string StatusCode,
    long Version,
    string ChecksumSha256,
    bool Frozen,
    bool ApprovedReview,
    bool ComponentsComplete,
    bool ComponentsCurrent,
    bool HasActiveRights,
    bool ReadyToPublish,
    IReadOnlyList<EditorialPublicationComponentSnapshot> Components,
    IReadOnlyList<string> Issues);

public sealed record EditorialPublicationState(
    Guid RecordingId,
    EditorialPublicationCandidateSnapshot? Candidate,
    EditorialPublicationSnapshot? ActivePublication,
    IReadOnlyList<EditorialPublicationSnapshot> History,
    string ETag,
    string Message);

public sealed record PublishEditorialPackageCommand(
    Guid PackageId,
    string TerritoryCode,
    string? LanguageTag,
    string AudienceCode,
    string Reason);

public sealed record EditorialApprovedPackageOption(
    Guid PackageId,
    int PackageNo,
    string ChecksumSha256);

public sealed record EditorialPublicationActionSnapshot(
    Guid ActionId,
    Guid PublicationId,
    Guid? CaseId,
    string ActionCode,
    string FromStatus,
    string ToStatus,
    DateTime EffectiveAt,
    string Reason,
    Guid CorrelationId);

public sealed record EditorialCorrectionState(
    Guid RecordingId,
    EditorialPublicationSnapshot? ActivePublication,
    IReadOnlyList<EditorialPublicationSnapshot> History,
    IReadOnlyList<EditorialPublicationActionSnapshot> Actions,
    IReadOnlyList<EditorialApprovedPackageOption> ApprovedPackages,
    string ETag,
    string Message);

public sealed record CorrectEditorialPublicationCommand(
    string ActionCode,
    Guid? TargetPublicationId,
    Guid? TargetPackageId,
    string? TerritoryCode,
    string? LanguageTag,
    string? AudienceCode,
    string Reason);

public sealed class EditorialPublicationLifecycleException(
    string code,
    string message,
    int statusCode = 409) : Exception(message)
{
    public string Code { get; } = code;
    public int StatusCode { get; } = statusCode;
}

public sealed class EditorialPublicationLifecycleService(
    ICompatibleEducationalPackageTransactionExecutor transactions,
    ITransactionalOutboxWriter outbox)
{
    private const string ActivateAction = "ACTIVATE";
    private static readonly string[] RequiredKinds =
    [
        "LYRICS",
        "TIMING",
        "TRANSLATION",
        "ANALYSIS"
    ];

    public Task<EditorialPublicationState> ReadPublicationAsync(
        Guid actorAccountId,
        Guid recordingId,
        Guid? packageId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(actorAccountId, recordingId);
        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ReadPublicationStateAsync(connection, transaction, recordingId, packageId, token),
            cancellationToken);
    }

    public Task<EditorialCorrectionState> ReadCorrectionAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(actorAccountId, recordingId);
        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ReadCorrectionStateAsync(connection, transaction, recordingId, token),
            cancellationToken);
    }

    public Task<EditorialPublicationState> PublishAsync(
        Guid actorAccountId,
        Guid recordingId,
        PublishEditorialPackageCommand command,
        string ifMatch,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(actorAccountId, recordingId);
        ArgumentNullException.ThrowIfNull(command);

        var operationId = NormalizeIdempotencyKey(idempotencyKey);
        var territory = NormalizeCode(command.TerritoryCode, "territorio");
        var language = NormalizeLanguageTag(command.LanguageTag);
        var audience = NormalizeCode(command.AudienceCode, "audiencia");
        var reason = NormalizeReason(command.Reason);

        if (command.PackageId == Guid.Empty)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.package.required",
                "Selecciona el paquete aprobado exacto que se va a publicar.",
                400);
        }

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await AcquireLifecycleLockAsync(connection, transaction, recordingId, token);

                if (await IsMatchingPublishReplayAsync(
                        connection,
                        transaction,
                        operationId,
                        recordingId,
                        command.PackageId,
                        territory,
                        language,
                        audience,
                        reason,
                        token))
                {
                    return await ReadPublicationStateAsync(
                        connection, transaction, recordingId, command.PackageId, token);
                }

                var state = await ReadPublicationStateAsync(
                    connection, transaction, recordingId, command.PackageId, token);
                EnsureIfMatch(ifMatch, state.ETag);

                var candidate = state.Candidate
                    ?? throw new EditorialPublicationLifecycleException(
                        "editorial.publication.package.not-found",
                        "El paquete exacto solicitado no existe para esta grabación.",
                        404);

                if (candidate.StatusCode == "PUBLISHED"
                    && state.ActivePublication?.PackageId == candidate.PackageId)
                {
                    return state;
                }

                EnsureCandidateReady(candidate);

                var rightsWindow = await ReadRightsWindowAsync(
                    connection, transaction, recordingId, territory, language, token);

                if (!rightsWindow.Allowed)
                {
                    throw new EditorialPublicationLifecycleException(
                        "editorial.publication.rights.scope",
                        "Los derechos vigentes no cubren exactamente el territorio e idioma solicitados.",
                        422);
                }

                await ActivatePackageAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    candidate,
                    territory,
                    language,
                    audience,
                    rightsWindow.ValidTo,
                    ActivateAction,
                    caseId: null,
                    operationId,
                    reason,
                    "editorial.publication.activated.v1",
                    token);

                return await ReadPublicationStateAsync(
                    connection, transaction, recordingId, command.PackageId, token);
            },
            cancellationToken);
    }

    public Task<EditorialCorrectionState> CorrectAsync(
        Guid actorAccountId,
        Guid recordingId,
        CorrectEditorialPublicationCommand command,
        string ifMatch,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(actorAccountId, recordingId);
        ArgumentNullException.ThrowIfNull(command);

        var operationId = NormalizeIdempotencyKey(idempotencyKey);
        var action = NormalizeCorrectionAction(command.ActionCode);
        var reason = NormalizeReason(command.Reason);

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await AcquireLifecycleLockAsync(connection, transaction, recordingId, token);

                if (await IsMatchingCorrectionReplayAsync(
                        connection,
                        transaction,
                        operationId,
                        recordingId,
                        action,
                        command,
                        reason,
                        token))
                {
                    return await ReadCorrectionStateAsync(
                        connection, transaction, recordingId, token);
                }

                var state = await ReadCorrectionStateAsync(
                    connection, transaction, recordingId, token);
                EnsureIfMatch(ifMatch, state.ETag);

                switch (action)
                {
                    case "WITHDRAW":
                        await WithdrawAsync(
                            connection, transaction, actorAccountId, recordingId,
                            state.ActivePublication, operationId, reason, token);
                        break;

                    case "RESTORE":
                    case "REVERT":
                        await RestoreHistoricalAsync(
                            connection, transaction, actorAccountId, recordingId,
                            state.ActivePublication, command.TargetPublicationId,
                            action, operationId, reason, token);
                        break;

                    case "SUBSTITUTE":
                        await SubstituteApprovedPackageAsync(
                            connection, transaction, actorAccountId, recordingId,
                            state.ActivePublication, command, operationId, reason, token);
                        break;
                }

                return await ReadCorrectionStateAsync(
                    connection, transaction, recordingId, token);
            },
            cancellationToken);
    }

    private async Task WithdrawAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        EditorialPublicationSnapshot? active,
        Guid operationId,
        string reason,
        CancellationToken cancellationToken)
    {
        if (active is null)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.correction.active.missing",
                "No existe una publicación activa que retirar.",
                422);
        }

        var caseId = await InsertCorrectionCaseAsync(
            connection, transaction, active.PublicationId, "WITHDRAWAL",
            actorAccountId, reason, cancellationToken);

        const string updateSql = """
            UPDATE editorial.publication
            SET status_code = 'WITHDRAWN',
                active_to = CASE
                    WHEN CURRENT_TIMESTAMP > active_from
                    THEN CURRENT_TIMESTAMP
                    ELSE active_from + INTERVAL '1 microsecond'
                END
            WHERE publication_id = @publication_id
              AND recording_id = @recording_id
              AND status_code = 'ACTIVE';
            """;

        await using (var command = new NpgsqlCommand(updateSql, connection, transaction))
        {
            command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, active.PublicationId);
            command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

            if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
                throw ConcurrentCorrection();
        }

        await InsertPublicationActionAsync(
            connection, transaction, active.PublicationId, caseId, "WITHDRAW",
            "ACTIVE", "WITHDRAWN", actorAccountId, reason, operationId, cancellationToken);

        await WriteAuditAsync(
            connection, transaction, actorAccountId, active.PublicationId,
            "EDITORIAL.PUBLICATION.WITHDRAW", active.ChecksumSha256,
            $"WITHDRAWN|{active.PublicationNo}", reason, operationId,
            "EDITORIAL.CORRECT", cancellationToken);

        await EnqueueEventAsync(
            connection, transaction, active.PublicationId, recordingId, operationId,
            "editorial.publication.withdrawn.v1", "WITHDRAW", cancellationToken);
    }

    private async Task RestoreHistoricalAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        EditorialPublicationSnapshot? active,
        Guid? targetPublicationId,
        string action,
        Guid operationId,
        string reason,
        CancellationToken cancellationToken)
    {
        if (targetPublicationId is null || targetPublicationId == Guid.Empty)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.correction.target-publication.required",
                "Selecciona una publicación histórica exacta.",
                400);
        }

        var target = await ReadPublicationHeaderAsync(
            connection, transaction, recordingId, targetPublicationId.Value, cancellationToken)
            ?? throw new EditorialPublicationLifecycleException(
                "editorial.correction.target-publication.not-found",
                "La publicación histórica seleccionada no pertenece a esta grabación.",
                404);

        if (target.StatusCode == "ACTIVE")
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.correction.target-publication.active",
                "La publicación seleccionada ya está activa.",
                422);
        }

        var targetAvailability = await ReadAvailabilityAsync(
            connection, transaction, target.PublicationId, cancellationToken);

        if (targetAvailability.Count == 0)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.correction.availability.missing",
                "La publicación histórica no conserva disponibilidad que pueda revalidarse.",
                422);
        }

        var restoredAvailability = new List<EditorialPublicationAvailabilitySnapshot>();
        foreach (var availability in targetAvailability)
        {
            if (availability.ValidTo is not null && availability.ValidTo <= DateTime.UtcNow)
            {
                throw new EditorialPublicationLifecycleException(
                    "editorial.correction.availability.expired",
                    "La disponibilidad histórica expiró; crea una nueva publicación con alcance vigente.",
                    422);
            }

            var rights = await ReadRightsWindowAsync(
                connection, transaction, recordingId,
                availability.TerritoryCode, availability.LanguageTag, cancellationToken);

            if (!rights.Allowed)
            {
                throw new EditorialPublicationLifecycleException(
                    "editorial.correction.rights.scope",
                    $"Los derechos actuales ya no cubren {availability.TerritoryCode}.",
                    422);
            }

            restoredAvailability.Add(
                availability with
                {
                    ValidFrom = DateTime.UtcNow,
                    ValidTo = Earlier(availability.ValidTo, rights.ValidTo),
                    StatusCode = "ACTIVE"
                });
        }

        var affectedPublicationId = active?.PublicationId ?? target.PublicationId;
        var caseId = await InsertCorrectionCaseAsync(
            connection, transaction, affectedPublicationId,
            action == "REVERT" ? "REVERSAL" : "RESTORATION",
            actorAccountId, reason, cancellationToken);

        if (active is not null)
        {
            await SupersedePublicationAsync(
                connection, transaction, active.PublicationId, recordingId, cancellationToken);
        }

        var publicationNo = await NextPublicationNoAsync(
            connection, transaction, recordingId, cancellationToken);

        DateTime? publicationActiveTo = null;
        foreach (var availability in restoredAvailability)
            publicationActiveTo = Earlier(publicationActiveTo, availability.ValidTo);

        var newPublicationId = await InsertPublicationAsync(
            connection, transaction, actorAccountId, recordingId,
            target.PackageId, publicationNo, target.Checksum,
            publicationActiveTo, cancellationToken);

        await CopyPublishedComponentsAsync(
            connection, transaction, target.PublicationId, newPublicationId, cancellationToken);

        foreach (var availability in restoredAvailability)
        {
            await InsertAvailabilityAsync(
                connection, transaction, newPublicationId,
                availability.TerritoryCode, availability.LanguageTag,
                availability.AudienceCode, availability.ValidTo, cancellationToken);
        }

        await InsertPublicationActionAsync(
            connection, transaction, newPublicationId, caseId, action,
            active?.StatusCode ?? target.StatusCode, "ACTIVE",
            actorAccountId, reason, operationId, cancellationToken);

        await WriteAuditAsync(
            connection, transaction, actorAccountId, newPublicationId,
            $"EDITORIAL.PUBLICATION.{action}",
            active?.ChecksumSha256 ?? target.ChecksumSha256,
            $"{action}|source:{target.PublicationId:D}|new:{newPublicationId:D}",
            reason, operationId, "EDITORIAL.CORRECT", cancellationToken);

        await EnqueueEventAsync(
            connection, transaction, newPublicationId, recordingId, operationId,
            action == "REVERT"
                ? "editorial.publication.reverted.v1"
                : "editorial.publication.restored.v1",
            action, cancellationToken);
    }

    private async Task SubstituteApprovedPackageAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        EditorialPublicationSnapshot? active,
        CorrectEditorialPublicationCommand command,
        Guid operationId,
        string reason,
        CancellationToken cancellationToken)
    {
        if (active is null)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.correction.active.missing",
                "La sustitución requiere una publicación activa que reemplazar.",
                422);
        }

        if (command.TargetPackageId is null || command.TargetPackageId == Guid.Empty)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.correction.target-package.required",
                "Selecciona un paquete corregido y aprobado.",
                400);
        }

        var territory = NormalizeCode(command.TerritoryCode ?? string.Empty, "territorio");
        var language = NormalizeLanguageTag(command.LanguageTag);
        var audience = NormalizeCode(command.AudienceCode ?? string.Empty, "audiencia");

        var candidate = await BuildCandidateAsync(
            connection, transaction, recordingId, command.TargetPackageId.Value, cancellationToken)
            ?? throw new EditorialPublicationLifecycleException(
                "editorial.correction.target-package.not-found",
                "El paquete corregido no pertenece a esta grabación.",
                404);

        EnsureCandidateReady(candidate);

        var rights = await ReadRightsWindowAsync(
            connection, transaction, recordingId, territory, language, cancellationToken);

        if (!rights.Allowed)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.correction.rights.scope",
                "Los derechos vigentes no cubren la disponibilidad solicitada.",
                422);
        }

        var caseId = await InsertCorrectionCaseAsync(
            connection, transaction, active.PublicationId, "SUBSTITUTION",
            actorAccountId, reason, cancellationToken);

        await ActivatePackageAsync(
            connection, transaction, actorAccountId, recordingId, candidate,
            territory, language, audience, rights.ValidTo,
            "SUBSTITUTE", caseId, operationId, reason,
            "editorial.publication.substituted.v1", cancellationToken);
    }

    private async Task<Guid> ActivatePackageAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        EditorialPublicationCandidateSnapshot candidate,
        string territory,
        string? language,
        string audience,
        DateTime? validTo,
        string actionCode,
        Guid? caseId,
        Guid operationId,
        string reason,
        string eventName,
        CancellationToken cancellationToken)
    {
        var current = await ReadActivePublicationAsync(
            connection, transaction, recordingId, cancellationToken);

        if (current is not null)
        {
            await SupersedePublicationAsync(
                connection, transaction, current.PublicationId, recordingId, cancellationToken);
        }

        var publicationNo = await NextPublicationNoAsync(
            connection, transaction, recordingId, cancellationToken);
        var checksum = Convert.FromHexString(candidate.ChecksumSha256);

        var publicationId = await InsertPublicationAsync(
            connection, transaction, actorAccountId, recordingId,
            candidate.PackageId, publicationNo, checksum, validTo, cancellationToken);

        await CopyPackageComponentsAsync(
            connection, transaction, candidate.PackageId, publicationId, cancellationToken);

        await InsertAvailabilityAsync(
            connection, transaction, publicationId,
            territory, language, audience, validTo, cancellationToken);

        await InsertPublicationActionAsync(
            connection, transaction, publicationId, caseId, actionCode,
            current?.StatusCode ?? candidate.StatusCode, "ACTIVE",
            actorAccountId, reason, operationId, cancellationToken);

        if (candidate.StatusCode == "APPROVED")
        {
            const string packageSql = """
                UPDATE editorial.editorial_package
                SET status_code = 'PUBLISHED'
                WHERE package_id = @package_id
                  AND recording_id = @recording_id
                  AND status_code = 'APPROVED'
                  AND frozen_at IS NOT NULL;
                """;

            await using var packageCommand =
                new NpgsqlCommand(packageSql, connection, transaction);
            packageCommand.Parameters.AddWithValue("package_id", NpgsqlDbType.Uuid, candidate.PackageId);
            packageCommand.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

            if (await packageCommand.ExecuteNonQueryAsync(cancellationToken) != 1)
            {
                throw new EditorialPublicationLifecycleException(
                    "editorial.publication.package.concurrent",
                    "El paquete aprobado cambió durante la publicación; no se confirmó ningún estado parcial.",
                    412);
            }
        }

        await WriteAuditAsync(
            connection, transaction, actorAccountId, publicationId,
            actionCode == ActivateAction
                ? "EDITORIAL.PUBLICATION.ACTIVATE"
                : $"EDITORIAL.PUBLICATION.{actionCode}",
            current?.ChecksumSha256 ?? candidate.ChecksumSha256,
            $"publication:{publicationId:D}|package:{candidate.PackageId:D}|{actionCode}",
            reason, operationId,
            actionCode == ActivateAction ? "EDITORIAL.PUBLISH" : "EDITORIAL.CORRECT",
            cancellationToken);

        await EnqueueEventAsync(
            connection, transaction, publicationId, recordingId, operationId,
            eventName, actionCode, cancellationToken);

        return publicationId;
    }

    private static async Task<EditorialPublicationState> ReadPublicationStateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid? packageId,
        CancellationToken cancellationToken)
    {
        await EnsureRecordingExistsAsync(connection, transaction, recordingId, cancellationToken);

        var candidate = packageId is null
            ? null
            : await BuildCandidateAsync(
                connection, transaction, recordingId, packageId.Value, cancellationToken);

        var active = await ReadActivePublicationAsync(
            connection, transaction, recordingId, cancellationToken);
        var history = await ReadPublicationHistoryAsync(
            connection, transaction, recordingId, cancellationToken);

        var etag = BuildPublicationETag(recordingId, candidate, active, history);

        var message = candidate switch
        {
            null when active is null =>
                "No hay paquete exacto seleccionado ni publicación activa.",
            null =>
                $"La publicación activa es #{active!.PublicationNo}.",
            { ReadyToPublish: true, StatusCode: "APPROVED" } =>
                $"Paquete #{candidate.PackageNo} aprobado y listo para publicación atómica.",
            { StatusCode: "PUBLISHED" } when active?.PackageId == candidate.PackageId =>
                $"Paquete #{candidate.PackageNo} ya está activo como publicación #{active.PublicationNo}.",
            _ =>
                $"El paquete #{candidate.PackageNo} no puede publicarse hasta resolver sus bloqueos."
        };

        return new EditorialPublicationState(
            recordingId, candidate, active, history, etag, message);
    }

    private static async Task<EditorialCorrectionState> ReadCorrectionStateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        await EnsureRecordingExistsAsync(connection, transaction, recordingId, cancellationToken);

        var active = await ReadActivePublicationAsync(
            connection, transaction, recordingId, cancellationToken);
        var history = await ReadPublicationHistoryAsync(
            connection, transaction, recordingId, cancellationToken);
        var actions = await ReadActionsAsync(
            connection, transaction, recordingId, cancellationToken);
        var packages = await ReadApprovedPackagesAsync(
            connection, transaction, recordingId, cancellationToken);

        var etag = BuildCorrectionETag(recordingId, active, history, actions, packages);

        return new EditorialCorrectionState(
            recordingId,
            active,
            history,
            actions,
            packages,
            etag,
            active is null
                ? "No existe publicación activa. Puedes restaurar una histórica si sus derechos siguen vigentes."
                : $"Publicación #{active.PublicationNo} activa. Toda corrección conservará el historial.");
    }

    private static async Task<EditorialPublicationCandidateSnapshot?> BuildCandidateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                p.package_id,
                p.package_no,
                p.status_code,
                p.version,
                p.checksum,
                p.frozen_at,
                EXISTS (
                    SELECT 1
                    FROM editorial.review_submission s
                    JOIN editorial.review_decision d
                      ON d.submission_id = s.submission_id
                    WHERE s.package_id = p.package_id
                      AND s.status_code = 'APPROVED'
                      AND d.decision_code = 'APPROVED'
                )
            FROM editorial.editorial_package p
            WHERE p.recording_id = @recording_id
              AND p.package_id = @package_id;
            """;

        PackageRow? row = null;
        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
            command.Parameters.AddWithValue("package_id", NpgsqlDbType.Uuid, packageId);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                row = new PackageRow(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2),
                    reader.GetInt64(3),
                    (byte[])reader.GetValue(4),
                    reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                    reader.GetBoolean(6));
            }
        }

        if (row is null)
            return null;

        var components = await ReadPackageComponentsAsync(
            connection, transaction, row.PackageId, cancellationToken);
        var issues = new List<string>();

        var frozen = row.FrozenAt is not null;
        if (!frozen)
            issues.Add("El paquete no está congelado.");

        if (row.StatusCode is not ("APPROVED" or "PUBLISHED"))
            issues.Add($"El paquete está en estado {row.StatusCode}; se requiere APPROVED.");

        if (!row.ApprovedReview)
            issues.Add("No existe una decisión APPROVED vinculada al sometimiento exacto.");

        var complete = HasCompleteComponentSet(components);
        if (!complete)
            issues.Add("El conjunto publicado requiere letra, sincronización, traducción, análisis y al menos un ejercicio.");

        var current = await ComponentsAreCurrentAsync(
            connection, transaction, components, cancellationToken);
        if (!current)
            issues.Add("Uno o más checksums ya no coinciden con la revisión exacta congelada.");

        var hasRights = await HasAnyActiveRightsAsync(
            connection, transaction, recordingId, cancellationToken);
        if (!hasRights)
            issues.Add("No existe una autorización vigente con alcance territorial explícito.");

        var ready =
            frozen
            && row.StatusCode == "APPROVED"
            && row.ApprovedReview
            && complete
            && current
            && hasRights;

        return new EditorialPublicationCandidateSnapshot(
            row.PackageId,
            row.PackageNo,
            row.StatusCode,
            row.Version,
            Convert.ToHexString(row.Checksum).ToLowerInvariant(),
            frozen,
            row.ApprovedReview,
            complete,
            current,
            hasRights,
            ready,
            components,
            issues.Distinct(StringComparer.Ordinal).ToArray());
    }

    private static async Task<IReadOnlyList<EditorialPublicationComponentSnapshot>>
        ReadPackageComponentsAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid packageId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                package_component_id,
                COALESCE(
                    lyrics_revision_id,
                    timing_revision_id,
                    translation_revision_id,
                    analysis_revision_id,
                    exercise_revision_id
                ),
                component_kind,
                checksum
            FROM editorial.package_component
            WHERE package_id = @package_id
            ORDER BY
                CASE component_kind
                    WHEN 'LYRICS' THEN 0
                    WHEN 'TIMING' THEN 1
                    WHEN 'TRANSLATION' THEN 2
                    WHEN 'ANALYSIS' THEN 3
                    WHEN 'EXERCISE' THEN 4
                    ELSE 99
                END,
                package_component_id;
            """;

        var results = new List<EditorialPublicationComponentSnapshot>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("package_id", NpgsqlDbType.Uuid, packageId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        var order = 0;
        while (await reader.ReadAsync(cancellationToken))
        {
            if (reader.IsDBNull(1))
            {
                throw new EditorialPublicationLifecycleException(
                    "editorial.publication.component.broken-link",
                    "El paquete aprobado contiene una referencia de componente vacía.",
                    422);
            }

            results.Add(
                new EditorialPublicationComponentSnapshot(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetString(2),
                    Convert.ToHexString((byte[])reader.GetValue(3)).ToLowerInvariant(),
                    order++));
        }

        return results;
    }

    private static bool HasCompleteComponentSet(
        IReadOnlyList<EditorialPublicationComponentSnapshot> components)
    {
        foreach (var kind in RequiredKinds)
        {
            if (components.Count(item => item.ComponentKind == kind) != 1)
                return false;
        }

        return components.Any(item => item.ComponentKind == "EXERCISE");
    }

    private static async Task<bool> ComponentsAreCurrentAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        IReadOnlyList<EditorialPublicationComponentSnapshot> components,
        CancellationToken cancellationToken)
    {
        foreach (var component in components)
        {
            var current = await ReadCurrentComponentChecksumAsync(
                connection, transaction, component.ComponentKind,
                component.SourceRevisionId, cancellationToken);

            if (current is null
                || !string.Equals(
                    current,
                    component.ChecksumSha256,
                    StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        return true;
    }

    private static async Task<string?> ReadCurrentComponentChecksumAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string kind,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        var sql = kind switch
        {
            "LYRICS" =>
                "SELECT encode(checksum, 'hex') FROM content.lyrics_revision WHERE lyrics_revision_id = @revision_id AND status_code NOT IN ('REJECTED','WITHDRAWN','SUPERSEDED');",
            "TIMING" =>
                "SELECT encode(checksum, 'hex') FROM content.timing_revision WHERE timing_revision_id = @revision_id AND status_code NOT IN ('REJECTED','WITHDRAWN','SUPERSEDED');",
            "TRANSLATION" =>
                "SELECT encode(checksum, 'hex') FROM content.translation_revision WHERE translation_revision_id = @revision_id AND status_code NOT IN ('REJECTED','WITHDRAWN','SUPERSEDED');",
            "ANALYSIS" =>
                "SELECT encode(checksum, 'hex') FROM content.linguistic_analysis_revision WHERE analysis_revision_id = @revision_id AND status_code NOT IN ('REJECTED','WITHDRAWN','SUPERSEDED');",
            "EXERCISE" =>
                "SELECT encode(checksum, 'hex') FROM learning.exercise_revision WHERE exercise_revision_id = @revision_id AND status_code NOT IN ('REJECTED','WITHDRAWN','SUPERSEDED');",
            _ => null
        };

        if (sql is null)
            return null;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("revision_id", NpgsqlDbType.Uuid, revisionId);
        return (string?)await command.ExecuteScalarAsync(cancellationToken);
    }

    private static async Task<bool> HasAnyActiveRightsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM editorial.rights_record r
                JOIN editorial.rights_scope s
                  ON s.rights_record_id = r.rights_record_id
                WHERE r.object_type = 'RECORDING'
                  AND r.object_id = @recording_id
                  AND r.status_code = 'ACTIVE'
                  AND (r.valid_from IS NULL OR r.valid_from <= CURRENT_TIMESTAMP)
                  AND (r.valid_to IS NULL OR r.valid_to > CURRENT_TIMESTAMP)
                  AND s.territory_code IS NOT NULL
                  AND s.channel_code = 'WEB'
                  AND s.use_code = 'DISPLAY'
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    private static async Task<RightsWindow> ReadRightsWindowAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        string territory,
        string? language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT r.valid_to
            FROM editorial.rights_record r
            JOIN editorial.rights_scope s
              ON s.rights_record_id = r.rights_record_id
            WHERE r.object_type = 'RECORDING'
              AND r.object_id = @recording_id
              AND r.status_code = 'ACTIVE'
              AND (r.valid_from IS NULL OR r.valid_from <= CURRENT_TIMESTAMP)
              AND (r.valid_to IS NULL OR r.valid_to > CURRENT_TIMESTAMP)
              AND s.territory_code = @territory
              AND s.channel_code = 'WEB'
              AND s.use_code = 'DISPLAY'
              AND (
                  s.language_tag IS NULL
                  OR (
                      @language IS NOT NULL
                      AND lower(s.language_tag) = lower(@language)
                  )
              )
            ORDER BY
                CASE WHEN r.valid_to IS NULL THEN 0 ELSE 1 END,
                r.valid_to DESC
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue("territory", territory);
        command.Parameters.Add(
            new NpgsqlParameter("language", NpgsqlDbType.Varchar)
            {
                Value = language is null ? DBNull.Value : language
            });

        var result = await command.ExecuteScalarAsync(cancellationToken);

        if (result is null)
            return new RightsWindow(false, null);

        return result is DBNull
            ? new RightsWindow(true, null)
            : new RightsWindow(true, (DateTime)result);
    }

    private static async Task<EditorialPublicationSnapshot?> ReadActivePublicationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                p.publication_id,
                p.package_id,
                p.publication_no,
                p.status_code,
                p.active_from,
                p.active_to,
                p.published_at,
                p.checksum
            FROM editorial.publication p
            WHERE p.recording_id = @recording_id
              AND p.status_code = 'ACTIVE'
              AND p.active_from <= CURRENT_TIMESTAMP
              AND (p.active_to IS NULL OR p.active_to > CURRENT_TIMESTAMP)
            ORDER BY p.publication_no DESC, p.publication_id DESC;
            """;

        var rows = new List<PublicationHeader>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
            rows.Add(ReadPublicationHeader(reader));

        if (rows.Count > 1)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.multiple-active",
                "Existe más de una publicación activa. La operación se bloqueó para evitar mezclar estados.");
        }

        if (rows.Count == 0)
            return null;

        return await ToSnapshotAsync(connection, transaction, rows[0], cancellationToken);
    }

    private static async Task<PublicationHeader?> ReadPublicationHeaderAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid publicationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                p.publication_id,
                p.package_id,
                p.publication_no,
                p.status_code,
                p.active_from,
                p.active_to,
                p.published_at,
                p.checksum
            FROM editorial.publication p
            WHERE p.recording_id = @recording_id
              AND p.publication_id = @publication_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? ReadPublicationHeader(reader) : null;
    }

    private static async Task<IReadOnlyList<EditorialPublicationSnapshot>>
        ReadPublicationHistoryAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid recordingId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                p.publication_id,
                p.package_id,
                p.publication_no,
                p.status_code,
                p.active_from,
                p.active_to,
                p.published_at,
                p.checksum
            FROM editorial.publication p
            WHERE p.recording_id = @recording_id
            ORDER BY p.publication_no DESC, p.publication_id DESC;
            """;

        var headers = new List<PublicationHeader>();
        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
                headers.Add(ReadPublicationHeader(reader));
        }

        var results = new List<EditorialPublicationSnapshot>(headers.Count);
        foreach (var header in headers)
            results.Add(await ToSnapshotAsync(connection, transaction, header, cancellationToken));

        return results;
    }

    private static PublicationHeader ReadPublicationHeader(NpgsqlDataReader reader) =>
        new(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetInt32(2),
            reader.GetString(3),
            reader.GetDateTime(4),
            reader.IsDBNull(5) ? null : reader.GetDateTime(5),
            reader.GetDateTime(6),
            (byte[])reader.GetValue(7));

    private static async Task<EditorialPublicationSnapshot> ToSnapshotAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        PublicationHeader header,
        CancellationToken cancellationToken)
    {
        var availability = await ReadAvailabilityAsync(
            connection, transaction, header.PublicationId, cancellationToken);

        return new EditorialPublicationSnapshot(
            header.PublicationId,
            header.PackageId,
            header.PublicationNo,
            header.StatusCode,
            header.ActiveFrom,
            header.ActiveTo,
            header.PublishedAt,
            header.ChecksumSha256,
            availability);
    }

    private static async Task<IReadOnlyList<EditorialPublicationAvailabilitySnapshot>>
        ReadAvailabilityAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid publicationId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT territory_code, language_tag, audience_code, valid_from, valid_to, status_code
            FROM editorial.publication_availability
            WHERE publication_id = @publication_id
            ORDER BY territory_code, language_tag NULLS FIRST, audience_code;
            """;

        var results = new List<EditorialPublicationAvailabilitySnapshot>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(
                new EditorialPublicationAvailabilitySnapshot(
                    reader.GetString(0),
                    reader.IsDBNull(1) ? null : reader.GetString(1),
                    reader.GetString(2),
                    reader.GetDateTime(3),
                    reader.IsDBNull(4) ? null : reader.GetDateTime(4),
                    reader.GetString(5)));
        }

        return results;
    }

    private static async Task<IReadOnlyList<EditorialPublicationActionSnapshot>>
        ReadActionsAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid recordingId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                a.action_id,
                a.publication_id,
                a.case_id,
                a.action_code,
                a.from_status,
                a.to_status,
                a.effective_at,
                a.reason,
                a.correlation_id
            FROM editorial.publication_action a
            JOIN editorial.publication p
              ON p.publication_id = a.publication_id
            WHERE p.recording_id = @recording_id
            ORDER BY a.effective_at DESC, a.action_id DESC;
            """;

        var results = new List<EditorialPublicationActionSnapshot>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(
                new EditorialPublicationActionSnapshot(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.IsDBNull(2) ? null : reader.GetGuid(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetDateTime(6),
                    reader.GetString(7),
                    reader.GetGuid(8)));
        }

        return results;
    }

    private static async Task<IReadOnlyList<EditorialApprovedPackageOption>>
        ReadApprovedPackagesAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid recordingId,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT p.package_id, p.package_no, encode(p.checksum, 'hex')
            FROM editorial.editorial_package p
            WHERE p.recording_id = @recording_id
              AND p.status_code = 'APPROVED'
              AND p.frozen_at IS NOT NULL
              AND EXISTS (
                  SELECT 1
                  FROM editorial.review_submission s
                  JOIN editorial.review_decision d
                    ON d.submission_id = s.submission_id
                  WHERE s.package_id = p.package_id
                    AND s.status_code = 'APPROVED'
                    AND d.decision_code = 'APPROVED'
              )
            ORDER BY p.package_no DESC, p.package_id DESC;
            """;

        var results = new List<EditorialApprovedPackageOption>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(
                new EditorialApprovedPackageOption(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2)));
        }

        return results;
    }

    private static async Task<Guid> InsertPublicationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        Guid packageId,
        int publicationNo,
        byte[] checksum,
        DateTime? activeTo,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.publication (
                recording_id,
                package_id,
                publication_no,
                status_code,
                active_from,
                active_to,
                published_by,
                published_at,
                checksum
            )
            VALUES (
                @recording_id,
                @package_id,
                @publication_no,
                'ACTIVE',
                CURRENT_TIMESTAMP,
                @active_to,
                @actor_id,
                CURRENT_TIMESTAMP,
                @checksum
            )
            RETURNING publication_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue("package_id", NpgsqlDbType.Uuid, packageId);
        command.Parameters.AddWithValue("publication_no", NpgsqlDbType.Integer, publicationNo);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);
        command.Parameters.AddWithValue("checksum", NpgsqlDbType.Bytea, checksum);
        command.Parameters.Add(
            new NpgsqlParameter("active_to", NpgsqlDbType.TimestampTz)
            {
                Value = activeTo is null ? DBNull.Value : activeTo
            });

        return (Guid)(await command.ExecuteScalarAsync(cancellationToken)
            ?? throw new InvalidOperationException("No se pudo crear la publicación atómica."));
    }

    private static async Task CopyPackageComponentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        Guid publicationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.publication_component (
                publication_id,
                component_kind,
                source_component_id,
                component_checksum,
                display_order
            )
            SELECT
                @publication_id,
                pc.component_kind,
                pc.package_component_id,
                pc.checksum,
                (
                    row_number() OVER (
                        ORDER BY
                            CASE pc.component_kind
                                WHEN 'LYRICS' THEN 0
                                WHEN 'TIMING' THEN 1
                                WHEN 'TRANSLATION' THEN 2
                                WHEN 'ANALYSIS' THEN 3
                                WHEN 'EXERCISE' THEN 4
                                ELSE 99
                            END,
                            pc.package_component_id
                    ) - 1
                )::integer
            FROM editorial.package_component pc
            WHERE pc.package_id = @package_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        command.Parameters.AddWithValue("package_id", NpgsqlDbType.Uuid, packageId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) <= 0)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.components.empty",
                "El paquete no produjo componentes publicables.",
                422);
        }
    }

    private static async Task CopyPublishedComponentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid sourcePublicationId,
        Guid targetPublicationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.publication_component (
                publication_id,
                component_kind,
                source_component_id,
                component_checksum,
                display_order
            )
            SELECT
                @target_publication_id,
                component_kind,
                source_component_id,
                component_checksum,
                display_order
            FROM editorial.publication_component
            WHERE publication_id = @source_publication_id
            ORDER BY display_order, publication_component_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("target_publication_id", NpgsqlDbType.Uuid, targetPublicationId);
        command.Parameters.AddWithValue("source_publication_id", NpgsqlDbType.Uuid, sourcePublicationId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) <= 0)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.correction.components.empty",
                "La publicación histórica no conserva su instantánea de componentes.",
                422);
        }
    }

    private static async Task InsertAvailabilityAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid publicationId,
        string territory,
        string? language,
        string audience,
        DateTime? validTo,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.publication_availability (
                publication_id,
                territory_code,
                language_tag,
                audience_code,
                valid_from,
                valid_to,
                status_code
            )
            VALUES (
                @publication_id,
                @territory,
                @language,
                @audience,
                CURRENT_TIMESTAMP,
                @valid_to,
                'ACTIVE'
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        command.Parameters.AddWithValue("territory", territory);
        command.Parameters.Add(
            new NpgsqlParameter("language", NpgsqlDbType.Varchar)
            {
                Value = language is null ? DBNull.Value : language
            });
        command.Parameters.AddWithValue("audience", audience);
        command.Parameters.Add(
            new NpgsqlParameter("valid_to", NpgsqlDbType.TimestampTz)
            {
                Value = validTo is null ? DBNull.Value : validTo
            });

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task SupersedePublicationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid publicationId,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE editorial.publication
            SET status_code = 'SUPERSEDED',
                active_to = CASE
                    WHEN CURRENT_TIMESTAMP > active_from
                    THEN CURRENT_TIMESTAMP
                    ELSE active_from + INTERVAL '1 microsecond'
                END
            WHERE publication_id = @publication_id
              AND recording_id = @recording_id
              AND status_code = 'ACTIVE';
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
            throw ConcurrentCorrection();
    }

    private static async Task<int> NextPublicationNoAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT COALESCE(MAX(publication_no), 0) + 1
            FROM editorial.publication
            WHERE recording_id = @recording_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        return Convert.ToInt32(
            await command.ExecuteScalarAsync(cancellationToken) ?? 1,
            System.Globalization.CultureInfo.InvariantCulture);
    }

    private static async Task<Guid> InsertCorrectionCaseAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid publicationId,
        string caseType,
        Guid actorAccountId,
        string reason,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.correction_case (
                publication_id,
                case_type,
                status_code,
                reason,
                opened_by,
                opened_at,
                resolved_at
            )
            VALUES (
                @publication_id,
                @case_type,
                'RESOLVED',
                @reason,
                @actor_id,
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP
            )
            RETURNING case_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        command.Parameters.AddWithValue("case_type", caseType);
        command.Parameters.AddWithValue("reason", reason);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);

        return (Guid)(await command.ExecuteScalarAsync(cancellationToken)
            ?? throw new InvalidOperationException("No se pudo registrar el expediente de corrección."));
    }

    private static async Task InsertPublicationActionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid publicationId,
        Guid? caseId,
        string actionCode,
        string fromStatus,
        string toStatus,
        Guid actorAccountId,
        string reason,
        Guid operationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.publication_action (
                publication_id,
                case_id,
                action_code,
                from_status,
                to_status,
                effective_at,
                actor_id,
                reason,
                correlation_id
            )
            VALUES (
                @publication_id,
                @case_id,
                @action_code,
                @from_status,
                @to_status,
                CURRENT_TIMESTAMP,
                @actor_id,
                @reason,
                @correlation_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        command.Parameters.Add(
            new NpgsqlParameter("case_id", NpgsqlDbType.Uuid)
            {
                Value = caseId is null ? DBNull.Value : caseId.Value
            });
        command.Parameters.AddWithValue("action_code", actionCode);
        command.Parameters.AddWithValue("from_status", fromStatus);
        command.Parameters.AddWithValue("to_status", toStatus);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);
        command.Parameters.AddWithValue("reason", reason);
        command.Parameters.AddWithValue("correlation_id", NpgsqlDbType.Uuid, operationId);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<bool> IsMatchingPublishReplayAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid operationId,
        Guid recordingId,
        Guid packageId,
        string territory,
        string? language,
        string audience,
        string reason,
        CancellationToken cancellationToken)
    {
        var replay = await ReadReplayActionAsync(
            connection, transaction, operationId, ActivateAction, cancellationToken);

        if (replay is null)
            return false;

        var availabilityMatches = await PublicationHasAvailabilityAsync(
            connection,
            transaction,
            replay.PublicationId,
            territory,
            language,
            audience,
            cancellationToken);

        if (replay.RecordingId != recordingId
            || replay.PackageId != packageId
            || !string.Equals(replay.Reason, reason, StringComparison.Ordinal)
            || !availabilityMatches)
        {
            throw IdempotencyConflict();
        }

        return true;
    }

    private static async Task<bool> IsMatchingCorrectionReplayAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid operationId,
        Guid recordingId,
        string actionCode,
        CorrectEditorialPublicationCommand command,
        string reason,
        CancellationToken cancellationToken)
    {
        var replay = await ReadReplayActionAsync(
            connection, transaction, operationId, actionCode, cancellationToken);

        if (replay is null)
            return false;

        if (replay.RecordingId != recordingId
            || !string.Equals(replay.Reason, reason, StringComparison.Ordinal))
        {
            throw IdempotencyConflict();
        }

        if (actionCode == "SUBSTITUTE")
        {
            if (command.TargetPackageId is null
                || command.TargetPackageId == Guid.Empty
                || replay.PackageId != command.TargetPackageId.Value)
            {
                throw IdempotencyConflict();
            }

            var territory = NormalizeCode(
                command.TerritoryCode ?? string.Empty,
                "territorio");
            var language = NormalizeLanguageTag(command.LanguageTag);
            var audience = NormalizeCode(
                command.AudienceCode ?? string.Empty,
                "audiencia");

            if (!await PublicationHasAvailabilityAsync(
                    connection,
                    transaction,
                    replay.PublicationId,
                    territory,
                    language,
                    audience,
                    cancellationToken))
            {
                throw IdempotencyConflict();
            }
        }

        if (actionCode is "RESTORE" or "REVERT")
        {
            if (command.TargetPublicationId is null
                || command.TargetPublicationId == Guid.Empty)
            {
                throw IdempotencyConflict();
            }

            var target = await ReadPublicationHeaderAsync(
                connection,
                transaction,
                recordingId,
                command.TargetPublicationId.Value,
                cancellationToken);

            if (target is null || target.PackageId != replay.PackageId)
                throw IdempotencyConflict();
        }

        return true;
    }

    private static async Task<ReplayActionRow?> ReadReplayActionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid operationId,
        string actionCode,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                a.publication_id,
                p.recording_id,
                p.package_id,
                a.reason
            FROM editorial.publication_action a
            JOIN editorial.publication p
              ON p.publication_id = a.publication_id
            WHERE a.correlation_id = @correlation_id
              AND a.action_code = @action_code;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("correlation_id", NpgsqlDbType.Uuid, operationId);
        command.Parameters.AddWithValue("action_code", actionCode);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
            return null;

        return new ReplayActionRow(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2),
            reader.GetString(3));
    }

    private static async Task<bool> PublicationHasAvailabilityAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid publicationId,
        string territory,
        string? language,
        string audience,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM editorial.publication_availability
                WHERE publication_id = @publication_id
                  AND territory_code = @territory
                  AND audience_code = @audience
                  AND (
                      (language_tag IS NULL AND @language IS NULL)
                      OR (
                          language_tag IS NOT NULL
                          AND @language IS NOT NULL
                          AND lower(language_tag) = lower(@language)
                      )
                  )
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        command.Parameters.AddWithValue("territory", territory);
        command.Parameters.AddWithValue("audience", audience);
        command.Parameters.Add(
            new NpgsqlParameter("language", NpgsqlDbType.Varchar)
            {
                Value = language is null ? DBNull.Value : language
            });

        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    private async Task EnqueueEventAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid publicationId,
        Guid recordingId,
        Guid operationId,
        string eventName,
        string actionCode,
        CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.Serialize(new
        {
            schemaVersion = 1,
            publicationId,
            recordingId,
            actionCode
        });

        var draft = OutboxMessageDraft.Create(
            eventName,
            schemaVersion: 1,
            aggregateType: "EDITORIAL_PUBLICATION",
            aggregateId: publicationId,
            payloadJson: payload,
            correlationId: operationId);

        await outbox.EnqueueAsync(connection, transaction, draft, cancellationToken);
    }

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid publicationId,
        string actionCode,
        string beforeMaterial,
        string afterMaterial,
        string reason,
        Guid operationId,
        string permissionCode,
        CancellationToken cancellationToken)
    {
        var roleCode = await ReadAuditRoleCodeAsync(
            connection, transaction, actorAccountId, permissionCode, cancellationToken);

        var before = SHA256.HashData(Encoding.UTF8.GetBytes(beforeMaterial));
        var after = SHA256.HashData(Encoding.UTF8.GetBytes(afterMaterial));

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
                'EDITORIAL_PUBLICATION',
                @publication_id,
                @action_code,
                @before_digest,
                @after_digest,
                @reason,
                CURRENT_TIMESTAMP,
                @correlation_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);
        command.Parameters.AddWithValue("role_code", roleCode);
        command.Parameters.AddWithValue("publication_id", NpgsqlDbType.Uuid, publicationId);
        command.Parameters.AddWithValue("action_code", actionCode);
        command.Parameters.AddWithValue("before_digest", NpgsqlDbType.Bytea, before);
        command.Parameters.AddWithValue("after_digest", NpgsqlDbType.Bytea, after);
        command.Parameters.AddWithValue("reason", reason);
        command.Parameters.AddWithValue("correlation_id", NpgsqlDbType.Uuid, operationId);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<string> ReadAuditRoleCodeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        string permissionCode,
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
              AND p.permission_code = @permission_code
              AND r.status_code = 'ACTIVE'
              AND a.valid_from <= CURRENT_TIMESTAMP
              AND (a.valid_to IS NULL OR a.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL OR rp.valid_to > CURRENT_TIMESTAMP)
            ORDER BY r.role_code
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);
        command.Parameters.AddWithValue("permission_code", permissionCode);

        return (string?)(await command.ExecuteScalarAsync(cancellationToken))
            ?? throw new EditorialPublicationLifecycleException(
                "editorial.publication.audit-role.missing",
                "No se pudo resolver un rol vigente para registrar la acción privilegiada.",
                403);
    }

    private static async Task EnsureRecordingExistsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.recording
                WHERE recording_id = @recording_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        if (!((bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false)))
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.recording.not-found",
                "La grabación editorial solicitada no existe.",
                404);
        }
    }

    private static async Task AcquireLifecycleLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql =
            "SELECT pg_advisory_xact_lock(hashtextextended(@key, 0));";

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "key",
            $"EDITORIAL-PUBLICATION-LIFECYCLE:{recordingId:D}");
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static string BuildPublicationETag(
        Guid recordingId,
        EditorialPublicationCandidateSnapshot? candidate,
        EditorialPublicationSnapshot? active,
        IReadOnlyList<EditorialPublicationSnapshot> history)
    {
        var material = new StringBuilder(recordingId.ToString("N"));

        if (candidate is not null)
        {
            material.Append('|');
            material.Append(candidate.PackageId.ToString("N"));
            material.Append('|');
            material.Append(candidate.Version);
            material.Append('|');
            material.Append(candidate.StatusCode);
            material.Append('|');
            material.Append(candidate.ChecksumSha256);
        }

        AppendActive(material, active);
        material.Append("|history:");
        material.Append(history.Count);

        return HashETag("publication", material.ToString());
    }

    private static string BuildCorrectionETag(
        Guid recordingId,
        EditorialPublicationSnapshot? active,
        IReadOnlyList<EditorialPublicationSnapshot> history,
        IReadOnlyList<EditorialPublicationActionSnapshot> actions,
        IReadOnlyList<EditorialApprovedPackageOption> packages)
    {
        var material = new StringBuilder(recordingId.ToString("N"));
        AppendActive(material, active);

        foreach (var publication in history)
        {
            material.Append('|');
            material.Append(publication.PublicationId.ToString("N"));
            material.Append(':');
            material.Append(publication.StatusCode);
        }

        foreach (var action in actions)
        {
            material.Append('|');
            material.Append(action.ActionId.ToString("N"));
            material.Append(':');
            material.Append(action.ActionCode);
        }

        foreach (var package in packages)
        {
            material.Append('|');
            material.Append(package.PackageId.ToString("N"));
            material.Append(':');
            material.Append(package.ChecksumSha256);
        }

        return HashETag("correction", material.ToString());
    }

    private static void AppendActive(
        StringBuilder material,
        EditorialPublicationSnapshot? active)
    {
        material.Append("|active:");
        if (active is null)
        {
            material.Append("none");
            return;
        }

        material.Append(active.PublicationId.ToString("N"));
        material.Append(':');
        material.Append(active.StatusCode);
        material.Append(':');
        material.Append(active.ChecksumSha256);
    }

    private static string HashETag(string prefix, string material)
    {
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(material));
        return $"\"{prefix}-{Convert.ToHexString(digest).ToLowerInvariant()}\"";
    }

    private static void EnsureIfMatch(string ifMatch, string expected)
    {
        if (string.IsNullOrWhiteSpace(ifMatch))
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.precondition.required",
                "Recarga el estado antes de confirmar esta acción.",
                428);
        }

        if (!string.Equals(ifMatch.Trim(), expected, StringComparison.Ordinal))
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.precondition.failed",
                "La publicación cambió. Recarga el impacto antes de confirmar.",
                412);
        }
    }

    private static void EnsureCandidateReady(
        EditorialPublicationCandidateSnapshot candidate)
    {
        if (!candidate.ReadyToPublish)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.candidate.blocked",
                candidate.Issues.Count == 0
                    ? "El paquete no cumple las condiciones de publicación."
                    : candidate.Issues[0],
                422);
        }
    }

    private static Guid NormalizeIdempotencyKey(string value)
    {
        if (!Guid.TryParse(value?.Trim(), out var key) || key == Guid.Empty)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.idempotency-key.invalid",
                "La confirmación requiere una Idempotency-Key UUID válida.",
                400);
        }

        return key;
    }

    private static string NormalizeCorrectionAction(string value)
    {
        var code = value?.Trim().ToUpperInvariant();

        return code switch
        {
            "WITHDRAW" => "WITHDRAW",
            "RESTORE" => "RESTORE",
            "REVERT" => "REVERT",
            "SUBSTITUTE" => "SUBSTITUTE",
            _ => throw new EditorialPublicationLifecycleException(
                "editorial.correction.action.invalid",
                "Usa WITHDRAW, RESTORE, REVERT o SUBSTITUTE.",
                400)
        };
    }

    private static string NormalizeCode(string value, string label)
    {
        var normalized = value?.Trim().ToUpperInvariant() ?? string.Empty;

        if (normalized.Length is < 1 or > 64
            || !IsCodeChar(normalized[0], first: true)
            || normalized.Skip(1).Any(character => !IsCodeChar(character, first: false)))
        {
            throw new EditorialPublicationLifecycleException(
                $"editorial.publication.{label}.invalid",
                $"El {label} no cumple el formato de código permitido.",
                400);
        }

        return normalized;
    }

    private static bool IsCodeChar(char value, bool first) =>
        char.IsAsciiLetterOrDigit(value)
        || (!first && value is '.' or '_' or '-');

    private static string? NormalizeLanguageTag(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return null;

        var normalized = value.Trim();
        var parts = normalized.Split('-', StringSplitOptions.None);

        if (normalized.Length > 35
            || parts.Length == 0
            || parts[0].Length is < 2 or > 8
            || !parts[0].All(char.IsAsciiLetter)
            || parts.Skip(1).Any(part =>
                part.Length is < 1 or > 8
                || !part.All(char.IsAsciiLetterOrDigit)))
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.language.invalid",
                "El idioma no cumple el formato BCP-47 mínimo.",
                400);
        }

        return normalized;
    }

    private static string NormalizeReason(string value)
    {
        var reason = value?.Trim();

        if (string.IsNullOrWhiteSpace(reason))
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.reason.required",
                "Indica un motivo explícito para la acción privilegiada.",
                400);
        }

        if (reason.Length > 2000)
        {
            throw new EditorialPublicationLifecycleException(
                "editorial.publication.reason.too-long",
                "El motivo no puede superar 2000 caracteres.",
                400);
        }

        return reason;
    }

    private static DateTime? Earlier(DateTime? left, DateTime? right)
    {
        if (left is null) return right;
        if (right is null) return left;
        return left <= right ? left : right;
    }

    private static EditorialPublicationLifecycleException ConcurrentCorrection() =>
        new(
            "editorial.correction.concurrent",
            "La publicación cambió mientras confirmabas. Recarga antes de continuar.",
            412);

    private static EditorialPublicationLifecycleException IdempotencyConflict() =>
        new(
            "editorial.publication.idempotency-key.conflict",
            "La Idempotency-Key ya fue usada con una solicitud diferente.",
            409);

    private static void ValidateIdentity(Guid actorAccountId, Guid recordingId)
    {
        if (actorAccountId == Guid.Empty)
            throw new ArgumentException("Actor inválido.", nameof(actorAccountId));
        if (recordingId == Guid.Empty)
            throw new ArgumentException("Grabación inválida.", nameof(recordingId));
    }

    private sealed record PackageRow(
        Guid PackageId,
        int PackageNo,
        string StatusCode,
        long Version,
        byte[] Checksum,
        DateTime? FrozenAt,
        bool ApprovedReview);

    private sealed record PublicationHeader(
        Guid PublicationId,
        Guid PackageId,
        int PublicationNo,
        string StatusCode,
        DateTime ActiveFrom,
        DateTime? ActiveTo,
        DateTime PublishedAt,
        byte[] Checksum)
    {
        public string ChecksumSha256 =>
            Convert.ToHexString(Checksum).ToLowerInvariant();
    }

    private sealed record RightsWindow(bool Allowed, DateTime? ValidTo);

    private sealed record ReplayActionRow(
        Guid PublicationId,
        Guid RecordingId,
        Guid PackageId,
        string Reason);
}
