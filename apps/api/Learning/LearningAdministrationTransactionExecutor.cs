using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Learning.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Learning;

public sealed class LearningAdministrationTransactionExecutor(
    BackofficeSecurityTransactionExecutor inner)
    : IExerciseBankAdministrationTransactionExecutor
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
