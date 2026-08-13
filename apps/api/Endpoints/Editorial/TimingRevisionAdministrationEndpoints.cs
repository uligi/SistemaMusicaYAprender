using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class TimingRevisionAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapTimingRevisionAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/synchronization-context",
                ReadContextAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialSynchronizationContext")
            .WithTags("Content");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/timing-revisions",
                CreateRevisionAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("CreateEditorialTimingRevision")
            .WithTags("Content");

        return endpoints;
    }

    private static async Task<IResult> ReadContextAsync(
        Guid recordingId,
        HttpContext httpContext,
        TimingRevisionAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var context =
                await service.ReadContextAsync(
                    actorId,
                    recordingId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            httpContext.Response.Headers["Cache-Control"] =
                "no-store";

            return Results.Ok(
                context);
        }
        catch (TimingAdministrationException exception)
        {
            return Problem(
                exception);
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

    private static async Task<IResult> CreateRevisionAsync(
        Guid recordingId,
        CreateTimingRevisionInput request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        TimingRevisionAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            await antiforgery.ValidateRequestAsync(
                httpContext);

            var revision =
                await service.CreateRevisionAsync(
                    actorId,
                    recordingId,
                    request,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            return Results.Ok(
                revision);
        }
        catch (AntiforgeryValidationException)
        {
            return Results.Problem(
                statusCode:
                    StatusCodes.Status400BadRequest,
                title:
                    "Solicitud no válida",
                detail:
                    "Actualiza la página y vuelve a intentarlo.",
                extensions:
                    new Dictionary<string, object?>
                    {
                        ["code"] =
                            "content.timing.csrf.invalid"
                    });
        }
        catch (OverflowException)
        {
            return Results.Problem(
                statusCode:
                    StatusCodes.Status400BadRequest,
                title:
                    "Tiempos fuera de rango",
                detail:
                    "El desplazamiento y los segmentos producen una posición temporal inválida.",
                extensions:
                    new Dictionary<string, object?>
                    {
                        ["code"] =
                            "content.timing.offset.overflow"
                    });
        }
        catch (TimingAdministrationException exception)
        {
            return Problem(
                exception);
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

    private static IResult Problem(
        TimingAdministrationException exception)
    {
        var status =
            exception.Code switch
            {
                "content.timing.recording.not-found" =>
                    StatusCodes.Status404NotFound,
                "content.timing.lyrics-revision.not-found" =>
                    StatusCodes.Status404NotFound,
                "content.timing.source.not-found" =>
                    StatusCodes.Status404NotFound,
                "content.timing.source-duration.required" =>
                    StatusCodes.Status409Conflict,
                "content.timing.revision.conflict" =>
                    StatusCodes.Status409Conflict,
                _ =>
                    StatusCodes.Status400BadRequest
            };

        return Results.Problem(
            statusCode: status,
            title:
                status switch
                {
                    StatusCodes.Status404NotFound =>
                        "Objeto de sincronización no encontrado",
                    StatusCodes.Status409Conflict
                        when exception.Code == "content.timing.revision.conflict" =>
                        "Conflicto de sincronización",
                    StatusCodes.Status409Conflict =>
                        "Fuente todavía no validable",
                    _ =>
                        "Revisión de sincronización no válida"
                },
            detail: exception.Message,
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
    }

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var value =
            context.User.FindFirstValue(
                "account_id");

        return Guid.TryParse(
                value,
                out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode:
                StatusCodes.Status503ServiceUnavailable,
            title:
                "Sincronización temporalmente no disponible",
            detail:
                "La letra y el último estado confirmado permanecen intactos.",
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] =
                        "content.timing.unavailable"
                });
}
