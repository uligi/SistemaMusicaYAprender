using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public sealed record LyricsStructureResponse(
    bool Exists,
    LyricsRevisionSnapshot? Revision);

public static class LyricsStructureAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapLyricsStructureAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/lyrics-revisions/latest",
                ReadLatestAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("ReadLatestEditorialLyricsRevision")
            .WithTags("Content");

        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/lyrics-revisions/{lyricsRevisionId:guid}/segmentation-impact",
                ReadSegmentationImpactAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialLyricsSegmentationImpact")
            .WithTags("Content");
        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/lyrics-revisions",
                CreateAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("CreateEditorialLyricsRevision")
            .WithTags("Content");

        return endpoints;
    }

    private static async Task<IResult> ReadLatestAsync(
        Guid recordingId,
        HttpContext httpContext,
        LyricsStructureAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var revision =
                await service.ReadLatestAsync(
                    actorId,
                    recordingId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            ApplyRevisionETag(
                httpContext,
                revision);

            return Results.Ok(
                new LyricsStructureResponse(
                    revision is not null,
                    revision));
        }
        catch (LyricsStructureAdministrationException exception)
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

    private static async Task<IResult> ReadSegmentationImpactAsync(
        Guid recordingId,
        Guid lyricsRevisionId,
        HttpContext httpContext,
        LyricsStructureAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var impact =
                await service.ReadSegmentationImpactAsync(
                    actorId,
                    recordingId,
                    lyricsRevisionId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            return Results.Ok(impact);
        }
        catch (LyricsStructureAdministrationException exception)
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
    private static async Task<IResult> CreateAsync(
        Guid recordingId,
        CreateLyricsRevisionInput request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        LyricsStructureAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        if (!httpContext.Request.Headers.TryGetValue(
                "If-Match",
                out var ifMatchHeader)
            || string.IsNullOrWhiteSpace(
                ifMatchHeader.ToString()))
        {
            return Results.Problem(
                statusCode:
                    StatusCodes.Status428PreconditionRequired,
                title:
                    "Falta la revisión base",
                detail:
                    "Recarga la revisión de letra antes de guardar cambios.",
                extensions:
                    new Dictionary<string, object?>
                    {
                        ["code"] =
                            "content.lyrics.precondition-required"
                    });
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
                    ifMatchHeader.ToString(),
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            ApplyRevisionETag(
                httpContext,
                revision);

            return Results.Ok(
                new LyricsStructureResponse(
                    true,
                    revision));
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
                            "content.lyrics.csrf.invalid"
                    });
        }
        catch (LyricsStructureAdministrationException exception)
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
        LyricsStructureAdministrationException exception)
    {
        var status =
            exception.Code switch
            {
                "content.lyrics.recording.not-found" =>
                    StatusCodes.Status404NotFound,
                "content.lyrics.revision.not-found" =>
                    StatusCodes.Status404NotFound,
                "content.lyrics.conflict" =>
                    StatusCodes.Status412PreconditionFailed,
                "content.lyrics.precondition-required" =>
                    StatusCodes.Status428PreconditionRequired,
                _ =>
                    StatusCodes.Status400BadRequest
            };

        return Results.Problem(
            statusCode: status,
            title:
                status switch
                {
                    StatusCodes.Status404NotFound =>
                        "Grabación no encontrada",
                    StatusCodes.Status412PreconditionFailed =>
                        "Hay una revisión de letra más reciente",
                    StatusCodes.Status428PreconditionRequired =>
                        "Falta la revisión base",
                    _ =>
                        "Estructura de letra no válida"
                },
            detail: exception.Message,
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
    }

    private static void ApplyRevisionETag(
        HttpContext context,
        LyricsRevisionSnapshot? revision)
    {
        context.Response.Headers["ETag"] =
            revision is null
                ? "\"lyrics-none\""
                : $"\"lyrics-{revision.LyricsRevisionId:N}-v{revision.Version}\"";
        context.Response.Headers["Cache-Control"] =
            "no-store";
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
                "Estructura de letra temporalmente no disponible",
            detail:
                "El último estado confirmado permanece intacto. Vuelve a intentarlo cuando el servicio esté disponible.",
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] =
                        "content.lyrics.unavailable"
                });
}
