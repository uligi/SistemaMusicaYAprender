using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Database;

public static class RlsTransactionContext
{
    public const string AccountSetting = "app.account_id";
    public const string RoleSetting = "app.role_code";
    public const string CorrelationSetting = "app.correlation_id";

    public static async Task ApplyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        DatabaseSessionContext context,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(context);

        if (connection.State != System.Data.ConnectionState.Open)
        {
            throw new InvalidOperationException(
                "La conexion PostgreSQL debe estar abierta antes de aplicar contexto RLS.");
        }

        await using var command = new NpgsqlCommand(
            """
            SELECT
                set_config('app.account_id', @account_id, true),
                set_config('app.role_code', @role_code, true),
                set_config('app.correlation_id', @correlation_id, true);
            """,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Text,
            context.AccountId.ToString("D"));

        command.Parameters.AddWithValue(
            "role_code",
            NpgsqlDbType.Text,
            context.RoleCode);

        command.Parameters.AddWithValue(
            "correlation_id",
            NpgsqlDbType.Text,
            context.CorrelationId);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
