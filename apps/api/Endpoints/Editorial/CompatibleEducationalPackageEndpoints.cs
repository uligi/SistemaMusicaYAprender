using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class CompatibleEducationalPackageEndpoints
{
    private static readonly string[] PackagePermissions =
    [
        "EDITORIAL.SUBMIT",
        "EDITORIAL.REVIEW"
    ];

    private static readonly string[] SubmitPermissions =
    [
        "EDITORIAL.SUBMIT"
    ];

    public static IEndpointRouteBuilder MapCompatibleEducationalPackage(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/compatible-package",
                ReadAsync)
            .RequireAnyEffectivePermission(
                PackagePermissions,
                "EDITORIAL.PACKAGE.READ",
                moduleCode: "M15",
                routeObjectKey: "recordingId")
            .WithName("ReadCompatibleEducationalPackage")
            .WithTags("Editorial");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/compatible-package",
                SaveAsync)
            .RequireAnyEffectivePermission(
                PackagePermissions,
                "EDITORIAL.PACKAGE.ASSEMBLE",
                moduleCode: "M15",
                routeObjectKey: "recordingId")
            .WithName("SaveCompatibleEducationalPackage")
            .WithTags("Editorial");

        endpoints.MapPost(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/compatible-package/submit",
                SubmitAsync)
            .RequireAnyEffectivePermission(
                SubmitPermissions,
                "EDITORIAL.PACKAGE.SUBMIT",
                moduleCode: "M15",
                routeObjectKey: "recordingId")
            .WithName("SubmitCompatibleEducationalPackage")
            .WithTags("Editorial");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        HttpContext httpContext,
        CompatibleEducationalPackageService service,
        ICompatibleEducationalPackageTransactionExecutor transactions)
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

            var submission =
                await new EducationalPackageSubmissionService(transactions)
                    .ReadLatestAsync(
                        actorId,
                        recordingId,
                        httpContext.TraceIdentifier,
                        httpContext.RequestAborted);

            ApplyHeaders(httpContext, snapshot);
            return Results.Ok(
                CompatiblePackageWorkspaceResponse.From(
                    snapshot,
                    submission));
        }
        catch (CompatibleEducationalPackageException exception)
        {
            return Problem(exception);
        }
        catch (EducationalPackageSubmissionException exception)
        {
            return SubmissionProblem(exception);
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
        CompatiblePackageSelectionInput request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        CompatibleEducationalPackageService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        if (!httpContext.Request.Headers.TryGetValue(
                "If-Match",
                out var ifMatch)
            || string.IsNullOrWhiteSpace(ifMatch.ToString()))
        {
            return Results.Problem(
                statusCode: StatusCodes.Status428PreconditionRequired,
                title: "Falta la versión base del paquete",
                detail: "Recarga el espacio de paquete antes de guardar.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "editorial.package.precondition-required"
                });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var snapshot = await service.SaveAsync(
                actorId,
                recordingId,
                request,
                ifMatch.ToString(),
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            ApplyHeaders(httpContext, snapshot);
            return Results.Ok(snapshot);
        }
        catch (AntiforgeryValidationException)
        {
            return InvalidCsrf();
        }
        catch (CompatibleEducationalPackageException exception)
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

    private static async Task<IResult> SubmitAsync(
        Guid recordingId,
        EducationalPackageSubmissionInput request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        ICompatibleEducationalPackageTransactionExecutor transactions)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        if (!httpContext.Request.Headers.TryGetValue(
                "If-Match",
                out var ifMatch)
            || string.IsNullOrWhiteSpace(ifMatch.ToString()))
        {
            return Results.Problem(
                statusCode: StatusCodes.Status428PreconditionRequired,
                title: "Falta la versión base del paquete",
                detail: "Recarga el paquete compatible antes de congelarlo.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "editorial.package.submit.precondition-required"
                });
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var snapshot =
                await new EducationalPackageSubmissionService(transactions)
                    .SubmitAsync(
                        actorId,
                        recordingId,
                        request,
                        ifMatch.ToString(),
                        httpContext.TraceIdentifier,
                        httpContext.RequestAborted);

            ApplySubmissionHeaders(httpContext, snapshot);
            return Results.Ok(snapshot);
        }
        catch (AntiforgeryValidationException)
        {
            return InvalidCsrf();
        }
        catch (EducationalPackageSubmissionException exception)
        {
            return SubmissionProblem(exception);
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
        CompatibleEducationalPackageException exception)
    {
        var status = exception.Code switch
        {
            "editorial.package.recording.not-found"
                => StatusCodes.Status404NotFound,
            "editorial.package.source-changed"
                => StatusCodes.Status412PreconditionFailed,
            "editorial.package.precondition-required"
                => StatusCodes.Status428PreconditionRequired,
            "editorial.package.multiple-drafts"
                => StatusCodes.Status409Conflict,
            "editorial.package.not-mutable"
                => StatusCodes.Status409Conflict,
            "editorial.package.source-incompatible"
                => StatusCodes.Status409Conflict,
            "editorial.package.exercise.invalid"
                => StatusCodes.Status409Conflict,
            "editorial.package.rights.required"
                => StatusCodes.Status409Conflict,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status switch
            {
                StatusCodes.Status404NotFound
                    => "Canción editorial no encontrada",
                StatusCodes.Status412PreconditionFailed
                    => "El paquete cambió",
                StatusCodes.Status428PreconditionRequired
                    => "Falta la versión base",
                StatusCodes.Status409Conflict
                    => "El paquete todavía no es compatible",
                _ => "Revisa la selección del paquete"
            },
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static IResult SubmissionProblem(
        EducationalPackageSubmissionException exception)
    {
        var status = exception.Code switch
        {
            "editorial.package.submit.recording-not-found"
                => StatusCodes.Status404NotFound,
            "editorial.package.submit.source-changed"
                => StatusCodes.Status412PreconditionFailed,
            "editorial.package.submit.precondition-required"
                => StatusCodes.Status428PreconditionRequired,
            "editorial.package.submit.draft-required"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.multiple-drafts"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.not-mutable"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.concurrent-change"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.components-incomplete"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.broken-link"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.component-terminal"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.component-changed"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.source-incompatible"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.exercise-provenance-required"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.rights-required"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.checksum-changed"
                => StatusCodes.Status409Conflict,
            "editorial.package.submit.permission-lost"
                => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status switch
            {
                StatusCodes.Status404NotFound
                    => "Canción editorial no encontrada",
                StatusCodes.Status403Forbidden
                    => "Ya no puedes someter este paquete",
                StatusCodes.Status412PreconditionFailed
                    => "El paquete cambió antes de congelarse",
                StatusCodes.Status428PreconditionRequired
                    => "Falta la versión base",
                StatusCodes.Status409Conflict
                    => "El paquete ya no está listo para someterse",
                _ => "Revisa el sometimiento"
            },
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static IResult InvalidCsrf() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud no válida",
            detail: "Actualiza la página y vuelve a intentarlo.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "editorial.package.csrf.invalid"
            });

    private static void ApplyHeaders(
        HttpContext context,
        CompatiblePackageSnapshot snapshot)
    {
        context.Response.Headers["ETag"] = snapshot.ETag;
        context.Response.Headers["Cache-Control"] = "no-store";
    }

    private static void ApplySubmissionHeaders(
        HttpContext context,
        EducationalPackageSubmissionSnapshot snapshot)
    {
        context.Response.Headers["ETag"] = snapshot.ETag;
        context.Response.Headers["Cache-Control"] = "no-store";
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

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Paquete editorial temporalmente no disponible",
            detail:
                "Las revisiones existentes permanecen intactas. "
                + "Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "editorial.package.unavailable"
            });

    private sealed record CompatiblePackageWorkspaceResponse(
        Guid RecordingId,
        long CatalogVersion,
        Guid? PackageId,
        int? PackageNo,
        string StatusCode,
        long Version,
        string? ChecksumSha256,
        string ETag,
        CompatiblePackageSelection Selection,
        IReadOnlyList<CompatiblePackageCandidate> Candidates,
        CompatiblePackageChecklist Checklist,
        string Message,
        EducationalPackageSubmissionSnapshot LatestSubmission)
    {
        public static CompatiblePackageWorkspaceResponse From(
            CompatiblePackageSnapshot snapshot,
            EducationalPackageSubmissionSnapshot latestSubmission) =>
            new(
                snapshot.RecordingId,
                snapshot.CatalogVersion,
                snapshot.PackageId,
                snapshot.PackageNo,
                snapshot.StatusCode,
                snapshot.Version,
                snapshot.ChecksumSha256,
                snapshot.ETag,
                snapshot.Selection,
                snapshot.Candidates,
                snapshot.Checklist,
                snapshot.Message,
                latestSubmission);
    }
}
