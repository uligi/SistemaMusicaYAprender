using System.Security.Claims;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class EditorialContextualAnalysisPreviewEndpoints
{
    public static IEndpointRouteBuilder MapEditorialContextualAnalysisPreview(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/analysis-preview/{token}",
                ReadAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialContextualAnalysisPreview")
            .WithTags("Content");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        string token,
        string? language,
        HttpContext httpContext,
        EditorialContextualAnalysisPreviewService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        httpContext.Response.Headers["Cache-Control"] = "no-store";

        try
        {
            var preview = await service.ReadAsync(
                actorId,
                recordingId,
                token,
                string.IsNullOrWhiteSpace(language) ? "es" : language,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return preview is null
                ? Results.NotFound()
                : Results.Ok(preview);
        }
        catch (EditorialContextualAnalysisPreviewException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Análisis DRAFT no disponible de forma segura",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
        }
        catch (LinguisticAnalysisAdministrationException exception)
        {
            var status = exception.Code == "content.analysis.recording.not-found"
                ? StatusCodes.Status404NotFound
                : StatusCodes.Status409Conflict;

            return Results.Problem(
                statusCode: status,
                title: "Análisis editorial no disponible",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Referencia de análisis DRAFT inválida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.analysis-preview.invalid-route"
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
        var value = context.User.FindFirstValue("account_id");

        return Guid.TryParse(value, out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Análisis DRAFT temporalmente no disponible",
            detail:
                "El borrador editorial permanece intacto. Vuelve a intentarlo cuando el servicio esté disponible.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "content.analysis-preview.unavailable"
            });
}
