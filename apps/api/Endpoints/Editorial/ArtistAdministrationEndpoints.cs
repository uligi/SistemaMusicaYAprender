using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Catalog.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public sealed record ArtistAliasRequest(
    string AliasText,
    string LanguageTag,
    string ScriptCode,
    bool Preferred);

public sealed record ArtistDraftRequest(
    string CanonicalName,
    string SortName,
    string ArtistType,
    string CanonicalLanguageTag,
    string CanonicalScriptCode,
    IReadOnlyList<ArtistAliasRequest>? Aliases,
    bool AcknowledgePotentialDuplicates = false);

public static class ArtistAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapArtistAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/artists",
                SearchAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02")
            .WithName("SearchEditorialArtists")
            .WithTags("Catalog");

        endpoints.MapPost(
                "/api/v1/editorial/artists/duplicates",
                CheckDuplicatesAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02")
            .WithName("CheckEditorialArtistDuplicates")
            .WithTags("Catalog");

        endpoints.MapPost(
                "/api/v1/editorial/artists",
                CreateAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02")
            .WithName("CreateEditorialArtist")
            .WithTags("Catalog");

        return endpoints;
    }

    private static async Task<IResult> SearchAsync(
        string? query,
        HttpContext httpContext,
        ArtistAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var results = await service.SearchAsync(
                actorId,
                query ?? string.Empty,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);
            return Results.Ok(results);
        }
        catch (ArtistAdministrationException exception)
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

    private static async Task<IResult> CheckDuplicatesAsync(
        ArtistDraftRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        ArtistAdministrationService service)
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

            var result =
                await service.CheckDuplicatesAsync(
                    actorId,
                    ToDraft(request),
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            return Results.Ok(result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (ArtistAdministrationException exception)
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
        ArtistDraftRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        ArtistAdministrationService service)
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
                            "catalog.artist.idempotency-key.missing"
                    });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(
                httpContext);

            var result =
                await service.CreateAsync(
                    actorId,
                    ToDraft(request),
                    idempotencyHeader.ToString(),
                    request.AcknowledgePotentialDuplicates,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            return result.AlreadyApplied
                ? Results.Ok(result)
                : Results.Created(
                    $"/api/v1/editorial/artists?query={Uri.EscapeDataString(result.CanonicalName)}",
                    result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (ArtistAdministrationException exception)
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

    private static ArtistDraft ToDraft(
        ArtistDraftRequest request) =>
        new(
            request.CanonicalName ?? string.Empty,
            request.SortName ?? string.Empty,
            request.ArtistType ?? string.Empty,
            request.CanonicalLanguageTag ?? string.Empty,
            request.CanonicalScriptCode ?? string.Empty,
            (request.Aliases ?? [])
                .Select(static alias =>
                    new ArtistAliasDraft(
                        alias.AliasText ?? string.Empty,
                        alias.LanguageTag ?? string.Empty,
                        alias.ScriptCode ?? string.Empty,
                        alias.Preferred))
                .ToArray());

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
        ArtistAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "catalog.artist.duplicate-review-required" =>
                StatusCodes.Status409Conflict,
            "catalog.artist.idempotency-conflict" =>
                StatusCodes.Status409Conflict,
            "catalog.artist.audit-role.missing" =>
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
            title:
                status == StatusCodes.Status409Conflict
                    ? "Revisión editorial requerida"
                    : "Datos de artista no válidos",
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
                        "catalog.artist.csrf.invalid"
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
                        "catalog.artist.unavailable"
                });
}
