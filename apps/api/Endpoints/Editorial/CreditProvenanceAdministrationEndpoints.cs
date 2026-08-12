using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Catalog.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public sealed record CreditProvenanceRequest(
    Guid? ArtistId,
    string DisplayName,
    string RoleCode,
    int DisplayOrder,
    string SourceType,
    string Citation,
    string? Locator,
    string VerificationCode);

public static class CreditProvenanceAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapCreditProvenanceAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/credits",
                ReadAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.DRAFT", "EDITORIAL.REVIEW"],
                "EDITORIAL.DRAFT_OR_REVIEW",
                moduleCode: "M02",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialRecordingCredits")
            .WithTags("Catalog");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/credits",
                CreateAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M02",
                routeObjectKey: "recordingId")
            .WithName("CreateEditorialRecordingCredit")
            .WithTags("Catalog");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        HttpContext httpContext,
        CreditProvenanceAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
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
        catch (CreditProvenanceAdministrationException exception)
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
        Guid recordingId,
        CreditProvenanceRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        CreditProvenanceAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        if (!httpContext.Request.Headers.TryGetValue(
                "Idempotency-Key",
                out var idempotencyHeader)
            || string.IsNullOrWhiteSpace(idempotencyHeader.ToString()))
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
                            "catalog.credit.idempotency-key.missing"
                    });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var result = await service.CreateAsync(
                actorId,
                recordingId,
                new CreditProvenanceInput(
                    request.ArtistId,
                    request.DisplayName ?? string.Empty,
                    request.RoleCode ?? string.Empty,
                    request.DisplayOrder,
                    request.SourceType ?? string.Empty,
                    request.Citation ?? string.Empty,
                    request.Locator,
                    request.VerificationCode ?? string.Empty),
                idempotencyHeader.ToString(),
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return result.AlreadyApplied
                ? Results.Ok(result)
                : Results.Created(
                    $"/api/v1/editorial/song-drafts/{recordingId:D}/credits",
                    result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (CreditProvenanceAdministrationException exception)
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

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var value =
            context.User.FindFirstValue("account_id");

        return Guid.TryParse(value, out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Problem(
        CreditProvenanceAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "catalog.credit.recording.not-found" =>
                StatusCodes.Status404NotFound,
            "catalog.credit.artist.not-found" =>
                StatusCodes.Status404NotFound,
            "catalog.credit.recording.not-draft" =>
                StatusCodes.Status409Conflict,
            "catalog.credit.display-order.conflict" =>
                StatusCodes.Status409Conflict,
            "catalog.credit.duplicate" =>
                StatusCodes.Status409Conflict,
            "catalog.credit.idempotency-conflict" =>
                StatusCodes.Status409Conflict,
            "catalog.credit.audit-role.missing" =>
                StatusCodes.Status403Forbidden,
            _ =>
                StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status switch
            {
                StatusCodes.Status404NotFound =>
                    "Objeto de catálogo no encontrado",
                StatusCodes.Status409Conflict =>
                    "El crédito requiere resolución editorial",
                StatusCodes.Status403Forbidden =>
                    "Acción editorial no disponible",
                _ =>
                    "Datos de crédito o procedencia no válidos"
            },
            detail: exception.Message,
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
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
                        "catalog.credit.csrf.invalid"
                });

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode:
                StatusCodes.Status503ServiceUnavailable,
            title:
                "Créditos editoriales temporalmente no disponibles",
            detail:
                "No se confirmó ningún cambio. Vuelve a intentarlo más tarde.",
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] =
                        "catalog.credit.unavailable"
                });
}
