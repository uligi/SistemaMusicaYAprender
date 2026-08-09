using MusicaAprender.BuildingBlocks.Contracts.Email;
using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;

public interface ITransactionalEmailEnqueuer
{
    Task<EmailQueueReceipt> EnqueueAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        EmailQueueRequest request,
        CancellationToken cancellationToken = default);
}
