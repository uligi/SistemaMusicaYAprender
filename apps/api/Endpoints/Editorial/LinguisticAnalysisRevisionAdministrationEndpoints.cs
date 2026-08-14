using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class LinguisticAnalysisRevisionAdministrationEndpoints
{
    public static IEndpointRouteBuilder MapLinguisticAnalysisRevisionAdministration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/analysis-context",
                ReadContextAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.DRAFT", "EDITORIAL.REVIEW"],
                "EDITORIAL.ANALYSIS.READ",
                moduleCode: "M05",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialLinguisticAnalysisContext")
            .WithTags("Content");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/analysis-revisions/validate",
                ValidateRevisionAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M05",
                routeObjectKey: "recordingId")
            .WithName("ValidateEditorialLinguisticAnalysisRevision")
            .WithTags("Content");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/analysis-revisions",
                CreateRevisionAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M05",
                routeObjectKey: "recordingId")
            .WithName("CreateEditorialLinguisticAnalysisRevision")
            .WithTags("Content");

        return endpoints;
    }

    private static async Task<IResult> ReadContextAsync(
        Guid recordingId,
        string? language,
        HttpContext httpContext,
        LinguisticAnalysisRevisionAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId)) return Results.Unauthorized();

        try
        {
            var context = await service.ReadContextAsync(
                actorId,
                recordingId,
                string.IsNullOrWhiteSpace(language) ? "es" : language,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            ApplyContextETag(httpContext, context);
            return Results.Ok(context);
        }
        catch (LinguisticAnalysisAdministrationException exception) { return Problem(exception); }
        catch (NpgsqlException) { return Unavailable(); }
        catch (InvalidOperationException) { return Unavailable(); }
    }

    private static async Task<IResult> ValidateRevisionAsync(
        Guid recordingId,
        CreateLinguisticAnalysisRevisionInput request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        LinguisticAnalysisEditorialWriter writer)
    {
        if (!TryActor(httpContext, out var actorId)) return Results.Unauthorized();
        if (!TryIfMatch(httpContext, out var ifMatch)) return PreconditionRequired();

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            var report = await writer.ValidateAsync(
                actorId,
                recordingId,
                request,
                ifMatch,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            httpContext.Response.Headers["Cache-Control"] = "no-store";
            return Results.Ok(report);
        }
        catch (AntiforgeryValidationException) { return InvalidCsrf(); }
        catch (LinguisticAnalysisAdministrationException exception) { return Problem(exception); }
        catch (NpgsqlException) { return Unavailable(); }
        catch (InvalidOperationException) { return Unavailable(); }
    }

    private static async Task<IResult> CreateRevisionAsync(
        Guid recordingId,
        CreateLinguisticAnalysisRevisionInput request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        LinguisticAnalysisEditorialWriter writer)
    {
        if (!TryActor(httpContext, out var actorId)) return Results.Unauthorized();
        if (!TryIfMatch(httpContext, out var ifMatch)) return PreconditionRequired();

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            var context = await writer.CreateRevisionAsync(
                actorId,
                recordingId,
                request,
                ifMatch,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            ApplyContextETag(httpContext, context);
            return Results.Ok(context);
        }
        catch (AntiforgeryValidationException) { return InvalidCsrf(); }
        catch (LinguisticAnalysisValidationException exception)
        {
            return Results.UnprocessableEntity(exception.Report);
        }
        catch (LinguisticAnalysisAdministrationException exception) { return Problem(exception); }
        catch (NpgsqlException) { return Unavailable(); }
        catch (InvalidOperationException) { return Unavailable(); }
    }

    private static bool TryIfMatch(HttpContext context, out string ifMatch)
    {
        ifMatch = string.Empty;
        if (!context.Request.Headers.TryGetValue("If-Match", out var header)) return false;
        ifMatch = header.ToString();
        return !string.IsNullOrWhiteSpace(ifMatch);
    }

    private static IResult PreconditionRequired() =>
        Results.Problem(
            statusCode: StatusCodes.Status428PreconditionRequired,
            title: "Falta la revisión base",
            detail: "Recarga el análisis antes de validar o guardar.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "content.analysis.precondition-required"
            });

    private static IResult InvalidCsrf() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud no válida",
            detail: "Actualiza la página y vuelve a intentarlo.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "content.analysis.csrf.invalid"
            });

    private static IResult Problem(LinguisticAnalysisAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "content.analysis.recording.not-found" => StatusCodes.Status404NotFound,
            "content.analysis.conflict" or "content.analysis.source-changed" =>
                StatusCodes.Status412PreconditionFailed,
            "content.analysis.precondition-required" =>
                StatusCodes.Status428PreconditionRequired,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status switch
            {
                StatusCodes.Status404NotFound => "Canción editorial no encontrada",
                StatusCodes.Status412PreconditionFailed => "La letra o el análisis cambió",
                StatusCodes.Status428PreconditionRequired => "Falta la revisión base",
                _ => "Análisis lingüístico no válido"
            },
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static void ApplyContextETag(
        HttpContext context,
        LinguisticAnalysisContextSnapshot analysisContext)
    {
        context.Response.Headers["ETag"] =
            LinguisticAnalysisEditorialWriter.ETagFor(analysisContext);
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
            title: "Análisis lingüístico temporalmente no disponible",
            detail: "La letra japonesa y el último estado confirmado permanecen intactos.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "content.analysis.unavailable"
            });
}
