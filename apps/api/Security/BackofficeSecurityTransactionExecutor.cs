using System.Data;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Security.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Security;

public sealed class BackofficeSecurityTransactionExecutor :
    IPrivilegedSecurityTransactionExecutor
{
    private const string DefaultSecretDirectory = "/run/secrets";
    private const string BackofficeSecretName = "postgres_backoffice_password";
    private const string BackofficeUsername = "jp_login_backoffice";

    private readonly string _connectionString;

    public BackofficeSecurityTransactionExecutor(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var normalConnectionString =
            configuration.GetConnectionString("PostgreSQL");

        if (string.IsNullOrWhiteSpace(normalConnectionString))
        {
            throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para el pool backoffice.");
        }

        var secretDirectory =
            configuration["Secrets:Directory"]
            ?? DefaultSecretDirectory;
        var secretPath = Path.Combine(
            secretDirectory,
            BackofficeSecretName);

        if (!File.Exists(secretPath))
        {
            throw new InvalidOperationException(
                $"Falta el secreto requerido '{BackofficeSecretName}'.");
        }

        var password = File.ReadAllText(secretPath).Trim();
        if (password.Length < 24 || password.Length > 4096)
        {
            throw new InvalidOperationException(
                "La credencial backoffice no cumple la longitud requerida.");
        }

        var builder = new NpgsqlConnectionStringBuilder(normalConnectionString)
        {
            Username = BackofficeUsername,
            Password = password,
            IncludeErrorDetail = false,
            PersistSecurityInfo = false,
            Pooling = true,
            ApplicationName = "MusicaAprender.Api.Backoffice"
        };

        _connectionString = builder.ConnectionString;
    }

    public async Task<TResult> ExecuteAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException(
                "El actor privilegiado no puede ser Guid.Empty.",
                nameof(actorAccountId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);
        ArgumentNullException.ThrowIfNull(operation);

        await using var connection =
            new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction =
            await connection.BeginTransactionAsync(
                IsolationLevel.ReadCommitted,
                cancellationToken);

        var context = DatabaseSessionContext.Create(
            actorAccountId,
            "BACKOFFICE",
            correlationId);

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
}
