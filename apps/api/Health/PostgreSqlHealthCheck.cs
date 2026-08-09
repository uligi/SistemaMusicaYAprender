using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;

namespace MusicaAprender.Api.Health;

internal sealed class PostgreSqlHealthCheck : IHealthCheck
{
    private readonly IConfiguration _configuration;

    public PostgreSqlHealthCheck(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var connectionString = _configuration.GetConnectionString("PostgreSQL");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return Failure(context, "PostgreSQL configuration is missing.");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(HealthConstants.DependencyTimeout);

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(timeout.Token);

            await using var command = new NpgsqlCommand("SELECT 1;", connection);
            _ = await command.ExecuteScalarAsync(timeout.Token);

            return HealthCheckResult.Healthy("PostgreSQL is reachable.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Failure(context, "PostgreSQL did not answer in time.");
        }
        catch (NpgsqlException)
        {
            return Failure(context, "PostgreSQL is unavailable.");
        }
        catch (InvalidOperationException)
        {
            return Failure(context, "PostgreSQL is unavailable.");
        }
        catch (ArgumentException)
        {
            return Failure(context, "PostgreSQL configuration is invalid.");
        }
    }

    private static HealthCheckResult Failure(
        HealthCheckContext context,
        string description)
    {
        return new HealthCheckResult(
            context.Registration.FailureStatus,
            description);
    }
}
