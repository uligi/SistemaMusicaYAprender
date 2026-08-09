using System.Data;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Database;

public sealed class RlsTransactionExecutor : IRlsTransactionExecutor
{
    private readonly string _connectionString;

    public RlsTransactionExecutor(IConfiguration configuration)
        : this(RequireConnectionString(configuration))
    {
    }

    public RlsTransactionExecutor(string connectionString)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);

        _connectionString = connectionString;
    }

    public async Task ExecuteAsync(
        DatabaseSessionContext context,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task> operation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(operation);

        await ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await operation(connection, transaction, token);
                return true;
            },
            cancellationToken);
    }

    public async Task<TResult> ExecuteAsync<TResult>(
        DatabaseSessionContext context,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(operation);

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.ReadCommitted,
            cancellationToken);

        await RlsTransactionContext.ApplyAsync(
            connection,
            transaction,
            context,
            cancellationToken);

        var result = await operation(
            connection,
            transaction,
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        return result;
    }

    private static string RequireConnectionString(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var connectionString = configuration.GetConnectionString("PostgreSQL");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para el ejecutor transaccional RLS.");
        }

        return connectionString;
    }
}
