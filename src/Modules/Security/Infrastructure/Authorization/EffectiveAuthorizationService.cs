using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Authorization;

public sealed class EffectiveAuthorizationService(
    IRlsTransactionExecutor transactionExecutor)
{
    private const string BaselineRoleCode = "STUDENT";

    public async Task<EffectiveAccessSnapshot> ResolveSnapshotAsync(
        Guid accountId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateSubject(accountId, correlationId);

        var grants = await LoadEffectiveGrantsAsync(
            accountId,
            correlationId,
            cancellationToken);

        if (!grants.AccountActive)
        {
            return EffectiveAccessSnapshot.Empty;
        }

        var roles = grants.Rows
            .Select(static row => row.RoleCode)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();

        var permissions = grants.Rows
            .Select(static row => row.PermissionCode)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();

        return new EffectiveAccessSnapshot(roles, permissions);
    }

    public async Task<AuthorizationDecision> AuthorizeAsync(
        Guid accountId,
        string permissionCode,
        AuthorizationScope requiredScope,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateSubject(accountId, correlationId);
        ArgumentNullException.ThrowIfNull(requiredScope);

        var normalizedPermission = NormalizePermissionCode(permissionCode);
        var grants = await LoadEffectiveGrantsAsync(
            accountId,
            correlationId,
            cancellationToken);

        if (!grants.AccountActive)
        {
            return AuthorizationDecision.Deny("ACCOUNT_NOT_ACTIVE");
        }

        var allowed = grants.Rows.Any(row =>
            string.Equals(
                row.PermissionCode,
                normalizedPermission,
                StringComparison.Ordinal)
            && AuthorizationScopeMatcher.Matches(
                requiredScope,
                row.ScopeType,
                row.ModuleCode,
                row.ObjectId));

        return allowed
            ? AuthorizationDecision.Grant()
            : AuthorizationDecision.Deny("NO_VALID_GRANT");
    }

    public async Task<AuthorizationCatalog> ReadCatalogAsync(
        Guid accountId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateSubject(accountId, correlationId);

        var context = DatabaseSessionContext.Create(
            accountId,
            BaselineRoleCode,
            correlationId);

        return await transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await using var command = new NpgsqlCommand(
                    """
                    SELECT 'ROLE' AS item_type, role_code AS code
                    FROM security.role
                    WHERE status_code = 'ACTIVE'
                    UNION ALL
                    SELECT 'PERMISSION' AS item_type, permission_code AS code
                    FROM security.permission
                    ORDER BY item_type, code;
                    """,
                    connection,
                    transaction);

                var roles = new List<string>();
                var permissions = new List<string>();

                await using var reader =
                    await command.ExecuteReaderAsync(token);

                while (await reader.ReadAsync(token))
                {
                    var itemType = reader.GetString(0);
                    var code = reader.GetString(1);

                    if (string.Equals(
                        itemType,
                        "ROLE",
                        StringComparison.Ordinal))
                    {
                        roles.Add(code);
                    }
                    else
                    {
                        permissions.Add(code);
                    }
                }

                return new AuthorizationCatalog(
                    roles.ToArray(),
                    permissions.ToArray());
            },
            cancellationToken);
    }

    private async Task<EffectiveGrantSet> LoadEffectiveGrantsAsync(
        Guid accountId,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var context = DatabaseSessionContext.Create(
            accountId,
            BaselineRoleCode,
            correlationId);

        return await transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                if (!await IsActiveAccountAsync(
                    connection,
                    transaction,
                    accountId,
                    token))
                {
                    return new EffectiveGrantSet(
                        false,
                        Array.Empty<EffectiveGrant>());
                }

                await using var command = new NpgsqlCommand(
                    """
                    WITH effective_role AS (
                        SELECT
                            role.role_id,
                            role.role_code,
                            NULL::uuid AS scope_id
                        FROM security.role AS role
                        WHERE role.role_code = 'STUDENT'
                          AND role.status_code = 'ACTIVE'

                        UNION ALL

                        SELECT
                            role.role_id,
                            role.role_code,
                            assignment.scope_id
                        FROM security.role_assignment AS assignment
                        INNER JOIN security.role AS role
                            ON role.role_id = assignment.role_id
                        WHERE assignment.account_id = @account_id
                          AND assignment.valid_from <= CURRENT_TIMESTAMP
                          AND (
                              assignment.valid_to IS NULL
                              OR assignment.valid_to > CURRENT_TIMESTAMP
                          )
                          AND role.status_code = 'ACTIVE'
                    )
                    SELECT
                        effective_role.role_code,
                        permission.permission_code,
                        scope.scope_type,
                        scope.module_code,
                        scope.object_id
                    FROM effective_role
                    INNER JOIN security.role_permission AS role_permission
                        ON role_permission.role_id = effective_role.role_id
                    INNER JOIN security.permission AS permission
                        ON permission.permission_id = role_permission.permission_id
                    LEFT JOIN security.access_scope AS scope
                        ON scope.scope_id = effective_role.scope_id
                    WHERE role_permission.valid_from <= CURRENT_TIMESTAMP
                      AND (
                          role_permission.valid_to IS NULL
                          OR role_permission.valid_to > CURRENT_TIMESTAMP
                      )
                    ORDER BY
                        effective_role.role_code,
                        permission.permission_code,
                        scope.scope_type,
                        scope.module_code,
                        scope.object_id;
                    """,
                    connection,
                    transaction);

                command.Parameters.AddWithValue(
                    "account_id",
                    NpgsqlDbType.Uuid,
                    accountId);

                var rows = new List<EffectiveGrant>();

                await using var reader =
                    await command.ExecuteReaderAsync(token);

                while (await reader.ReadAsync(token))
                {
                    rows.Add(new EffectiveGrant(
                        reader.GetString(0),
                        reader.GetString(1),
                        reader.IsDBNull(2) ? null : reader.GetString(2),
                        reader.IsDBNull(3) ? null : reader.GetString(3),
                        reader.IsDBNull(4) ? null : reader.GetGuid(4)));
                }

                return new EffectiveGrantSet(true, rows.ToArray());
            },
            cancellationToken);
    }

    private static async Task<bool> IsActiveAccountAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT EXISTS (
                SELECT 1
                FROM security.account
                WHERE account_id = @account_id
                  AND status_code = 'ACTIVE'
                  AND verified_at IS NOT NULL
            );
            """,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static string NormalizePermissionCode(string permissionCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(permissionCode);

        var normalized = permissionCode.Trim().ToUpperInvariant();
        if (!AuthorizationCode.IsValid(normalized))
        {
            throw new ArgumentException(
                "PermissionCode no cumple el formato estable esperado.",
                nameof(permissionCode));
        }

        return normalized;
    }

    private static void ValidateSubject(
        Guid accountId,
        string correlationId)
    {
        if (accountId == Guid.Empty)
        {
            throw new ArgumentException(
                "AccountId no puede ser Guid.Empty.",
                nameof(accountId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);
    }

    private sealed record EffectiveGrantSet(
        bool AccountActive,
        IReadOnlyList<EffectiveGrant> Rows);

    private sealed record EffectiveGrant(
        string RoleCode,
        string PermissionCode,
        string? ScopeType,
        string? ModuleCode,
        Guid? ObjectId);
}

public sealed record AuthorizationCatalog(
    IReadOnlyList<string> Roles,
    IReadOnlyList<string> Permissions);
