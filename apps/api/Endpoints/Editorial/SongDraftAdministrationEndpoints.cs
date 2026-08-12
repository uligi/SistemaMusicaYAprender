using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Catalog.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public sealed record SongDraftRequest(
    Guid ArtistId,
    string CanonicalTitle,
    string LanguageTag,
    string? RecordingTitle,
    long? RecordingDurationMs,
    string YouTubeReference,
    long? SourceDurationMs,
    long OffsetMs,
    bool ExactRecordingConfirmed,
    bool AcknowledgePotentialDuplicates = false);

public static class SongDraftAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapSongDraftAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/duplicates",
                CheckDuplicatesAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02")
            .WithName("CheckEditorialSongDraftDuplicates")
            .WithTags("Catalog");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts",
                CreateAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02")
            .WithName("CreateEditorialSongDraft")
            .WithTags("Catalog");

        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}",
                ReadAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialSongDraft")
            .WithTags("Catalog");

        return endpoints;
    }

    private static async Task<IResult> CheckDuplicatesAsync(
        SongDraftRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        SongDraftAdministrationService service)
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

            var result = await service.CheckDuplicatesAsync(
                actorId,
                ToInput(request),
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return Results.Ok(result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (SongDraftAdministrationException exception)
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
        SongDraftRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        SongDraftAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        if (!httpContext.Request.Headers.TryGetValue(
                "Idempotency-Key",
                out var idempotencyHeader)
            || string.IsNullOrWhiteSpace(
                idempotencyHeader.ToString()))
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Falta la clave de idempotencia",
                detail:
                    "Actualiza la pantalla y vuelve a intentar el alta.",
                extensions:
                    new Dictionary<string, object?>
                    {
                        ["code"] =
                            "catalog.song-draft.idempotency-key.missing"
                    });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(
                httpContext);

            var result = await service.CreateAsync(
                actorId,
                ToInput(request),
                idempotencyHeader.ToString(),
                request.AcknowledgePotentialDuplicates,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return result.AlreadyApplied
                ? Results.Ok(result)
                : Results.Created(
                    $"/api/v1/editorial/song-drafts/{result.RecordingId:D}",
                    result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (SongDraftAdministrationException exception)
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

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        HttpContext httpContext,
        SongDraftAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var result = await service.ReadAsync(
                actorId,
                recordingId,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return Results.Ok(result);
        }
        catch (SongDraftAdministrationException exception)
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

    private static SongDraftInput ToInput(
        SongDraftRequest request) =>
        new(
            request.ArtistId,
            request.CanonicalTitle ?? string.Empty,
            request.LanguageTag ?? string.Empty,
            request.RecordingTitle,
            request.RecordingDurationMs,
            request.YouTubeReference ?? string.Empty,
            request.SourceDurationMs,
            request.OffsetMs,
            request.ExactRecordingConfirmed);

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var value =
            context.User.FindFirstValue("account_id");

        return Guid.TryParse(
                value,
                out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Problem(
        SongDraftAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "catalog.song-draft.duplicate-review-required" =>
                StatusCodes.Status409Conflict,
            "catalog.song-draft.youtube-source-conflict" =>
                StatusCodes.Status409Conflict,
            "catalog.song-draft.idempotency-conflict" =>
                StatusCodes.Status409Conflict,
            "catalog.song-draft.artist.not-found" =>
                StatusCodes.Status404NotFound,
            "catalog.song-draft.not-found" =>
                StatusCodes.Status404NotFound,
            "catalog.song-draft.audit-role.missing" =>
                StatusCodes.Status403Forbidden,
            _ =>
                StatusCodes.Status400BadRequest
        };

        var extensions =
            new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            };

        if (exception.Duplicates.Count > 0)
        {
            extensions["duplicates"] =
                exception.Duplicates;
        }

        return Results.Problem(
            statusCode: status,
            title: status switch
            {
                StatusCodes.Status409Conflict =>
                    "Revisión editorial requerida",
                StatusCodes.Status404NotFound =>
                    "Objeto de catálogo no encontrado",
                StatusCodes.Status403Forbidden =>
                    "Acción editorial no disponible",
                _ =>
                    "Datos de obra, grabación o fuente no válidos"
            },
            detail: exception.Message,
            extensions: extensions);
    }

    private static IResult CsrfInvalid() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud no válida",
            detail:
                "Actualiza la página y vuelve a intentarlo.",
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] =
                        "catalog.song-draft.csrf.invalid"
                });

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode:
                StatusCodes.Status503ServiceUnavailable,
            title:
                "Catálogo editorial temporalmente no disponible",
            detail:
                "No se confirmó ningún cambio. Vuelve a intentarlo más tarde.",
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] =
                        "catalog.song-draft.unavailable"
                });
}
