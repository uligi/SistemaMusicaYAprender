using System.Security.Claims;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Learning.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class ExerciseBankAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapExerciseBankAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/exercise-bank",
                ReadAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M08",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialExerciseBank")
            .WithTags("Learning");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        HttpContext httpContext,
        ExerciseBankAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var snapshot = await service.ReadAsync(
                actorId,
                recordingId,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            httpContext.Response.Headers["Cache-Control"] = "no-store";
            return Results.Ok(snapshot);
        }
        catch (ExerciseBankAdministrationException exception)
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

    private static bool TryActor(HttpContext context, out Guid actorId)
    {
        var value = context.User.FindFirstValue("account_id");
        return Guid.TryParse(value, out actorId) && actorId != Guid.Empty;
    }

    private static IResult Problem(ExerciseBankAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "learning.exercise-bank.recording.not-found" => StatusCodes.Status404NotFound,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status == StatusCodes.Status404NotFound
                ? "Canción editorial no encontrada"
                : "Banco de ejercicios no válido",
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Banco de ejercicios temporalmente no disponible",
            detail: "Los ejercicios y revisiones confirmados permanecen intactos.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "learning.exercise-bank.unavailable"
            });
}
