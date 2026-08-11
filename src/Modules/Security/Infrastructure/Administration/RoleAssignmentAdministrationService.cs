using System.Security.Cryptography;
using System.Text;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Administration;

public sealed record RoleAssignmentScopeView(
    Guid ScopeId,
    string ScopeType,
    string? ModuleCode,
    Guid? ObjectId);

public sealed record RoleAssignmentCatalog(
    IReadOnlyList<string> Roles,
    IReadOnlyList<RoleAssignmentScopeView> Scopes);

public sealed record RoleAssignmentView(
    Guid AssignmentId,
    Guid AccountId,
    string RoleCode,
    RoleAssignmentScopeView? Scope,
    DateTimeOffset ValidFrom,
    DateTimeOffset? ValidTo,
    string Reason,
    string State);

public sealed record GrantRoleAssignmentCommand(
    Guid AccountId,
    string RoleCode,
    Guid? ScopeId,
    DateTimeOffset? ValidUntil,
    string Reason);

public sealed record RevokeRoleAssignmentCommand(
    Guid AssignmentId,
    string Reason);

public sealed record RoleAssignmentMutation(
    RoleAssignmentView Assignment,
    bool AlreadyApplied);

public sealed class RoleAssignmentAdministrationException(
    string code,
    string message) : Exception(message)
{
    public string Code { get; } = code;
}

public sealed class RoleAssignmentAdministrationService(
    IPrivilegedSecurityTransactionExecutor executor)
{
    private const string ManageRolesPermission = "SECURITY.MANAGE_ROLES";
    private const string ObjectType = "ROLE_ASSIGNMENT";
    private const string GrantAction = "SECURITY.ROLE_ASSIGNMENT.GRANT";
    private const string RevokeAction = "SECURITY.ROLE_ASSIGNMENT.REVOKE";

    public Task<RoleAssignmentCatalog> ReadCatalogAsync(
        Guid actorAccountId,
        string correlationId,
        CancellationToken cancellationToken = default) =>
        executor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                _ = await RequireManagingRoleAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    token);

                var roles = new List<string>();
                await using (var roleCommand = new NpgsqlCommand(
                    """
                    SELECT role_code
                    FROM security.role
                    WHERE status_code = 'ACTIVE'
                    ORDER BY role_code;
                    """,
                    connection,
                    transaction))
                await using (var reader =
                    await roleCommand.ExecuteReaderAsync(token))
                {
                    while (await reader.ReadAsync(token))
                    {
                        roles.Add(reader.GetString(0));
                    }
                }

                var scopes = new List<RoleAssignmentScopeView>();
                await using (var scopeCommand = new NpgsqlCommand(
                    """
                    SELECT scope_id, scope_type, module_code, object_id
                    FROM security.access_scope
                    ORDER BY scope_type, module_code NULLS FIRST, object_id NULLS FIRST, scope_id;
                    """,
                    connection,
                    transaction))
                await using (var reader =
                    await scopeCommand.ExecuteReaderAsync(token))
                {
                    while (await reader.ReadAsync(token))
                    {
                        scopes.Add(ReadScope(reader));
                    }
                }

                return new RoleAssignmentCatalog(roles, scopes);
            },
            cancellationToken);

    public Task<IReadOnlyList<RoleAssignmentView>> ListAsync(
        Guid actorAccountId,
        Guid targetAccountId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (targetAccountId == Guid.Empty)
        {
            throw Invalid(
                "security.role-assignment.target.invalid",
                "La cuenta objetivo no es válida.");
        }

        return executor.ExecuteAsync<IReadOnlyList<RoleAssignmentView>>(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                _ = await RequireManagingRoleAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    token);

                const string sql = """
                    SELECT
                        ra.assignment_id,
                        ra.account_id,
                        r.role_code,
                        s.scope_id,
                        s.scope_type,
                        s.module_code,
                        s.object_id,
                        ra.valid_from,
                        ra.valid_to,
                        ra.reason,
                        CASE
                            WHEN ra.valid_from > CURRENT_TIMESTAMP THEN 'SCHEDULED'
                            WHEN ra.valid_to IS NOT NULL
                                 AND ra.valid_to <= CURRENT_TIMESTAMP THEN 'EXPIRED'
                            ELSE 'ACTIVE'
                        END AS state_code
                    FROM security.role_assignment ra
                    JOIN security.role r
                      ON r.role_id = ra.role_id
                    LEFT JOIN security.access_scope s
                      ON s.scope_id = ra.scope_id
                    WHERE ra.account_id = @account_id
                    ORDER BY ra.valid_from DESC, ra.assignment_id DESC
                    LIMIT 100;
                    """;

                await using var command =
                    new NpgsqlCommand(sql, connection, transaction);
                command.Parameters.AddWithValue(
                    "account_id",
                    NpgsqlDbType.Uuid,
                    targetAccountId);

                var result = new List<RoleAssignmentView>();
                await using var reader =
                    await command.ExecuteReaderAsync(token);

                while (await reader.ReadAsync(token))
                {
                    result.Add(ReadAssignment(reader));
                }

                return result;
            },
            cancellationToken);
    }

    public Task<RoleAssignmentMutation> GrantAsync(
        Guid actorAccountId,
        GrantRoleAssignmentCommand request,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateGrant(actorAccountId, request);

        return executor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                var managingRole = await RequireManagingRoleAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    token);

                await RequireActiveTargetAsync(
                    connection,
                    transaction,
                    request.AccountId,
                    token);

                var roleId = await ResolveActiveRoleAsync(
                    connection,
                    transaction,
                    request.RoleCode,
                    token);

                if (request.ScopeId.HasValue)
                {
                    _ = await ResolveScopeAsync(
                        connection,
                        transaction,
                        request.ScopeId.Value,
                        token);
                }

                var normalizedReason = NormalizeReason(request.Reason);
                var validUntil = request.ValidUntil?.ToUniversalTime();

                var existing = await FindOverlappingAsync(
                    connection,
                    transaction,
                    request.AccountId,
                    roleId,
                    request.ScopeId,
                    validUntil,
                    token);

                if (existing is not null)
                {
                    if (SameGrant(existing, validUntil, normalizedReason))
                    {
                        return new RoleAssignmentMutation(
                            existing,
                            AlreadyApplied: true);
                    }

                    throw Invalid(
                        "security.role-assignment.overlap",
                        "Ya existe una asignación que se solapa para el mismo sujeto, rol y alcance.");
                }

                const string insertSql = """
                    INSERT INTO security.role_assignment (
                        account_id,
                        role_id,
                        scope_id,
                        valid_from,
                        valid_to,
                        reason
                    )
                    VALUES (
                        @account_id,
                        @role_id,
                        @scope_id,
                        CURRENT_TIMESTAMP,
                        @valid_to,
                        @reason
                    )
                    RETURNING assignment_id;
                    """;

                Guid assignmentId;
                try
                {
                    await using var insert =
                        new NpgsqlCommand(insertSql, connection, transaction);
                    insert.Parameters.AddWithValue(
                        "account_id",
                        NpgsqlDbType.Uuid,
                        request.AccountId);
                    insert.Parameters.AddWithValue(
                        "role_id",
                        NpgsqlDbType.Uuid,
                        roleId);
                    insert.Parameters.Add(
                        NullableUuid("scope_id", request.ScopeId));
                    insert.Parameters.Add(
                        NullableTimestamp("valid_to", validUntil));
                    insert.Parameters.AddWithValue(
                        "reason",
                        NpgsqlDbType.Text,
                        normalizedReason);

                    assignmentId = (Guid)(
                        await insert.ExecuteScalarAsync(token)
                        ?? throw new InvalidOperationException(
                            "No se obtuvo assignment_id."));
                }
                catch (PostgresException exception)
                    when (exception.SqlState == "23P01")
                {
                    throw Invalid(
                        "security.role-assignment.overlap",
                        "La asignación se solapa con otra vigencia existente.");
                }

                var created = await ReadByIdAsync(
                    connection,
                    transaction,
                    assignmentId,
                    token)
                    ?? throw new InvalidOperationException(
                        "La asignación creada no pudo releerse.");

                await InsertAuditAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    managingRole,
                    GrantAction,
                    created.AssignmentId,
                    beforeDigest: null,
                    afterDigest: Digest(created),
                    normalizedReason,
                    ResolveCorrelationGuid(correlationId),
                    token);

                return new RoleAssignmentMutation(
                    created,
                    AlreadyApplied: false);
            },
            cancellationToken);
    }

    public Task<RoleAssignmentMutation> RevokeAsync(
        Guid actorAccountId,
        RevokeRoleAssignmentCommand request,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (request.AssignmentId == Guid.Empty)
        {
            throw Invalid(
                "security.role-assignment.id.invalid",
                "La asignación no es válida.");
        }

        var revokeReason = NormalizeReason(request.Reason);

        return executor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                var managingRole = await RequireManagingRoleAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    token);

                var before = await ReadByIdForUpdateAsync(
                    connection,
                    transaction,
                    request.AssignmentId,
                    token)
                    ?? throw Invalid(
                        "security.role-assignment.not-found",
                        "La asignación solicitada no existe.");

                if (before.AccountId == actorAccountId)
                {
                    throw Invalid(
                        "security.role-assignment.self-change",
                        "Un administrador no puede cambiar sus propias asignaciones.");
                }

                var now = await ReadDatabaseNowAsync(
                    connection,
                    transaction,
                    token);

                if (before.ValidTo.HasValue
                    && before.ValidTo.Value <= now)
                {
                    return new RoleAssignmentMutation(
                        before,
                        AlreadyApplied: true);
                }

                if (before.ValidFrom > now)
                {
                    throw Invalid(
                        "security.role-assignment.future-revoke",
                        "Una asignación futura creada fuera de este flujo debe cancelarse mediante un procedimiento administrativo compatible.");
                }

                const string updateSql = """
                    UPDATE security.role_assignment
                    SET valid_to = CURRENT_TIMESTAMP
                    WHERE assignment_id = @assignment_id;
                    """;

                await using (var update =
                    new NpgsqlCommand(updateSql, connection, transaction))
                {
                    update.Parameters.AddWithValue(
                        "assignment_id",
                        NpgsqlDbType.Uuid,
                        request.AssignmentId);

                    if (await update.ExecuteNonQueryAsync(token) != 1)
                    {
                        throw new InvalidOperationException(
                            "No se actualizó exactamente una asignación.");
                    }
                }

                var after = await ReadByIdAsync(
                    connection,
                    transaction,
                    request.AssignmentId,
                    token)
                    ?? throw new InvalidOperationException(
                        "La asignación revocada no pudo releerse.");

                await InsertAuditAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    managingRole,
                    RevokeAction,
                    after.AssignmentId,
                    Digest(before),
                    Digest(after),
                    revokeReason,
                    ResolveCorrelationGuid(correlationId),
                    token);

                return new RoleAssignmentMutation(
                    after,
                    AlreadyApplied: false);
            },
            cancellationToken);
    }

    private static void ValidateGrant(
        Guid actorAccountId,
        GrantRoleAssignmentCommand request)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (request.AccountId == Guid.Empty)
        {
            throw Invalid(
                "security.role-assignment.target.invalid",
                "La cuenta objetivo no es válida.");
        }

        if (actorAccountId == request.AccountId)
        {
            throw Invalid(
                "security.role-assignment.self-change",
                "Un administrador no puede ampliar ni modificar sus propias asignaciones.");
        }

        _ = NormalizeCode(request.RoleCode, "rol");
        _ = NormalizeReason(request.Reason);

        if (request.ValidUntil.HasValue
            && request.ValidUntil.Value <= DateTimeOffset.UtcNow)
        {
            throw Invalid(
                "security.role-assignment.validity.invalid",
                "La vigencia final debe ser posterior al momento actual.");
        }
    }

    private static async Task<string> RequireManagingRoleAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT r.role_code
            FROM security.role_assignment ra
            JOIN security.role r
              ON r.role_id = ra.role_id
            JOIN security.role_permission rp
              ON rp.role_id = r.role_id
            JOIN security.permission p
              ON p.permission_id = rp.permission_id
            LEFT JOIN security.access_scope s
              ON s.scope_id = ra.scope_id
            WHERE ra.account_id = @actor_id
              AND r.status_code = 'ACTIVE'
              AND p.permission_code = @permission_code
              AND ra.valid_from <= CURRENT_TIMESTAMP
              AND (ra.valid_to IS NULL OR ra.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL OR rp.valid_to > CURRENT_TIMESTAMP)
              AND (
                    ra.scope_id IS NULL
                    OR s.scope_type = 'GLOBAL'
              )
            ORDER BY r.role_code
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "actor_id",
            NpgsqlDbType.Uuid,
            actorAccountId);
        command.Parameters.AddWithValue(
            "permission_code",
            NpgsqlDbType.Varchar,
            ManageRolesPermission);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not string roleCode)
        {
            throw Invalid(
                "security.authorization.denied",
                "El permiso para administrar roles ya no está vigente.");
        }

        return roleCode;
    }

    private static async Task RequireActiveTargetAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM security.account
                WHERE account_id = @account_id
                  AND status_code = 'ACTIVE'
                  AND verified_at IS NOT NULL
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        if (await command.ExecuteScalarAsync(cancellationToken) is not true)
        {
            throw Invalid(
                "security.role-assignment.target.unavailable",
                "La cuenta objetivo no está activa y verificada.");
        }
    }

    private static async Task<Guid> ResolveActiveRoleAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string roleCode,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT role_id
            FROM security.role
            WHERE role_code = @role_code
              AND status_code = 'ACTIVE';
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "role_code",
            NpgsqlDbType.Varchar,
            NormalizeCode(roleCode, "rol"));

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not Guid roleId)
        {
            throw Invalid(
                "security.role-assignment.role.invalid",
                "El rol solicitado no está activo.");
        }

        return roleId;
    }

    private static async Task<RoleAssignmentScopeView> ResolveScopeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid scopeId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT scope_id, scope_type, module_code, object_id
            FROM security.access_scope
            WHERE scope_id = @scope_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "scope_id",
            NpgsqlDbType.Uuid,
            scopeId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw Invalid(
                "security.role-assignment.scope.invalid",
                "El alcance solicitado no existe.");
        }

        return ReadScope(reader);
    }

    private static async Task<RoleAssignmentView?> FindOverlappingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid roleId,
        Guid? scopeId,
        DateTimeOffset? validUntil,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                ra.assignment_id,
                ra.account_id,
                r.role_code,
                s.scope_id,
                s.scope_type,
                s.module_code,
                s.object_id,
                ra.valid_from,
                ra.valid_to,
                ra.reason,
                CASE
                    WHEN ra.valid_from > CURRENT_TIMESTAMP THEN 'SCHEDULED'
                    WHEN ra.valid_to IS NOT NULL
                         AND ra.valid_to <= CURRENT_TIMESTAMP THEN 'EXPIRED'
                    ELSE 'ACTIVE'
                END AS state_code
            FROM security.role_assignment ra
            JOIN security.role r
              ON r.role_id = ra.role_id
            LEFT JOIN security.access_scope s
              ON s.scope_id = ra.scope_id
            WHERE ra.account_id = @account_id
              AND ra.role_id = @role_id
              AND ra.scope_id IS NOT DISTINCT FROM @scope_id
              AND tstzrange(
                    ra.valid_from,
                    ra.valid_to,
                    '[)'
                  ) && tstzrange(
                    CURRENT_TIMESTAMP,
                    @valid_to,
                    '[)'
                  )
            ORDER BY ra.valid_from DESC
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);
        command.Parameters.AddWithValue(
            "role_id",
            NpgsqlDbType.Uuid,
            roleId);
        command.Parameters.Add(
            NullableUuid("scope_id", scopeId));
        command.Parameters.Add(
            NullableTimestamp("valid_to", validUntil));

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        return await reader.ReadAsync(cancellationToken)
            ? ReadAssignment(reader)
            : null;
    }

    private static bool SameGrant(
        RoleAssignmentView existing,
        DateTimeOffset? validUntil,
        string reason)
    {
        var sameValidity =
            (!existing.ValidTo.HasValue && !validUntil.HasValue)
            || (
                existing.ValidTo.HasValue
                && validUntil.HasValue
                && existing.ValidTo.Value == validUntil.Value
            );

        return sameValidity
            && string.Equals(
                existing.Reason,
                reason,
                StringComparison.Ordinal);
    }

    private static async Task<RoleAssignmentView?> ReadByIdAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid assignmentId,
        CancellationToken cancellationToken) =>
        await ReadByIdCoreAsync(
            connection,
            transaction,
            assignmentId,
            forUpdate: false,
            cancellationToken);

    private static async Task<RoleAssignmentView?> ReadByIdForUpdateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid assignmentId,
        CancellationToken cancellationToken) =>
        await ReadByIdCoreAsync(
            connection,
            transaction,
            assignmentId,
            forUpdate: true,
            cancellationToken);

    private static async Task<RoleAssignmentView?> ReadByIdCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid assignmentId,
        bool forUpdate,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT
                ra.assignment_id,
                ra.account_id,
                r.role_code,
                s.scope_id,
                s.scope_type,
                s.module_code,
                s.object_id,
                ra.valid_from,
                ra.valid_to,
                ra.reason,
                CASE
                    WHEN ra.valid_from > CURRENT_TIMESTAMP THEN 'SCHEDULED'
                    WHEN ra.valid_to IS NOT NULL
                         AND ra.valid_to <= CURRENT_TIMESTAMP THEN 'EXPIRED'
                    ELSE 'ACTIVE'
                END AS state_code
            FROM security.role_assignment ra
            JOIN security.role r
              ON r.role_id = ra.role_id
            LEFT JOIN security.access_scope s
              ON s.scope_id = ra.scope_id
            WHERE ra.assignment_id = @assignment_id
            """;

        if (forUpdate)
        {
            sql += " FOR UPDATE OF ra";
        }

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "assignment_id",
            NpgsqlDbType.Uuid,
            assignmentId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        return await reader.ReadAsync(cancellationToken)
            ? ReadAssignment(reader)
            : null;
    }

    private static async Task<DateTimeOffset> ReadDatabaseNowAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        await using var command =
            new NpgsqlCommand(
                "SELECT CURRENT_TIMESTAMP;",
                connection,
                transaction);
        var value = await command.ExecuteScalarAsync(cancellationToken);

        return value switch
        {
            DateTime dateTime => new DateTimeOffset(
                DateTime.SpecifyKind(dateTime, DateTimeKind.Utc)),
            DateTimeOffset offset => offset.ToUniversalTime(),
            _ => throw new InvalidOperationException(
                "PostgreSQL no devolvió CURRENT_TIMESTAMP.")
        };
    }

    private static RoleAssignmentView ReadAssignment(
        NpgsqlDataReader reader)
    {
        var scope = reader.IsDBNull(3)
            ? null
            : new RoleAssignmentScopeView(
                reader.GetGuid(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetGuid(6));

        return new RoleAssignmentView(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            scope,
            AsUtcOffset(reader.GetDateTime(7)),
            reader.IsDBNull(8)
                ? null
                : AsUtcOffset(reader.GetDateTime(8)),
            reader.GetString(9),
            reader.GetString(10));
    }

    private static RoleAssignmentScopeView ReadScope(
        NpgsqlDataReader reader) =>
        new(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetGuid(3));

    private static async Task InsertAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorId,
        string roleCode,
        string actionCode,
        Guid assignmentId,
        byte[]? beforeDigest,
        byte[]? afterDigest,
        string reason,
        Guid correlationId,
        CancellationToken cancellationToken)
    {
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
                @object_type,
                @object_id,
                @action_code,
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
            actorId);
        command.Parameters.AddWithValue(
            "role_code",
            NpgsqlDbType.Varchar,
            roleCode);
        command.Parameters.AddWithValue(
            "object_type",
            NpgsqlDbType.Varchar,
            ObjectType);
        command.Parameters.AddWithValue(
            "object_id",
            NpgsqlDbType.Uuid,
            assignmentId);
        command.Parameters.AddWithValue(
            "action_code",
            NpgsqlDbType.Varchar,
            actionCode);
        command.Parameters.Add(
            NullableBytea("before_digest", beforeDigest));
        command.Parameters.Add(
            NullableBytea("after_digest", afterDigest));
        command.Parameters.AddWithValue(
            "reason",
            NpgsqlDbType.Text,
            reason);
        command.Parameters.AddWithValue(
            "correlation_id",
            NpgsqlDbType.Uuid,
            correlationId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se registró exactamente un evento de auditoría.");
        }
    }

    private static byte[] Digest(RoleAssignmentView value)
    {
        var scope = value.Scope?.ScopeId.ToString("D") ?? "GLOBAL";
        var validTo = value.ValidTo?.ToUniversalTime()
            .ToString("O", System.Globalization.CultureInfo.InvariantCulture)
            ?? "OPEN";

        var canonical = string.Join(
            "|",
            value.AssignmentId.ToString("D"),
            value.AccountId.ToString("D"),
            value.RoleCode,
            scope,
            value.ValidFrom.ToUniversalTime().ToString(
                "O",
                System.Globalization.CultureInfo.InvariantCulture),
            validTo,
            value.Reason);

        return SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
    }

    private static Guid ResolveCorrelationGuid(string correlationId)
    {
        if (Guid.TryParse(correlationId, out var parsed))
        {
            return parsed;
        }

        var bytes = Encoding.UTF8.GetBytes(correlationId);
        try
        {
            var hash = SHA256.HashData(bytes);
            return new Guid(hash.AsSpan(0, 16));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
        }
    }

    private static DateTimeOffset AsUtcOffset(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static string NormalizeReason(string reason)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(reason);
        var normalized = reason.Trim();

        if (normalized.Length > 1000)
        {
            throw Invalid(
                "security.role-assignment.reason.invalid",
                "El motivo no puede superar 1000 caracteres.");
        }

        return normalized;
    }

    private static string NormalizeCode(
        string value,
        string fieldName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        var normalized = value.Trim().ToUpperInvariant();

        if (normalized.Length is < 1 or > 64
            || !IsAsciiCode(normalized))
        {
            throw Invalid(
                "security.role-assignment.role.invalid",
                $"El {fieldName} no usa un código válido.");
        }

        return normalized;
    }

    private static bool IsAsciiCode(string value)
    {
        if (!(char.IsAsciiLetterOrDigit(value[0])))
        {
            return false;
        }

        return value.All(static character =>
            char.IsAsciiLetterOrDigit(character)
            || character is '.' or '_' or '-');
    }

    private static NpgsqlParameter NullableUuid(
        string name,
        Guid? value) =>
        new(name, NpgsqlDbType.Uuid)
        {
            Value = value.HasValue
                ? value.Value
                : DBNull.Value
        };

    private static NpgsqlParameter NullableTimestamp(
        string name,
        DateTimeOffset? value) =>
        new(name, NpgsqlDbType.TimestampTz)
        {
            Value = value.HasValue
                ? value.Value.UtcDateTime
                : DBNull.Value
        };

    private static NpgsqlParameter NullableBytea(
        string name,
        byte[]? value) =>
        new(name, NpgsqlDbType.Bytea)
        {
            Value = value is null
                ? DBNull.Value
                : value
        };

    private static RoleAssignmentAdministrationException Invalid(
        string code,
        string message) =>
        new(code, message);
}
