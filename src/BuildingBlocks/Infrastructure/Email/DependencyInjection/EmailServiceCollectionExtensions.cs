using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MusicaAprender.BuildingBlocks.Contracts.Email;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Delivery;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Smtp;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.DependencyInjection;

public static class EmailServiceCollectionExtensions
{
    public static IServiceCollection AddMusicaAprenderEmailQueue(
        this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<
            ITransactionalEmailEnqueuer,
            TransactionalEmailEnqueuer>();

        return services;
    }

    public static IServiceCollection AddMusicaAprenderEmailDelivery(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        services.TryAddEnumerable(
            ServiceDescriptor.Singleton<
                IOutboxConsumer,
                EmailJobProjectionConsumer>());

        services.TryAddSingleton<IEmailSender>(
            _ => new MailKitEmailSender(
                SmtpOptions.FromConfiguration(configuration)));

        services.TryAddSingleton<EmailDeliveryJobDispatcher>();

        return services;
    }
}
