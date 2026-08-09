using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Minio;
using MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;

namespace MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage.DependencyInjection;

public static class ObjectStoreServiceCollectionExtensions
{
    public static IServiceCollection AddMusicaAprenderPrivateObjectStore(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        services.AddSingleton(
            _ => ObjectStoreOptions.FromConfiguration(configuration));

        services.AddSingleton<IMinioClient>(
            serviceProvider =>
            {
                var options = serviceProvider.GetRequiredService<ObjectStoreOptions>();

                return new MinioClient()
                    .WithEndpoint(options.Endpoint.Authority)
                    .WithCredentials(options.AccessKey, options.SecretKey)
                    .WithSSL(options.Endpoint.Scheme == Uri.UriSchemeHttps)
                    .Build();
            });

        services.AddSingleton<IObjectStore, MinioPrivateObjectStore>();

        return services;
    }
}
