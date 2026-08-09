namespace MusicaAprender.DatabaseMigrator.Migrations;

internal static class SeedMigrationSql
{
    private const string RoleMarker = "SET LOCAL ROLE jp_owner;";
    private const string CommitMarker = "COMMIT;";
    private const string TemporaryPolicyName = "p_account_bootstrap_owner";

    internal static string Prepare(string authoritativeSeedSql)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(authoritativeSeedSql);

        var rolePosition = authoritativeSeedSql.IndexOf(
            RoleMarker,
            StringComparison.Ordinal);

        if (rolePosition < 0)
        {
            throw new InvalidOperationException(
                "La semilla autoritativa no contiene SET LOCAL ROLE jp_owner.");
        }

        var roleEnd = rolePosition + RoleMarker.Length;

        var policySql =
            $"""

            -- Política temporal de bootstrap:
            -- security.account tiene FORCE RLS y la semilla autoritativa
            -- usa INSERT ... ON CONFLICT DO NOTHING bajo jp_owner.
            -- FOR ALL cubre tanto WITH CHECK de INSERT como cualquier
            -- comprobacion de visibilidad que PostgreSQL requiera durante
            -- ON CONFLICT. La política existe solo durante esta transacción.
            CREATE POLICY {TemporaryPolicyName}
                ON security.account
                FOR ALL
                TO jp_owner
                USING (true)
                WITH CHECK (true);
            """;

        var prepared = authoritativeSeedSql.Insert(roleEnd, policySql);

        var commitPosition = prepared.LastIndexOf(
            CommitMarker,
            StringComparison.Ordinal);

        if (commitPosition < 0)
        {
            throw new InvalidOperationException(
                "La semilla autoritativa no contiene COMMIT final.");
        }

        var cleanupSql =
            $"""
            DROP POLICY {TemporaryPolicyName} ON security.account;

            """;

        return prepared.Insert(commitPosition, cleanupSql);
    }
}
