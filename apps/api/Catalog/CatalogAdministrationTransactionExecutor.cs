using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Catalog.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Catalog;

public sealed class CatalogAdministrationTransactionExecutor(
    BackofficeSecurityTransactionExecutor inner)
    : IArtistAdministrationTransactionExecutor,
      ISongDraftAdministrationTransactionExecutor,
      ICreditProvenanceAdministrationTransactionExecutor
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
