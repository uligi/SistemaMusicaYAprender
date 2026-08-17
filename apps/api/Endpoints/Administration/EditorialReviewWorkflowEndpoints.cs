using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Administration;

public sealed record AssignEditorialReviewerRequest(
    Guid ReviewerId,
    DateTimeOffset? DueAt,
    string Reason);

public sealed record DeclareEditorialReviewConflictRequest(
    string Reason);

public sealed record DecideEditorialReviewRequest(
    string DecisionCode,
    string Reason);

public static class EditorialReviewWorkflowEndpoints
{
    private static readonly string[] ReadPermissions =
    [
        "EDITORIAL.REVIEW",
        "EDITORIAL.PUBLISH"
    ];

    public static IEndpointRouteBuilder MapEditorialReviewWorkflow(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/administration/publications/{recordingId:guid}/review",
                ReadAsync)
            .RequireAnyEffectivePermission(
                ReadPermissions,
                "EDITORIAL.REVIEW.READ",
                "M15",
                "recordingId")
            .RequireRecentPrivilegedAssurance()
            .WithName("ReadEditorialReviewWorkflow")
            .WithTags("Administration", "Editorial");

        endpoints.MapPost(
                "/api/v1/administration/publications/{recordingId:guid}/review/assignments",
                AssignAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.PUBLISH"],
                "EDITORIAL.REVIEW.ASSIGN.AUTH",
                "M15",
                "recordingId")
            .RequireRecentPrivilegedAssurance()
            .WithName("AssignEditorialReviewer")
            .WithTags("Administration", "Editorial");

        endpoints.MapPost(
                "/api/v1/administration/publications/{recordingId:guid}/review/conflict",
                DeclareConflictAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.REVIEW"],
                "EDITORIAL.REVIEW.CONFLICT.AUTH",
                "M15",
                "recordingId")
            .RequireRecentPrivilegedAssurance()
            .WithName("DeclareEditorialReviewConflict")
            .WithTags("Administration", "Editorial");

        endpoints.MapPost(
                "/api/v1/administration/publications/{recordingId:guid}/review/decisions",
                DecideAsync)
            .RequireAnyEffectivePermission(
                ["EDITORIAL.REVIEW"],
                "EDITORIAL.REVIEW.DECIDE.AUTH",
                "M15",
                "recordingId")
            .RequireRecentPrivilegedAssurance()
            .WithName("DecideEditorialReview")
            .WithTags("Administration", "Editorial");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        HttpContext context,
        EditorialReviewWorkflowService service)
    {
        if (!TryActor(context, out var actorId))
            return Results.Unauthorized();

        try
        {
            var state = await service.ReadAsync(
                actorId,
                recordingId,
                context.TraceIdentifier,
                context.RequestAborted);

            context.Response.Headers.ETag = state.ETag;
            context.Response.Headers.CacheControl = "private, no-store";
            return Results.Ok(state);
        }
        catch (EditorialReviewWorkflowException exception)
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

    private static async Task<IResult> AssignAsync(
        Guid recordingId,
        AssignEditorialReviewerRequest request,
        HttpContext context,
        IAntiforgery antiforgery,
        EditorialReviewWorkflowService service)
    {
        if (!TryActor(context, out var actorId))
            return Results.Unauthorized();

        try
        {
            await antiforgery.ValidateRequestAsync(context);
            var state = await service.AssignAsync(
                actorId,
                recordingId,
                ReadIfMatch(context),
                new AssignEditorialReviewerCommand(
                    request.ReviewerId,
                    request.DueAt,
                    request.Reason),
                context.TraceIdentifier,
                context.RequestAborted);

            context.Response.Headers.ETag = state.ETag;
            return Results.Ok(state);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (EditorialReviewWorkflowException exception)
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

    private static async Task<IResult> DeclareConflictAsync(
        Guid recordingId,
        DeclareEditorialReviewConflictRequest request,
        HttpContext context,
        IAntiforgery antiforgery,
        EditorialReviewWorkflowService service)
    {
        if (!TryActor(context, out var actorId))
            return Results.Unauthorized();

        try
        {
            await antiforgery.ValidateRequestAsync(context);
            var state = await service.DeclareConflictAsync(
                actorId,
                recordingId,
                ReadIfMatch(context),
                new DeclareEditorialReviewConflictCommand(request.Reason),
                context.TraceIdentifier,
                context.RequestAborted);

            context.Response.Headers.ETag = state.ETag;
            return Results.Ok(state);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (EditorialReviewWorkflowException exception)
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

    private static async Task<IResult> DecideAsync(
        Guid recordingId,
        DecideEditorialReviewRequest request,
        HttpContext context,
        IAntiforgery antiforgery,
        EditorialReviewWorkflowService service)
    {
        if (!TryActor(context, out var actorId))
            return Results.Unauthorized();

        try
        {
            await antiforgery.ValidateRequestAsync(context);
            var state = await service.DecideAsync(
                actorId,
                recordingId,
                ReadIfMatch(context),
                new DecideEditorialReviewCommand(
                    request.DecisionCode,
                    request.Reason),
                context.TraceIdentifier,
                context.RequestAborted);

            context.Response.Headers.ETag = state.ETag;
            return Results.Ok(state);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (EditorialReviewWorkflowException exception)
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

    private static string ReadIfMatch(HttpContext context) =>
        context.Request.Headers.IfMatch.ToString();

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var raw = context.User.FindFirstValue("account_id");
        return Guid.TryParse(raw, out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Problem(
        EditorialReviewWorkflowException exception) =>
        Results.Problem(
            statusCode: exception.StatusCode,
            title: exception.StatusCode switch
            {
                403 => "Acción de revisión no permitida",
                404 => "Revisión no encontrada",
                412 => "La revisión cambió",
                422 => "Checklist de revisión incompleto",
                428 => "Falta condición de concurrencia",
                _ => "No se pudo completar la revisión"
            },
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });

    private static IResult CsrfInvalid() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud de revisión inválida",
            detail: "La protección antifalsificación no pudo validarse.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.csrf.invalid"
            });

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Revisión temporalmente no disponible",
            detail: "No se modificó la publicación. Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "editorial.review.unavailable"
            });
}
