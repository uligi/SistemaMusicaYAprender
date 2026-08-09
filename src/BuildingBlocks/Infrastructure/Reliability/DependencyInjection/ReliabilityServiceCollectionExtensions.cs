using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Inbox;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.DependencyInjection;

public static class ReliabilityServiceCollectionExtensions
{
    public static IServiceCollection AddMusicaAprenderReliableOperations(
        this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<
            ITransactionalOutboxWriter,
            TransactionalOutboxWriter>();

        services.TryAddSingleton<
            IReliableOperationExecutor,
            ReliableOperationExecutor>();

        return services;
    }

    public static IServiceCollection AddMusicaAprenderOutboxDispatch(
        this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<
            IInboxConsumerExecutor,
            InboxConsumerExecutor>();

        services.TryAddSingleton<OutboxDispatcher>();

        return services;
    }
}
