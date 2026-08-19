using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Editorial.Infrastructure.Administration;

public sealed record EditorialReviewComponent(
    string ComponentKind,
    string ChecksumSha256);

public sealed record EditorialReviewerCandidate(
    Guid AccountId,
    string Label,
    bool Eligible,
    string? IneligibilityReason);

public sealed record EditorialReviewAssignmentSnapshot(
    Guid AssignmentId,
    Guid ReviewerId,
    string ReviewerLabel,
    string ScopeCode,
    DateTime AssignedAt,
    DateTime? DueAt,
    bool ConflictDeclared,
    bool IsCurrent);

public sealed record EditorialReviewDecisionSnapshot(
    Guid DecisionId,
    Guid AssignmentId,
    string DecisionCode,
    string Reason,
    DateTime DecidedAt,
    JsonElement ChecklistResult);

public sealed record EditorialReviewChecklist(
    bool PackageFrozen,
    bool SubmissionOpen,
    bool ComponentSetComplete,
    bool ComponentChecksumsPresent,
    bool ActiveRights,
    bool ConflictFree,
    bool ReadyForApproval,
    IReadOnlyList<string> Issues);

public sealed record EditorialReviewWorkflowSnapshot(
    Guid RecordingId,
    Guid PackageId,
    int PackageNo,
    string PackageStatusCode,
    long PackageVersion,
    string PackageChecksumSha256,
    DateTime FrozenAt,
    Guid SubmissionId,
    Guid SubmittedBy,
    DateTime SubmittedAt,
    string SubmissionStatusCode,
    string ChecklistVersion,
    IReadOnlyList<EditorialReviewComponent> Components,
    IReadOnlyList<EditorialReviewerCandidate> ReviewerCandidates,
    IReadOnlyList<EditorialReviewAssignmentSnapshot> Assignments,
    IReadOnlyList<EditorialReviewDecisionSnapshot> Decisions,
    EditorialReviewChecklist Checklist,
    bool ActorIsCurrentReviewer,
    bool CurrentReviewerHasConflict,
    string ETag,
    string Message);

public sealed record AssignEditorialReviewerCommand(
    Guid ReviewerId,
    DateTimeOffset? DueAt,
    string Reason);

public sealed record DeclareEditorialReviewConflictCommand(
    string Reason);

public sealed record DecideEditorialReviewCommand(
    string DecisionCode,
    string Reason);

public sealed class EditorialReviewWorkflowException(
    string code,
    string message,
    int statusCode = 409) : Exception(message)
{
    public string Code { get; } = code;
    public int StatusCode { get; } = statusCode;
}

public sealed class EditorialReviewWorkflowService(
    ICompatibleEducationalPackageTransactionExecutor transactions)
{
    private const string ReviewScopeCode = "PACKAGE";

    public Task<EditorialReviewWorkflowSnapshot> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIds(actorAccountId, recordingId);

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
                await ReadStateAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    token),
            cancellationToken);
    }

    public Task<EditorialReviewWorkflowSnapshot> AssignAsync(
        Guid actorAccountId,
        Guid recordingId,
        string ifMatch,
        AssignEditorialReviewerCommand command,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIds(actorAccountId, recordingId);
        ArgumentNullException.ThrowIfNull(command);

        var reason = NormalizeReason(command.Reason);
        if (command.ReviewerId == Guid.Empty)
        {
            throw new EditorialReviewWorkflowException(
                "editorial.review.reviewer.required",
                "Selecciona un revisor explícito.",
                400);
        }

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await AcquireReviewLockAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                var state = await ReadStateAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    token);

                EnsureIfMatch(ifMatch, state.ETag);
                EnsureSubmissionOpen(state);

                if (state.Decisions.Count > 0)
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.already-decided",
                        "La revisión ya tiene una decisión final. Una reconsideración requiere un flujo posterior autorizado.");
                }

                var candidate = state.ReviewerCandidates.SingleOrDefault(
                    item => item.AccountId == command.ReviewerId);

                if (candidate is null || !candidate.Eligible)
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.reviewer.ineligible",
                        candidate?.IneligibilityReason
                            ?? "La cuenta seleccionada no posee EDITORIAL.REVIEW vigente para esta canción.",
                        422);
                }

                if (state.Assignments.Any(item =>
                        item.ReviewerId == command.ReviewerId
                        && string.Equals(
                            item.ScopeCode,
                            ReviewScopeCode,
                            StringComparison.Ordinal)))
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.assignment.duplicate",
                        "Ese revisor ya fue asignado a esta presentación. Selecciona otra persona si necesitas reasignar.");
                }

                var dueAt = command.DueAt?.UtcDateTime;
                if (dueAt is not null && dueAt <= DateTime.UtcNow)
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.assignment.due-date",
                        "La fecha límite debe ser posterior al momento de asignación.",
                        400);
                }

                const string insertSql = """
                    INSERT INTO editorial.review_assignment (
                        submission_id,
                        reviewer_id,
                        scope_code,
                        assigned_at,
                        due_at,
                        conflict_declared
                    )
                    VALUES (
                        @submission_id,
                        @reviewer_id,
                        @scope_code,
                        CURRENT_TIMESTAMP,
                        @due_at,
                        false
                    )
                    RETURNING assignment_id;
                    """;

                Guid assignmentId;
                await using (var commandSql =
                             new NpgsqlCommand(insertSql, connection, transaction))
                {
                    commandSql.Parameters.AddWithValue(
                        "submission_id",
                        NpgsqlDbType.Uuid,
                        state.SubmissionId);
                    commandSql.Parameters.AddWithValue(
                        "reviewer_id",
                        NpgsqlDbType.Uuid,
                        command.ReviewerId);
                    commandSql.Parameters.AddWithValue(
                        "scope_code",
                        ReviewScopeCode);
                    commandSql.Parameters.Add(
                        new NpgsqlParameter("due_at", NpgsqlDbType.TimestampTz)
                        {
                            Value = dueAt is null ? DBNull.Value : dueAt
                        });

                    assignmentId = (Guid)(await commandSql.ExecuteScalarAsync(token)
                        ?? throw new InvalidOperationException(
                            "No se pudo crear la asignación editorial."));
                }

                await WriteAuditAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    state.PackageId,
                    "EDITORIAL.REVIEW.ASSIGN",
                    reason,
                    correlationId,
                    $"assignment:{assignmentId:D}",
                    token);

                return await ReadStateAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    token);
            },
            cancellationToken);
    }

    public Task<EditorialReviewWorkflowSnapshot> DeclareConflictAsync(
        Guid actorAccountId,
        Guid recordingId,
        string ifMatch,
        DeclareEditorialReviewConflictCommand command,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIds(actorAccountId, recordingId);
        ArgumentNullException.ThrowIfNull(command);
        var reason = NormalizeReason(command.Reason);

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await AcquireReviewLockAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                var state = await ReadStateAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    token);

                EnsureIfMatch(ifMatch, state.ETag);
                EnsureSubmissionOpen(state);

                var current = state.Assignments.SingleOrDefault(item => item.IsCurrent)
                    ?? throw new EditorialReviewWorkflowException(
                        "editorial.review.assignment.missing",
                        "No existe una asignación activa para declarar conflicto.");

                if (current.ReviewerId != actorAccountId)
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.conflict.not-reviewer",
                        "Solo el revisor actualmente asignado puede declarar su conflicto de interés.",
                        403);
                }

                if (state.Decisions.Any(item => item.AssignmentId == current.AssignmentId))
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.conflict.after-decision",
                        "No se puede declarar conflicto después de una decisión final.");
                }

                if (!current.ConflictDeclared)
                {
                    const string sql = """
                        UPDATE editorial.review_assignment
                        SET conflict_declared = true
                        WHERE assignment_id = @assignment_id
                          AND reviewer_id = @reviewer_id
                          AND conflict_declared = false;
                        """;

                    await using var update = new NpgsqlCommand(sql, connection, transaction);
                    update.Parameters.AddWithValue(
                        "assignment_id",
                        NpgsqlDbType.Uuid,
                        current.AssignmentId);
                    update.Parameters.AddWithValue(
                        "reviewer_id",
                        NpgsqlDbType.Uuid,
                        actorAccountId);

                    if (await update.ExecuteNonQueryAsync(token) != 1)
                    {
                        throw new EditorialReviewWorkflowException(
                            "editorial.review.conflict.concurrent",
                            "La asignación cambió mientras declarabas el conflicto. Recarga antes de continuar.",
                            412);
                    }

                    await WriteAuditAsync(
                        connection,
                        transaction,
                        actorAccountId,
                        state.PackageId,
                        "EDITORIAL.REVIEW.CONFLICT",
                        reason,
                        correlationId,
                        $"assignment:{current.AssignmentId:D}|conflict:true",
                        token);
                }

                return await ReadStateAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    token);
            },
            cancellationToken);
    }

    public Task<EditorialReviewWorkflowSnapshot> DecideAsync(
        Guid actorAccountId,
        Guid recordingId,
        string ifMatch,
        DecideEditorialReviewCommand command,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIds(actorAccountId, recordingId);
        ArgumentNullException.ThrowIfNull(command);

        var decisionCode = NormalizeDecision(command.DecisionCode);
        var reason = NormalizeReason(command.Reason);

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await AcquireReviewLockAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                var state = await ReadStateAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    token);

                EnsureIfMatch(ifMatch, state.ETag);
                EnsureSubmissionOpen(state);

                var assignment = state.Assignments.SingleOrDefault(item => item.IsCurrent)
                    ?? throw new EditorialReviewWorkflowException(
                        "editorial.review.assignment.missing",
                        "La presentación necesita un revisor explícitamente asignado.");

                if (assignment.ReviewerId != actorAccountId)
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.decision.not-assigned",
                        "Solo el revisor actualmente asignado puede decidir sobre este paquete.",
                        403);
                }

                if (assignment.ConflictDeclared)
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.decision.conflict",
                        "El conflicto declarado bloquea la decisión. Debe reasignarse la revisión.");
                }

                if (state.Decisions.Any(item => item.AssignmentId == assignment.AssignmentId))
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.decision.duplicate",
                        "La asignación ya tiene una decisión final. Las decisiones no se reescriben.");
                }

                if (decisionCode == "APPROVED" && !state.Checklist.ReadyForApproval)
                {
                    throw new EditorialReviewWorkflowException(
                        "editorial.review.checklist.failed",
                        "El checklist todavía contiene bloqueos. No se puede aprobar hasta resolverlos.",
                        422);
                }

                var checklistJson = JsonSerializer.Serialize(new
                {
                    schemaVersion = 1,
                    checklistVersion = state.ChecklistVersion,
                    packageFrozen = state.Checklist.PackageFrozen,
                    submissionOpen = state.Checklist.SubmissionOpen,
                    componentSetComplete = state.Checklist.ComponentSetComplete,
                    componentChecksumsPresent = state.Checklist.ComponentChecksumsPresent,
                    activeRights = state.Checklist.ActiveRights,
                    conflictFree = state.Checklist.ConflictFree,
                    readyForApproval = state.Checklist.ReadyForApproval,
                    issues = state.Checklist.Issues
                });

                const string insertDecisionSql = """
                    INSERT INTO editorial.review_decision (
                        submission_id,
                        assignment_id,
                        decision_code,
                        reason,
                        decided_at,
                        checklist_result
                    )
                    VALUES (
                        @submission_id,
                        @assignment_id,
                        @decision_code,
                        @reason,
                        CURRENT_TIMESTAMP,
                        @checklist_result::jsonb
                    )
                    RETURNING decision_id;
                    """;

                Guid decisionId;
                await using (var insert =
                             new NpgsqlCommand(
                                 insertDecisionSql,
                                 connection,
                                 transaction))
                {
                    insert.Parameters.AddWithValue(
                        "submission_id",
                        NpgsqlDbType.Uuid,
                        state.SubmissionId);
                    insert.Parameters.AddWithValue(
                        "assignment_id",
                        NpgsqlDbType.Uuid,
                        assignment.AssignmentId);
                    insert.Parameters.AddWithValue(
                        "decision_code",
                        decisionCode);
                    insert.Parameters.AddWithValue(
                        "reason",
                        reason);
                    insert.Parameters.AddWithValue(
                        "checklist_result",
                        checklistJson);

                    decisionId = (Guid)(await insert.ExecuteScalarAsync(token)
                        ?? throw new InvalidOperationException(
                            "No se pudo registrar la decisión editorial."));
                }

                const string moveStateSql = """
                    UPDATE editorial.review_submission
                    SET status_code = @status_code
                    WHERE submission_id = @submission_id
                      AND status_code = 'SUBMITTED';

                    UPDATE editorial.editorial_package
                    SET status_code = @status_code
                    WHERE package_id = @package_id
                      AND status_code = 'SUBMITTED'
                      AND frozen_at IS NOT NULL;
                    """;

                await using (var move =
                             new NpgsqlCommand(
                                 moveStateSql,
                                 connection,
                                 transaction))
                {
                    move.Parameters.AddWithValue(
                        "status_code",
                        decisionCode);
                    move.Parameters.AddWithValue(
                        "submission_id",
                        NpgsqlDbType.Uuid,
                        state.SubmissionId);
                    move.Parameters.AddWithValue(
                        "package_id",
                        NpgsqlDbType.Uuid,
                        state.PackageId);

                    var changed = await move.ExecuteNonQueryAsync(token);
                    if (changed != 2)
                    {
                        throw new EditorialReviewWorkflowException(
                            "editorial.review.decision.concurrent",
                            "La presentación cambió durante la decisión. No se creó publicación y debes recargar.",
                            412);
                    }
                }

                await WriteAuditAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    state.PackageId,
                    "EDITORIAL.REVIEW.DECIDE",
                    reason,
                    correlationId,
                    $"decision:{decisionId:D}|{decisionCode}",
                    token);

                return await ReadStateAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    token);
            },
            cancellationToken);
    }

    private static async Task<EditorialReviewWorkflowSnapshot> ReadStateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        var headers = await ReadHeadersAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        if (headers.Count == 0)
        {
            throw new EditorialReviewWorkflowException(
                "editorial.review.submission.not-found",
                "Todavía no existe un paquete congelado y sometido para esta canción.",
                404);
        }

        if (headers.Count(item =>
                item.PackageStatusCode == "SUBMITTED"
                && item.SubmissionStatusCode == "SUBMITTED") > 1)
        {
            throw new EditorialReviewWorkflowException(
                "editorial.review.submission.ambiguous",
                "Existe más de una presentación abierta para la misma canción. La revisión se bloqueó de forma segura.");
        }

        var header = headers.FirstOrDefault(item =>
                item.PackageStatusCode == "SUBMITTED"
                && item.SubmissionStatusCode == "SUBMITTED")
            ?? headers[0];

        var components = await ReadComponentsAsync(
            connection,
            transaction,
            header.PackageId,
            cancellationToken);

        var assignments = await ReadAssignmentsAsync(
            connection,
            transaction,
            header.SubmissionId,
            cancellationToken);

        var decisions = await ReadDecisionsAsync(
            connection,
            transaction,
            header.SubmissionId,
            cancellationToken);

        var reviewerCandidates = await ReadReviewerCandidatesAsync(
            connection,
            transaction,
            recordingId,
            header.SubmittedBy,
            header.PackageCreatedBy,
            cancellationToken);

        var activeRights = await HasActiveRightsAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var currentAssignment = assignments.LastOrDefault();
        var assignmentSnapshots = assignments
            .Select((item, index) =>
                new EditorialReviewAssignmentSnapshot(
                    item.AssignmentId,
                    item.ReviewerId,
                    item.ReviewerLabel,
                    item.ScopeCode,
                    item.AssignedAt,
                    item.DueAt,
                    item.ConflictDeclared,
                    index == assignments.Count - 1))
            .ToArray();

        var decisionSnapshots = decisions
            .Select(item =>
                new EditorialReviewDecisionSnapshot(
                    item.DecisionId,
                    item.AssignmentId,
                    item.DecisionCode,
                    item.Reason,
                    item.DecidedAt,
                    JsonDocument.Parse(item.ChecklistResultJson)
                        .RootElement.Clone()))
            .ToArray();

        var issues = new List<string>();
        var packageFrozen = header.FrozenAt is not null;
        var submissionOpen =
            header.PackageStatusCode == "SUBMITTED"
            && header.SubmissionStatusCode == "SUBMITTED";

        var counts = components
            .GroupBy(item => item.ComponentKind, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.Count(),
                StringComparer.Ordinal);

        var componentSetComplete =
            counts.GetValueOrDefault("LYRICS") == 1
            && counts.GetValueOrDefault("TIMING") == 1
            && counts.GetValueOrDefault("TRANSLATION") == 1
            && counts.GetValueOrDefault("ANALYSIS") == 1
            && counts.GetValueOrDefault("EXERCISE") >= 1
            && counts.All(pair =>
                pair.Key == "EXERCISE"
                || pair.Value == 1);

        var componentChecksumsPresent =
            components.Count > 0
            && components.All(item => item.ChecksumSha256.Length >= 32)
            && header.PackageChecksum.Length >= 16;

        if (!packageFrozen)
            issues.Add("El paquete no conserva frozen_at.");
        if (!submissionOpen && decisions.Count == 0)
            issues.Add("La presentación ya no está abierta.");
        if (!componentSetComplete)
            issues.Add("El paquete congelado no contiene exactamente las capas P0 esperadas.");
        if (!componentChecksumsPresent)
            issues.Add("Uno o más componentes no conservan checksum verificable.");
        if (!activeRights)
            issues.Add("Los derechos vigentes dejaron de cubrir la grabación.");

        var conflictFree =
            currentAssignment is null || !currentAssignment.ConflictDeclared;

        if (!conflictFree)
            issues.Add("El revisor actual declaró conflicto de interés; debe reasignarse.");

        var readyForApproval =
            packageFrozen
            && submissionOpen
            && componentSetComplete
            && componentChecksumsPresent
            && activeRights
            && conflictFree
            && currentAssignment is not null
            && decisions.Count == 0;

        var checklist = new EditorialReviewChecklist(
            packageFrozen,
            submissionOpen,
            componentSetComplete,
            componentChecksumsPresent,
            activeRights,
            conflictFree,
            readyForApproval,
            issues);

        var etag = BuildETag(
            header,
            components,
            assignments,
            decisions);

        var message = decisions.LastOrDefault() is { } lastDecision
            ? $"Decisión {lastDecision.DecisionCode} registrada de forma append-only. BL-MVP-049 no publica."
            : currentAssignment?.ConflictDeclared == true
                ? "La revisión está bloqueada por conflicto de interés. Asigna otro revisor."
                : currentAssignment is not null
                    ? "Revisor explícito asignado. El paquete sigue congelado y sin publicar."
                    : "Presentación lista para asignar un revisor independiente.";

        return new EditorialReviewWorkflowSnapshot(
            recordingId,
            header.PackageId,
            header.PackageNo,
            header.PackageStatusCode,
            header.PackageVersion,
            Convert.ToHexString(header.PackageChecksum).ToLowerInvariant(),
            header.FrozenAt
                ?? throw new EditorialReviewWorkflowException(
                    "editorial.review.package.not-frozen",
                    "La presentación no apunta a un paquete congelado."),
            header.SubmissionId,
            header.SubmittedBy,
            header.SubmittedAt,
            header.SubmissionStatusCode,
            header.ChecklistVersion,
            components,
            reviewerCandidates,
            assignmentSnapshots,
            decisionSnapshots,
            checklist,
            currentAssignment?.ReviewerId == actorAccountId,
            currentAssignment?.ConflictDeclared == true,
            etag,
            message);
    }

    private static async Task<IReadOnlyList<ReviewHeader>> ReadHeadersAsync(
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
                p.created_by,
                p.frozen_at,
                p.checksum,
                p.version,
                s.submission_id,
                s.submitted_by,
                s.submitted_at,
                s.status_code,
                s.checklist_version
            FROM editorial.editorial_package p
            JOIN editorial.review_submission s
              ON s.package_id = p.package_id
            WHERE p.recording_id = @recording_id
              AND p.frozen_at IS NOT NULL
              AND p.status_code IN ('SUBMITTED', 'APPROVED', 'REJECTED', 'PUBLISHED')
            ORDER BY
                CASE WHEN p.status_code = 'SUBMITTED'
                       AND s.status_code = 'SUBMITTED'
                     THEN 0 ELSE 1 END,
                p.package_no DESC,
                s.submitted_at DESC,
                s.submission_id DESC;
            """;

        var rows = new List<ReviewHeader>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new ReviewHeader(
                reader.GetGuid(0),
                reader.GetInt32(1),
                reader.GetString(2),
                reader.GetGuid(3),
                reader.IsDBNull(4) ? null : reader.GetDateTime(4),
                (byte[])reader.GetValue(5),
                reader.GetInt64(6),
                reader.GetGuid(7),
                reader.GetGuid(8),
                reader.GetDateTime(9),
                reader.GetString(10),
                reader.GetString(11)));
        }

        return rows;
    }

    private static async Task<IReadOnlyList<EditorialReviewComponent>> ReadComponentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT component_kind, encode(checksum, 'hex')
            FROM editorial.package_component
            WHERE package_id = @package_id
            ORDER BY component_kind, package_component_id;
            """;

        var rows = new List<EditorialReviewComponent>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new EditorialReviewComponent(
                reader.GetString(0),
                reader.GetString(1)));
        }

        return rows;
    }

    private static async Task<List<AssignmentRow>> ReadAssignmentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid submissionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                assignment.assignment_id,
                assignment.reviewer_id,
                CASE
                    WHEN profile.username IS NOT NULL
                        THEN '@' || profile.username
                    WHEN NULLIF(btrim(profile.display_name), '') IS NOT NULL
                        THEN btrim(profile.display_name)
                    ELSE 'Cuenta '
                        || left(
                            replace(assignment.reviewer_id::text, '-', ''),
                            8
                        )
                END AS reviewer_label,
                assignment.scope_code,
                assignment.assigned_at,
                assignment.due_at,
                assignment.conflict_declared
            FROM editorial.review_assignment AS assignment
            LEFT JOIN identity.user_profile AS profile
              ON profile.account_id = assignment.reviewer_id
            WHERE assignment.submission_id = @submission_id
            ORDER BY assignment.assigned_at, assignment.assignment_id;
            """;

        var rows = new List<AssignmentRow>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "submission_id",
            NpgsqlDbType.Uuid,
            submissionId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new AssignmentRow(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetDateTime(4),
                reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                reader.GetBoolean(6)));
        }

        return rows;
    }

    private static async Task<List<DecisionRow>> ReadDecisionsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid submissionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                decision_id,
                assignment_id,
                decision_code,
                reason,
                decided_at,
                checklist_result::text
            FROM editorial.review_decision
            WHERE submission_id = @submission_id
            ORDER BY decided_at, decision_id;
            """;

        var rows = new List<DecisionRow>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "submission_id",
            NpgsqlDbType.Uuid,
            submissionId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new DecisionRow(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetDateTime(4),
                reader.GetString(5)));
        }

        return rows;
    }

    private static async Task<IReadOnlyList<EditorialReviewerCandidate>>
        ReadReviewerCandidatesAsync(
            NpgsqlConnection connection,
            NpgsqlTransaction transaction,
            Guid recordingId,
            Guid submittedBy,
            Guid packageCreatedBy,
            CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT DISTINCT
                a.account_id,
                CASE
                    WHEN profile.username IS NOT NULL
                        THEN '@' || profile.username
                    WHEN NULLIF(btrim(profile.display_name), '') IS NOT NULL
                        THEN btrim(profile.display_name)
                    ELSE 'Cuenta '
                        || left(
                            replace(a.account_id::text, '-', ''),
                            8
                        )
                END AS reviewer_label
            FROM security.account a
            LEFT JOIN identity.user_profile AS profile
              ON profile.account_id = a.account_id
            JOIN security.role_assignment ra
              ON ra.account_id = a.account_id
            JOIN security.role r
              ON r.role_id = ra.role_id
            JOIN security.role_permission rp
              ON rp.role_id = r.role_id
            JOIN security.permission p
              ON p.permission_id = rp.permission_id
            LEFT JOIN security.access_scope s
              ON s.scope_id = ra.scope_id
            WHERE a.status_code = 'ACTIVE'
              AND r.status_code = 'ACTIVE'
              AND p.permission_code = 'EDITORIAL.REVIEW'
              AND ra.valid_from <= CURRENT_TIMESTAMP
              AND (ra.valid_to IS NULL OR ra.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL OR rp.valid_to > CURRENT_TIMESTAMP)
              AND (
                    ra.scope_id IS NULL
                    OR s.scope_type = 'GLOBAL'
                    OR (
                        s.scope_type = 'MODULE'
                        AND s.module_code = 'M15'
                        AND s.object_id IS NULL
                    )
                    OR (
                        s.scope_type = 'OBJECT'
                        AND (s.module_code IS NULL OR s.module_code = 'M15')
                        AND s.object_id = @recording_id
                    )
              )
            ORDER BY a.account_id;
            """;

        var rows = new List<EditorialReviewerCandidate>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var accountId = reader.GetGuid(0);
            var reviewerLabel = reader.GetString(1);
            var reason = accountId == submittedBy
                ? "Quien sometió el paquete no puede revisar su propia presentación."
                : accountId == packageCreatedBy
                    ? "Quien creó el paquete no puede actuar como revisor independiente."
                    : null;

            rows.Add(new EditorialReviewerCandidate(
                accountId,
                reviewerLabel,
                reason is null,
                reason));
        }

        return rows;
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
                FROM editorial.rights_record r
                WHERE r.object_type = 'RECORDING'
                  AND r.object_id = @recording_id
                  AND r.status_code = 'ACTIVE'
                  AND (r.valid_from IS NULL OR r.valid_from <= CURRENT_TIMESTAMP)
                  AND (r.valid_to IS NULL OR r.valid_to > CURRENT_TIMESTAMP)
                  AND EXISTS (
                      SELECT 1
                      FROM editorial.rights_scope s
                      WHERE s.rights_record_id = r.rights_record_id
                  )
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static async Task AcquireReviewLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT pg_advisory_xact_lock(hashtextextended(@key, 0));",
            connection,
            transaction);
        command.Parameters.AddWithValue(
            "key",
            $"EDITORIAL-REVIEW:{recordingId:D}");
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static void EnsureSubmissionOpen(
        EditorialReviewWorkflowSnapshot state)
    {
        if (state.PackageStatusCode != "SUBMITTED"
            || state.SubmissionStatusCode != "SUBMITTED")
        {
            throw new EditorialReviewWorkflowException(
                "editorial.review.submission.closed",
                "La presentación ya fue decidida y no admite nuevas acciones ordinarias.");
        }
    }

    private static void EnsureIfMatch(
        string ifMatch,
        string currentEtag)
    {
        if (string.IsNullOrWhiteSpace(ifMatch))
        {
            throw new EditorialReviewWorkflowException(
                "editorial.review.precondition.required",
                "La operación requiere If-Match con la versión visible de la revisión.",
                428);
        }

        if (!string.Equals(
                ifMatch.Trim(),
                currentEtag,
                StringComparison.Ordinal))
        {
            throw new EditorialReviewWorkflowException(
                "editorial.review.precondition.failed",
                "La revisión cambió. Recarga el checklist y confirma nuevamente.",
                412);
        }
    }

    private static string BuildETag(
        ReviewHeader header,
        IReadOnlyList<EditorialReviewComponent> components,
        IReadOnlyList<AssignmentRow> assignments,
        IReadOnlyList<DecisionRow> decisions)
    {
        var material = new StringBuilder();
        material.Append(header.PackageId.ToString("N"));
        material.Append('|');
        material.Append(header.PackageVersion);
        material.Append('|');
        material.Append(header.PackageStatusCode);
        material.Append('|');
        material.Append(header.SubmissionId.ToString("N"));
        material.Append('|');
        material.Append(header.SubmissionStatusCode);

        foreach (var component in components)
        {
            material.Append('|');
            material.Append(component.ComponentKind);
            material.Append(':');
            material.Append(component.ChecksumSha256);
        }

        foreach (var assignment in assignments)
        {
            material.Append('|');
            material.Append(assignment.AssignmentId.ToString("N"));
            material.Append(':');
            material.Append(assignment.ReviewerId.ToString("N"));
            material.Append(':');
            material.Append(assignment.ConflictDeclared ? '1' : '0');
        }

        foreach (var decision in decisions)
        {
            material.Append('|');
            material.Append(decision.DecisionId.ToString("N"));
            material.Append(':');
            material.Append(decision.DecisionCode);
        }

        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(material.ToString()));

        return $"\"review-{Convert.ToHexString(digest).ToLowerInvariant()}\"";
    }

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid packageId,
        string actionCode,
        string reason,
        string correlationId,
        string afterMaterial,
        CancellationToken cancellationToken)
    {
        var roleCode = await ReadAuditRoleCodeAsync(
            connection,
            transaction,
            actorAccountId,
            cancellationToken);

        var before = SHA256.HashData(
            Encoding.UTF8.GetBytes($"{packageId:D}|{actionCode}|before"));
        var after = SHA256.HashData(
            Encoding.UTF8.GetBytes($"{packageId:D}|{actionCode}|{afterMaterial}"));

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
        command.Parameters.AddWithValue("package_id", NpgsqlDbType.Uuid, packageId);
        command.Parameters.AddWithValue("action_code", actionCode);
        command.Parameters.AddWithValue("before_digest", NpgsqlDbType.Bytea, before);
        command.Parameters.AddWithValue("after_digest", NpgsqlDbType.Bytea, after);
        command.Parameters.AddWithValue("reason", reason);
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
              AND p.permission_code IN ('EDITORIAL.PUBLISH', 'EDITORIAL.REVIEW')
              AND r.status_code = 'ACTIVE'
              AND a.valid_from <= CURRENT_TIMESTAMP
              AND (a.valid_to IS NULL OR a.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL OR rp.valid_to > CURRENT_TIMESTAMP)
            ORDER BY CASE p.permission_code
                WHEN 'EDITORIAL.PUBLISH' THEN 0
                ELSE 1
            END, r.role_code
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);

        return (string?)(await command.ExecuteScalarAsync(cancellationToken))
            ?? throw new InvalidOperationException(
                "No se pudo resolver un rol vigente para auditar la revisión.");
    }


    private static string NormalizeDecision(string value)
    {
        var code = value?.Trim().ToUpperInvariant();

        return code switch
        {
            "APPROVED" => "APPROVED",
            "REJECTED" => "REJECTED",
            _ => throw new EditorialReviewWorkflowException(
                "editorial.review.decision.invalid",
                "La decisión debe ser APPROVED o REJECTED.",
                400)
        };
    }

    private static string NormalizeReason(string value)
    {
        var reason = value?.Trim();

        if (string.IsNullOrWhiteSpace(reason))
        {
            throw new EditorialReviewWorkflowException(
                "editorial.review.reason.required",
                "Indica un motivo explicable y accionable.",
                400);
        }

        if (reason.Length > 2000)
        {
            throw new EditorialReviewWorkflowException(
                "editorial.review.reason.too-long",
                "El motivo no puede superar 2000 caracteres.",
                400);
        }

        return reason;
    }

    private static Guid CorrelationGuid(string correlationId)
    {
        if (Guid.TryParse(correlationId, out var parsed)
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

    private static void ValidateIds(
        Guid actorAccountId,
        Guid recordingId)
    {
        if (actorAccountId == Guid.Empty)
            throw new ArgumentException("Actor inválido.", nameof(actorAccountId));
        if (recordingId == Guid.Empty)
            throw new ArgumentException("Grabación inválida.", nameof(recordingId));
    }

    private sealed record ReviewHeader(
        Guid PackageId,
        int PackageNo,
        string PackageStatusCode,
        Guid PackageCreatedBy,
        DateTime? FrozenAt,
        byte[] PackageChecksum,
        long PackageVersion,
        Guid SubmissionId,
        Guid SubmittedBy,
        DateTime SubmittedAt,
        string SubmissionStatusCode,
        string ChecklistVersion);

    private sealed record AssignmentRow(
        Guid AssignmentId,
        Guid ReviewerId,
        string ReviewerLabel,
        string ScopeCode,
        DateTime AssignedAt,
        DateTime? DueAt,
        bool ConflictDeclared);

    private sealed record DecisionRow(
        Guid DecisionId,
        Guid AssignmentId,
        string DecisionCode,
        string Reason,
        DateTime DecidedAt,
        string ChecklistResultJson);
}
