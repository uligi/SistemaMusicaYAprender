using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Learning.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class FillBlankExerciseAuthoringEndpoints
{
    public static IEndpointRouteBuilder MapFillBlankExerciseAuthoring(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/exercise-authoring-context",
                ReadContextAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M08",
                routeObjectKey: "recordingId")
            .WithName("ReadFillBlankExerciseAuthoringContext")
            .WithTags("Learning");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/fill-blank-exercise-drafts",
                SaveDraftAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M08",
                routeObjectKey: "recordingId")
            .WithName("SaveFillBlankExerciseDraft")
            .WithTags("Learning");

        return endpoints;
    }

    private static async Task<IResult> ReadContextAsync(
        Guid recordingId,
        HttpContext httpContext,
        FillBlankExerciseAuthoringService service)
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
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            ApplyETag(httpContext, context);
            return Results.Ok(context);
        }
        catch (FillBlankExerciseAuthoringException exception)
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

    private static async Task<IResult> SaveDraftAsync(
        Guid recordingId,
        FillBlankDraftInput request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        FillBlankExerciseAuthoringService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        if (!httpContext.Request.Headers.TryGetValue("If-Match", out var ifMatch)
            || string.IsNullOrWhiteSpace(ifMatch.ToString()))
        {
            return Results.Problem(
                statusCode: StatusCodes.Status428PreconditionRequired,
                title: "Falta la revisión base",
                detail: "Recarga la fuente DRAFT antes de guardar el ejercicio.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "learning.fill-blank.precondition-required"
                });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var saved = await service.SaveDraftAsync(
                actorId,
                recordingId,
                request,
                ifMatch.ToString(),
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            var context = await service.ReadContextAsync(
                actorId,
                recordingId,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            ApplyETag(httpContext, context);
            return Results.Ok(saved);
        }
        catch (AntiforgeryValidationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Solicitud no válida",
                detail: "Actualiza la página y vuelve a intentarlo.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "learning.fill-blank.csrf.invalid"
                });
        }
        catch (FillBlankExerciseAuthoringException exception)
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

    private static IResult Problem(FillBlankExerciseAuthoringException exception)
    {
        var status = exception.Code switch
        {
            "learning.fill-blank.recording.not-found" => StatusCodes.Status404NotFound,
            "learning.fill-blank.source-changed" => StatusCodes.Status412PreconditionFailed,
            "learning.fill-blank.precondition-required" => StatusCodes.Status428PreconditionRequired,
            _ => StatusCodes.Status400BadRequest
        };

        var title = status switch
        {
            StatusCodes.Status404NotFound => "Canción editorial no encontrada",
            StatusCodes.Status412PreconditionFailed => "La fuente DRAFT cambió",
            StatusCodes.Status428PreconditionRequired => "Falta la revisión base",
            _ => "Revisa el ejercicio"
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

    private static void ApplyETag(
        HttpContext context,
        FillBlankAuthoringContext authoringContext)
    {
        context.Response.Headers["ETag"] =
            FillBlankExerciseAuthoringService.ETagFor(authoringContext);
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
            title: "Autoría de ejercicios temporalmente no disponible",
            detail: "Tu contenido confirmado permanece intacto.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "learning.fill-blank.unavailable"
            });
}
