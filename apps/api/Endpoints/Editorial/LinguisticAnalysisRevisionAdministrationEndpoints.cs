using System.Security.Claims;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class LinguisticAnalysisRevisionAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapLinguisticAnalysisRevisionAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/analysis-context",
                ReadContextAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.DRAFT", "EDITORIAL.REVIEW"],
                "EDITORIAL.ANALYSIS.READ",
                moduleCode: "M05",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialLinguisticAnalysisContext")
            .WithTags("Content");

        return endpoints;
    }

    private static async Task<IResult> ReadContextAsync(
        Guid recordingId,
        string? language,
        HttpContext httpContext,
        LinguisticAnalysisRevisionAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var context = await service.ReadContextAsync(
                actorId,
                recordingId,
                string.IsNullOrWhiteSpace(language) ? "es" : language,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            httpContext.Response.Headers["Cache-Control"] = "no-store";
            return Results.Ok(context);
        }
        catch (LinguisticAnalysisAdministrationException exception)
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

    private static IResult Problem(LinguisticAnalysisAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "content.analysis.recording.not-found" => StatusCodes.Status404NotFound,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status == StatusCodes.Status404NotFound
                ? "Canción editorial no encontrada"
                : "Análisis lingüístico no válido",
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static bool TryActor(HttpContext context, out Guid actorId)
    {
        var value = context.User.FindFirstValue("account_id");
        return Guid.TryParse(value, out actorId) && actorId != Guid.Empty;
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Análisis lingüístico temporalmente no disponible",
            detail:
                "La letra japonesa y el último estado confirmado permanecen intactos.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "content.analysis.unavailable"
            });
}
