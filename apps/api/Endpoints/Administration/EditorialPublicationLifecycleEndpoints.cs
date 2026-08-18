using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Administration;

public sealed record PublishEditorialPackageRequest(
    Guid PackageId,
    string TerritoryCode,
    string? LanguageTag,
    string AudienceCode,
    string Reason);

public sealed record CorrectEditorialPublicationRequest(
    string ActionCode,
    Guid? TargetPublicationId,
    Guid? TargetPackageId,
    string? TerritoryCode,
    string? LanguageTag,
    string? AudienceCode,
    string Reason);

public static class EditorialPublicationLifecycleEndpoints
{
    public static IEndpointRouteBuilder MapEditorialPublicationLifecycle(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/administration/publications/{recordingId:guid}/publication",
                ReadPublicationAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.REVIEW", "EDITORIAL.PUBLISH"],
                "EDITORIAL.PUBLICATION.READ",
                "M15",
                "recordingId")
            .RequireRecentPrivilegedAssurance()
            .WithName("ReadEditorialPublication")
            .WithTags("Administration", "Editorial");

        endpoints.MapPost(
                "/api/v1/administration/publications/{recordingId:guid}/publication",
                PublishAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.PUBLISH"],
                "EDITORIAL.PUBLICATION.ACTIVATE.AUTH",
                "M15",
                "recordingId")
            .RequireRecentPrivilegedAssurance()
            .WithName("PublishEditorialPackage")
            .WithTags("Administration", "Editorial");

        endpoints.MapGet(
                "/api/v1/administration/corrections/{recordingId:guid}",
                ReadCorrectionAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.CORRECT"],
                "EDITORIAL.CORRECTION.READ",
                "M15",
                "recordingId")
            .RequireRecentPrivilegedAssurance()
            .WithName("ReadEditorialCorrection")
            .WithTags("Administration", "Editorial");

        endpoints.MapPost(
                "/api/v1/administration/corrections/{recordingId:guid}/actions",
                CorrectAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.CORRECT"],
                "EDITORIAL.CORRECTION.WRITE",
                "M15",
                "recordingId")
            .RequireRecentPrivilegedAssurance()
            .WithName("CorrectEditorialPublication")
            .WithTags("Administration", "Editorial");

        return endpoints;
    }

    private static async Task<IResult> ReadPublicationAsync(
        Guid recordingId,
        Guid? packageId,
        HttpContext context,
        EditorialPublicationLifecycleService service)
    {
        if (!TryActor(context, out var actorId))
            return Results.Unauthorized();

        try
        {
            var state = await service.ReadPublicationAsync(
                actorId,
                recordingId,
                packageId,
                context.TraceIdentifier,
                context.RequestAborted);

            context.Response.Headers.ETag = state.ETag;
            context.Response.Headers.CacheControl = "private, no-store";
            return Results.Ok(state);
        }
        catch (EditorialPublicationLifecycleException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> PublishAsync(
        Guid recordingId,
        PublishEditorialPackageRequest request,
        HttpContext context,
        IAntiforgery antiforgery,
        EditorialPublicationLifecycleService service)
    {
        if (!TryActor(context, out var actorId))
            return Results.Unauthorized();

        try
        {
            await antiforgery.ValidateRequestAsync(context);

            var state = await service.PublishAsync(
                actorId,
                recordingId,
                new PublishEditorialPackageCommand(
                    request.PackageId,
                    request.TerritoryCode,
                    request.LanguageTag,
                    request.AudienceCode,
                    request.Reason),
                ReadIfMatch(context),
                ReadIdempotencyKey(context),
                context.TraceIdentifier,
                context.RequestAborted);

            context.Response.Headers.ETag = state.ETag;
            return Results.Ok(state);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (EditorialPublicationLifecycleException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> ReadCorrectionAsync(
        Guid recordingId,
        HttpContext context,
        EditorialPublicationLifecycleService service)
    {
        if (!TryActor(context, out var actorId))
            return Results.Unauthorized();

        try
        {
            var state = await service.ReadCorrectionAsync(
                actorId,
                recordingId,
                context.TraceIdentifier,
                context.RequestAborted);

            context.Response.Headers.ETag = state.ETag;
            context.Response.Headers.CacheControl = "private, no-store";
            return Results.Ok(state);
        }
        catch (EditorialPublicationLifecycleException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> CorrectAsync(
        Guid recordingId,
        CorrectEditorialPublicationRequest request,
        HttpContext context,
        IAntiforgery antiforgery,
        EditorialPublicationLifecycleService service)
    {
        if (!TryActor(context, out var actorId))
            return Results.Unauthorized();

        try
        {
            await antiforgery.ValidateRequestAsync(context);

            var state = await service.CorrectAsync(
                actorId,
                recordingId,
                new CorrectEditorialPublicationCommand(
                    request.ActionCode,
                    request.TargetPublicationId,
                    request.TargetPackageId,
                    request.TerritoryCode,
                    request.LanguageTag,
                    request.AudienceCode,
                    request.Reason),
                ReadIfMatch(context),
                ReadIdempotencyKey(context),
                context.TraceIdentifier,
                context.RequestAborted);

            context.Response.Headers.ETag = state.ETag;
            return Results.Ok(state);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (EditorialPublicationLifecycleException exception)
        {
            return Problem(exception);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
    }

    private static string ReadIfMatch(HttpContext context) =>
        context.Request.Headers.IfMatch.ToString();

    private static string ReadIdempotencyKey(HttpContext context) =>
        context.Request.Headers["Idempotency-Key"].ToString();

    private static bool TryActor(HttpContext context, out Guid actorId)
    {
        var raw = context.User.FindFirstValue("account_id");
        return Guid.TryParse(raw, out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Problem(
        EditorialPublicationLifecycleException exception) =>
        Results.Problem(
            statusCode: exception.StatusCode,
            title: exception.StatusCode switch
            {
                403 => "Acción editorial no permitida",
                404 => "Publicación no encontrada",
                412 => "La publicación cambió",
                422 => "Publicación bloqueada",
                428 => "Falta condición de concurrencia",
                _ => "No se pudo completar la publicación"
            },
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });

    private static IResult CsrfInvalid() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud editorial inválida",
            detail: "La protección antifalsificación no pudo validarse.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.csrf.invalid"
            });

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Publicación temporalmente no disponible",
            detail: "No se confirmó ningún estado parcial. Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "editorial.publication.unavailable"
            });
}
