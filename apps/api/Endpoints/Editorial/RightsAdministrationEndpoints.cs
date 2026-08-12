using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public sealed record RightsScopeRequest(
    string TerritoryCode,
    string? LanguageTag,
    string ChannelCode,
    string UseCode);

public sealed record RightsAdministrationRequest(
    string HolderType,
    string HolderDisplayName,
    string BasisCode,
    DateTime? ValidFrom,
    DateTime? ValidTo,
    string EvidenceFileName,
    string EvidenceMediaType,
    string EvidenceBase64,
    IReadOnlyList<RightsScopeRequest> Scopes,
    string Reason,
    Guid? SupersedesRightsRecordId);

public static class RightsAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapRightsAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/rights",
                ReadAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.DRAFT", "EDITORIAL.REVIEW"],
                "EDITORIAL.DRAFT_OR_REVIEW",
                moduleCode: "M15",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialRights")
            .WithTags("Editorial");

        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/rights/evaluate",
                EvaluateAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.DRAFT", "EDITORIAL.REVIEW"],
                "EDITORIAL.DRAFT_OR_REVIEW",
                moduleCode: "M15",
                routeObjectKey: "recordingId")
            .WithName("EvaluateEditorialRights")
            .WithTags("Editorial");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/rights",
                CreateAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M15",
                routeObjectKey: "recordingId")
            .WithName("CreateEditorialRights")
            .WithTags("Editorial");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        HttpContext httpContext,
        RightsAdministrationService service)
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
        catch (RightsAdministrationException exception)
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

    private static async Task<IResult> EvaluateAsync(
        Guid recordingId,
        string territoryCode,
        string channelCode,
        string useCode,
        string? languageTag,
        HttpContext httpContext,
        RightsAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var result = await service.EvaluateAsync(
                actorId,
                recordingId,
                territoryCode,
                channelCode,
                useCode,
                languageTag,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return Results.Ok(result);
        }
        catch (RightsAdministrationException exception)
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
        RightsAdministrationRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        RightsAdministrationService service)
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
                detail: "Actualiza la pantalla y vuelve a intentar el registro de derechos.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "editorial.rights.idempotency-key.missing"
                });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var result = await service.CreateAsync(
                actorId,
                recordingId,
                new RightsAdministrationInput(
                    request.HolderType ?? string.Empty,
                    request.HolderDisplayName ?? string.Empty,
                    request.BasisCode ?? string.Empty,
                    request.ValidFrom,
                    request.ValidTo,
                    request.EvidenceFileName ?? string.Empty,
                    request.EvidenceMediaType ?? string.Empty,
                    request.EvidenceBase64 ?? string.Empty,
                    request.Scopes?
                        .Select(static scope => new RightsScopeInput(
                            scope.TerritoryCode ?? string.Empty,
                            scope.LanguageTag,
                            scope.ChannelCode ?? string.Empty,
                            scope.UseCode ?? string.Empty))
                        .ToArray()
                        ?? [],
                    request.Reason ?? string.Empty,
                    request.SupersedesRightsRecordId),
                idempotencyHeader.ToString(),
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return result.AlreadyApplied
                ? Results.Ok(result)
                : Results.Created(
                    $"/api/v1/editorial/song-drafts/{recordingId:D}/rights",
                    result);
        }
        catch (AntiforgeryValidationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Solicitud no válida",
                detail: "Actualiza la página y vuelve a intentarlo.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "editorial.rights.csrf.invalid"
                });
        }
        catch (RightsAdministrationException exception)
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

    private static IResult Problem(RightsAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "editorial.rights.recording.not-found" => StatusCodes.Status404NotFound,
            "editorial.rights.recording.not-draft" => StatusCodes.Status409Conflict,
            "editorial.rights.idempotency-conflict" => StatusCodes.Status409Conflict,
            "editorial.rights.supersedes.not-active" => StatusCodes.Status409Conflict,
            "editorial.rights.audit-role.missing" => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status switch
            {
                StatusCodes.Status404NotFound => "Objeto editorial no encontrado",
                StatusCodes.Status409Conflict => "El expediente de derechos requiere resolución",
                StatusCodes.Status403Forbidden => "Acción editorial no disponible",
                _ => "Datos de derechos no válidos"
            },
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Derechos editoriales temporalmente no disponibles",
            detail: "No se confirmó ningún cambio. Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "editorial.rights.unavailable"
            });
}
