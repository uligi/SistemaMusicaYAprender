using System.Security.Claims;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class TranslationRevisionAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapTranslationRevisionAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/translation-context",
                ReadContextAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.DRAFT", "EDITORIAL.REVIEW"],
                "EDITORIAL.TRANSLATION.READ",
                moduleCode: "M04",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialTranslationContext")
            .WithTags("Content");

        return endpoints;
    }

    private static async Task<IResult> ReadContextAsync(
        Guid recordingId,
        string? language,
        string? translationType,
        HttpContext httpContext,
        TranslationRevisionAdministrationService service)
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
                string.IsNullOrWhiteSpace(translationType) ? "HUMAN" : translationType,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            httpContext.Response.Headers["Cache-Control"] = "no-store";
            return Results.Ok(context);
        }
        catch (TranslationAdministrationException exception)
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

    private static IResult Problem(TranslationAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "content.translation.recording.not-found" => StatusCodes.Status404NotFound,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status == StatusCodes.Status404NotFound
                ? "Canción editorial no encontrada"
                : "Consulta de traducción no válida",
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
            title: "Traducción temporalmente no disponible",
            detail:
                "La revisión japonesa y el último estado confirmado permanecen intactos.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "content.translation.unavailable"
            });
}
