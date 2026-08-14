using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
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

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/translation-revisions",
                CreateRevisionAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M04",
                routeObjectKey: "recordingId")
            .WithName("CreateEditorialTranslationRevision")
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

            ApplyContextETag(httpContext, context);
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

    private static async Task<IResult> CreateRevisionAsync(
        Guid recordingId,
        CreateTranslationRevisionInput request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        TranslationRevisionAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        if (!httpContext.Request.Headers.TryGetValue("If-Match", out var ifMatchHeader)
            || string.IsNullOrWhiteSpace(ifMatchHeader.ToString()))
        {
            return Results.Problem(
                statusCode: StatusCodes.Status428PreconditionRequired,
                title: "Falta la revisión base",
                detail: "Recarga la traducción antes de guardar el borrador.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.translation.precondition-required"
                });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var context = await service.CreateRevisionAsync(
                actorId,
                recordingId,
                request,
                ifMatchHeader.ToString(),
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            ApplyContextETag(httpContext, context);
            return Results.Ok(context);
        }
        catch (AntiforgeryValidationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Solicitud no válida",
                detail: "Actualiza la página y vuelve a intentarlo.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.translation.csrf.invalid"
                });
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
            "content.translation.conflict" => StatusCodes.Status412PreconditionFailed,
            "content.translation.source-changed" => StatusCodes.Status412PreconditionFailed,
            "content.translation.precondition-required" => StatusCodes.Status428PreconditionRequired,
            _ => StatusCodes.Status400BadRequest
        };

        var title = status switch
        {
            StatusCodes.Status404NotFound => "Canción editorial no encontrada",
            StatusCodes.Status412PreconditionFailed => "La fuente o traducción cambió",
            StatusCodes.Status428PreconditionRequired => "Falta la revisión base",
            _ => "Traducción no válida"
        };

        return Results.Problem(
            statusCode: status,
            title: title,
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static void ApplyContextETag(
        HttpContext context,
        TranslationContextSnapshot translationContext)
    {
        context.Response.Headers["ETag"] =
            TranslationRevisionAdministrationService.ETagFor(translationContext);
        context.Response.Headers["Cache-Control"] = "no-store";
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
