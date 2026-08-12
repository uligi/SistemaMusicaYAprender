using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Catalog.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public sealed record RecordingDraftAutosaveRequest(
    string? RecordingTitle,
    long? RecordingDurationMs,
    long? SourceDurationMs,
    long OffsetMs);

public static class RecordingDraftAutosaveEndpoints
{
    public static IEndpointRouteBuilder MapRecordingDraftAutosave(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/autosave",
                ReadAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialRecordingAutosave")
            .WithTags("Catalog");

        endpoints.MapPut(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/autosave",
                SaveAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02",
                routeObjectKey: "recordingId")
            .WithName("SaveEditorialRecordingAutosave")
            .WithTags("Catalog");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        HttpContext httpContext,
        RecordingDraftAutosaveService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var snapshot =
                await service.ReadAsync(
                    actorId,
                    recordingId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            ApplyVersionHeaders(
                httpContext,
                snapshot);

            return Results.Ok(snapshot);
        }
        catch (RecordingDraftAutosaveException exception)
        {
            return Problem(
                httpContext,
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

    private static async Task<IResult> SaveAsync(
        Guid recordingId,
        RecordingDraftAutosaveRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        RecordingDraftAutosaveService service)
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
                    "Falta la versión editorial",
                detail:
                    "Recarga el borrador antes de intentar guardarlo.",
                extensions:
                    new Dictionary<string, object?>
                    {
                        ["code"] =
                            "catalog.recording.autosave.precondition-required"
                    });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(
                httpContext);

            var snapshot =
                await service.SaveAsync(
                    actorId,
                    recordingId,
                    new RecordingDraftAutosaveInput(
                        request.RecordingTitle,
                        request.RecordingDurationMs,
                        request.SourceDurationMs,
                        request.OffsetMs),
                    ifMatchHeader.ToString(),
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            ApplyVersionHeaders(
                httpContext,
                snapshot);

            return Results.Ok(snapshot);
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
                            "catalog.recording.autosave.csrf.invalid"
                    });
        }
        catch (RecordingDraftAutosaveException exception)
        {
            return Problem(
                httpContext,
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
        HttpContext httpContext,
        RecordingDraftAutosaveException exception)
    {
        if (exception.Current is { } current)
        {
            ApplyVersionHeaders(
                httpContext,
                current);
        }

        var status = exception.Code switch
        {
            "catalog.recording.autosave.conflict" =>
                StatusCodes.Status412PreconditionFailed,
            "catalog.recording.autosave.not-editable" =>
                StatusCodes.Status409Conflict,
            "catalog.recording.autosave.not-found" =>
                StatusCodes.Status404NotFound,
            "catalog.recording.autosave.precondition-required" =>
                StatusCodes.Status428PreconditionRequired,
            _ =>
                StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status switch
            {
                StatusCodes.Status412PreconditionFailed =>
                    "Hay una versión editorial más reciente",
                StatusCodes.Status409Conflict =>
                    "El borrador ya no puede editarse",
                StatusCodes.Status404NotFound =>
                    "Grabación no encontrada",
                StatusCodes.Status428PreconditionRequired =>
                    "Falta la versión editorial",
                _ =>
                    "Datos de autoguardado no válidos"
            },
            detail: exception.Message,
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
    }

    private static void ApplyVersionHeaders(
        HttpContext context,
        RecordingDraftAutosaveSnapshot snapshot)
    {
        context.Response.Headers["ETag"] =
            snapshot.ETag;
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
                "Autoguardado editorial temporalmente no disponible",
            detail:
                "Los cambios locales se conservaron. Vuelve a intentarlo cuando el servicio esté disponible.",
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] =
                        "catalog.recording.autosave.unavailable"
                });
}
