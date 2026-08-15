using System.Security.Claims;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class EditorialKaraokePreviewEndpoints
{
    public static IEndpointRouteBuilder MapEditorialKaraokePreview(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/karaoke-preview",
                ReadAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialKaraokePreview")
            .WithTags("Content");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        Guid sourceId,
        string? language,
        HttpContext httpContext,
        EditorialKaraokePreviewService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        if (sourceId == Guid.Empty)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Falta la fuente de previsualizacion",
                detail:
                    "Selecciona una fuente de YouTube de la grabacion antes de abrir el karaoke.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.karaoke-preview.source.required"
                });
        }

        try
        {
            var preview = await service.ReadAsync(
                actorId,
                recordingId,
                sourceId,
                string.IsNullOrWhiteSpace(language) ? "es" : language,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            httpContext.Response.Headers["Cache-Control"] = "no-store";
            return Results.Ok(preview);
        }
        catch (EditorialKaraokePreviewException exception)
        {
            var status = exception.Code switch
            {
                "content.karaoke-preview.source.not-found" =>
                    StatusCodes.Status404NotFound,
                "content.karaoke-preview.provider.unsupported" =>
                    StatusCodes.Status409Conflict,
                "content.karaoke-preview.lyrics.changed" =>
                    StatusCodes.Status409Conflict,
                _ =>
                    StatusCodes.Status400BadRequest
            };

            return Results.Problem(
                statusCode: status,
                title: "Previsualizacion de karaoke no disponible",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
        }
        catch (Exception exception) when (
            exception is LyricsStructureAdministrationException
            or TimingAdministrationException
            or TranslationAdministrationException
            or LinguisticAnalysisAdministrationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "El borrador cambio",
                detail:
                    "Recarga la previsualizacion para usar las revisiones editoriales compatibles mas recientes.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.karaoke-preview.draft-changed"
                });
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
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Previsualizacion temporalmente no disponible",
            detail:
                "El borrador editorial permanece intacto. Vuelve a intentarlo cuando el servicio este disponible.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "content.karaoke-preview.unavailable"
            });
}
