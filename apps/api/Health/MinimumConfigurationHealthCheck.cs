using Microsoft.Extensions.Diagnostics.HealthChecks;
using MusicaAprender.Modules.Configuration.Infrastructure.Publication;
using MusicaAprender.Modules.Security.Infrastructure.Authorization;

namespace MusicaAprender.Api.Health;

internal sealed class MinimumConfigurationHealthCheck(
    MinimumPublishedConfigurationReader configurationReader,
    MinimumRoleCatalogReader roleCatalogReader) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(HealthConstants.DependencyTimeout);

        var configurationTask = configurationReader.InspectAsync(timeout.Token);
        var rolesTask = roleCatalogReader.InspectAsync(timeout.Token);
        try
        {
            await Task.WhenAll(configurationTask, rolesTask);
        }
        catch (OperationCanceledException)
            when (timeout.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            return HealthCheckResult.Degraded(
                "La inspeccion de configuracion excedio el tiempo limite; se conserva el ultimo valor valido o el sustituto seguro declarado.",
                data: new Dictionary<string, object>
                {
                    ["safeFallbackDeclared"] = true,
                    ["safeRole"] = MinimumRoleCatalogManifest.SafeRoleCode
                });
        }

        var configuration = await configurationTask;
        var roles = await rolesTask;
        var data = new Dictionary<string, object>
        {
            ["publishedCatalogs"] = configuration.PublishedCatalogCount,
            ["publishedCatalogEntries"] = configuration.PublishedCatalogEntryCount,
            ["effectiveParameters"] = configuration.EffectiveParameterCount,
            ["retentionPolicies"] = configuration.RetentionPolicyCount,
            ["publishedRoles"] = roles.PublishedRoleCount,
            ["safeRole"] = MinimumRoleCatalogManifest.SafeRoleCode,
            ["missingItemCount"] = configuration.MissingItems.Count
                                   + roles.MissingRoleCodes.Count
        };

        if (!configuration.StorageAvailable || !roles.StorageAvailable)
        {
            return HealthCheckResult.Degraded(
                "Configuracion no disponible; los consumidores deben conservar el ultimo valor valido o el sustituto seguro declarado.",
                data: data);
        }

        if (!configuration.IsComplete || !roles.IsComplete)
        {
            return HealthCheckResult.Unhealthy(
                "La publicacion minima de configuracion esta incompleta o fuera de vigencia.",
                data: data);
        }

        return HealthCheckResult.Healthy(
            "Catalogos, parametros, roles y politicas minimas estan publicados y vigentes.",
            data);
    }
}
