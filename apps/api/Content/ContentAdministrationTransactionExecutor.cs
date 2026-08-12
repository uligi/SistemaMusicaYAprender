using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Content;

public sealed class ContentAdministrationTransactionExecutor(
    BackofficeSecurityTransactionExecutor inner)
    : ILyricsStructureAdministrationTransactionExecutor
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
