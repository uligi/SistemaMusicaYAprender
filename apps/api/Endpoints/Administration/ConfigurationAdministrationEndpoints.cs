using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Configuration.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Administration;

public sealed record ParameterConfigurationChangeRequest(
    string ParameterKey,
    string ScopeCode,
    string? ScopeValue,
    string TypedValueJson,
    DateTimeOffset? ValidUntil,
    string Reason,
    string Impact,
    int ExpectedVersionNo);

public sealed record CatalogConfigurationChangeRequest(
    string CatalogCode,
    string EntryCode,
    string LabelsJson,
    string ValueJson,
    DateTimeOffset? ValidUntil,
    string Reason,
    string Impact,
    Guid ExpectedEntryId,
    long ExpectedVersion);

public static class ConfigurationAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapConfigurationAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/administration/configuration",
                ReadSnapshotAsync)
            .RequireEffectivePermission(
                "CONFIG.MANAGE",
                moduleCode: "M19")
            .RequireRecentPrivilegedAssurance()
            .WithName("ReadConfigurationAdministration")
            .WithTags("Configuration");

        endpoints.MapPost(
                "/api/v1/administration/configuration/parameters/simulate",
                SimulateParameterAsync)
            .RequireEffectivePermission(
                "CONFIG.MANAGE",
                moduleCode: "M19")
            .RequireRecentPrivilegedAssurance()
            .WithName("SimulateParameterConfigurationChange")
            .WithTags("Configuration");

        endpoints.MapPost(
                "/api/v1/administration/configuration/parameters/activate",
                ActivateParameterAsync)
            .RequireEffectivePermission(
                "CONFIG.MANAGE",
                moduleCode: "M19")
            .RequireEffectivePermission(
                "CONFIG.APPROVE",
                moduleCode: "M19")
            .RequireRecentPrivilegedAssurance()
            .WithName("ActivateParameterConfigurationChange")
            .WithTags("Configuration");

        endpoints.MapPost(
                "/api/v1/administration/configuration/catalogs/simulate",
                SimulateCatalogAsync)
            .RequireEffectivePermission(
                "CONFIG.MANAGE",
                moduleCode: "M19")
            .RequireRecentPrivilegedAssurance()
            .WithName("SimulateCatalogConfigurationChange")
            .WithTags("Configuration");

        endpoints.MapPost(
                "/api/v1/administration/configuration/catalogs/activate",
                ActivateCatalogAsync)
            .RequireEffectivePermission(
                "CONFIG.MANAGE",
                moduleCode: "M19")
            .RequireEffectivePermission(
                "CONFIG.APPROVE",
                moduleCode: "M19")
            .RequireRecentPrivilegedAssurance()
            .WithName("ActivateCatalogConfigurationChange")
            .WithTags("Configuration");

        return endpoints;
    }

    private static async Task<IResult> ReadSnapshotAsync(
        HttpContext httpContext,
        ConfigurationAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            return Results.Ok(
                await service.ReadSnapshotAsync(
                    actorId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted));
        }
        catch (ConfigurationAdministrationException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
        catch (InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> SimulateParameterAsync(
        ParameterConfigurationChangeRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        ConfigurationAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            return Results.Ok(
                await service.SimulateParameterAsync(
                    actorId,
                    ToCommand(request),
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted));
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (ConfigurationAdministrationException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
        catch (InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> ActivateParameterAsync(
        ParameterConfigurationChangeRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        ConfigurationAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            var result =
                await service.ActivateParameterAsync(
                    actorId,
                    ToCommand(request),
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            return result.AlreadyApplied
                ? Results.Ok(result)
                : Results.Created(
                    $"/api/v1/administration/configuration?parameter={Uri.EscapeDataString(request.ParameterKey)}",
                    result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (PostgresException exception)
            when (exception.SqlState == "23P01")
        {
            return ValidityConflict();
        }
        catch (ConfigurationAdministrationException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
        catch (InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> SimulateCatalogAsync(
        CatalogConfigurationChangeRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        ConfigurationAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            return Results.Ok(
                await service.SimulateCatalogAsync(
                    actorId,
                    ToCommand(request),
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted));
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (ConfigurationAdministrationException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
        catch (InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> ActivateCatalogAsync(
        CatalogConfigurationChangeRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        ConfigurationAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            var result =
                await service.ActivateCatalogAsync(
                    actorId,
                    ToCommand(request),
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            return result.AlreadyApplied
                ? Results.Ok(result)
                : Results.Created(
                    $"/api/v1/administration/configuration?catalog={Uri.EscapeDataString(request.CatalogCode)}",
                    result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (PostgresException exception)
            when (exception.SqlState == "23P01")
        {
            return ValidityConflict();
        }
        catch (ConfigurationAdministrationException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
        catch (InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static ParameterConfigurationChangeCommand ToCommand(
        ParameterConfigurationChangeRequest request) =>
        new(
            request.ParameterKey?.Trim().ToUpperInvariant()
                ?? string.Empty,
            request.ScopeCode?.Trim().ToUpperInvariant()
                ?? string.Empty,
            request.ScopeValue?.Trim(),
            request.TypedValueJson ?? string.Empty,
            request.ValidUntil,
            request.Reason ?? string.Empty,
            request.Impact ?? string.Empty,
            request.ExpectedVersionNo);

    private static CatalogConfigurationChangeCommand ToCommand(
        CatalogConfigurationChangeRequest request) =>
        new(
            request.CatalogCode?.Trim().ToUpperInvariant()
                ?? string.Empty,
            request.EntryCode?.Trim().ToUpperInvariant()
                ?? string.Empty,
            request.LabelsJson ?? string.Empty,
            request.ValueJson ?? string.Empty,
            request.ValidUntil,
            request.Reason ?? string.Empty,
            request.Impact ?? string.Empty,
            request.ExpectedEntryId,
            request.ExpectedVersion);

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var value =
            context.User.FindFirstValue("account_id");
        return Guid.TryParse(value, out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Problem(
        ConfigurationAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "configuration.authorization.approver-missing" =>
                StatusCodes.Status403Forbidden,
            "configuration.parameter.not-found" =>
                StatusCodes.Status404NotFound,
            "configuration.parameter.no-effective-value" =>
                StatusCodes.Status409Conflict,
            "configuration.catalog.not-found" =>
                StatusCodes.Status404NotFound,
            "configuration.catalog-entry.no-effective-value" =>
                StatusCodes.Status409Conflict,
            "configuration.change.concurrency" =>
                StatusCodes.Status409Conflict,
            "configuration.change.validity-overlap" =>
                StatusCodes.Status409Conflict,
            "configuration.projection.conflict" =>
                StatusCodes.Status409Conflict,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status == StatusCodes.Status409Conflict
                ? "La configuración cambió o tiene una vigencia incompatible"
                : "Cambio de configuración no válido",
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static IResult CsrfInvalid() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud no válida",
            detail:
                "Actualiza la página y vuelve a intentarlo.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] =
                    "configuration.change.csrf.invalid"
            });

    private static IResult ValidityConflict() =>
        Results.Problem(
            statusCode: StatusCodes.Status409Conflict,
            title: "Vigencia incompatible",
            detail:
                "Otra versión activa o programada ocupa el mismo ámbito y periodo.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] =
                    "configuration.change.validity-overlap"
            });

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode:
                StatusCodes.Status503ServiceUnavailable,
            title:
                "Administración de configuración temporalmente no disponible",
            detail:
                "No se activó ningún cambio. La última configuración confirmada permanece vigente.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] =
                    "configuration.change.unavailable"
            });
}
