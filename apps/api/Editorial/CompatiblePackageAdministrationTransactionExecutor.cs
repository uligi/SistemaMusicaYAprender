using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Editorial;

public sealed class CompatiblePackageAdministrationTransactionExecutor(
    BackofficeSecurityTransactionExecutor inner)
    : ICompatibleEducationalPackageTransactionExecutor
{
    public Task<TResult> ExecuteAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default)
    {
        return inner.ExecuteAsync(
            actorAccountId,
            correlationId,
            operation,
            cancellationToken);
    }
}
