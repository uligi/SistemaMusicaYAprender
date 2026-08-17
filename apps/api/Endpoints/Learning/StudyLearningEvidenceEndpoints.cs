using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Learning.Infrastructure.Sessions;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Learning;

public static class StudyLearningEvidenceEndpoints
{
    public static IEndpointRouteBuilder MapStudyLearningEvidence(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints
            .MapGroup("/api/v1/study")
            .RequireAuthorization()
            .WithTags("Learning");

        group.MapGet(
                "/exercise-instances/{instanceId:guid}/evidence",
                ReadAsync)
            .Produces<StudyLearningEvidenceResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("ReadStudyLearningEvidence");

        group.MapPost(
                "/exercise-instances/{instanceId:guid}/evidence",
                EnsureAsync)
            .Produces<StudyLearningEvidenceResponse>(StatusCodes.Status201Created)
            .Produces<StudyLearningEvidenceResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("EnsureStudyLearningEvidence");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid instanceId,
        HttpContext httpContext,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudyLearningEvidenceService service,
        CancellationToken cancellationToken)
    {
        SetPrivateNoStore(httpContext);

        try
        {
            var context = contextFactory.CreateRequired(httpContext);
            var result = await service.ReadAsync(context, instanceId, cancellationToken);
            return Results.Ok(ToResponse(result));
        }
        catch (StudyLearningEvidencePendingException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "La evidencia todavía está pendiente",
                "Primero debe existir una evaluación válida. Si ya existe, puedes reintentar la confirmación sin crear duplicados.",
                "learning.study-evidence.pending");
        }
        catch (StudyLearningEvidenceDriftException)
        {
            return ReviewableConflict();
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Instancia no válida",
                exception.Message,
                "learning.study-evidence.request.invalid");
        }
        catch (NpgsqlException)
        {
            return StorageUnavailable();
        }
        catch (InvalidOperationException)
        {
            return StorageUnavailable();
        }
    }

    private static async Task<IResult> EnsureAsync(
        Guid instanceId,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudyLearningEvidenceService service,
        CancellationToken cancellationToken)
    {
        SetPrivateNoStore(httpContext);

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            var context = contextFactory.CreateRequired(httpContext);
            var result = await service.EnsureAsync(context, instanceId, cancellationToken);

            return Results.Json(
                ToResponse(result),
                statusCode: result.ReusedExisting
                    ? StatusCodes.Status200OK
                    : StatusCodes.Status201Created);
        }
        catch (AntiforgeryValidationException)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "La página necesita renovarse",
                "Actualiza la página antes de confirmar la evidencia. La evaluación existente no se pierde.",
                "learning.study-evidence.csrf.invalid");
        }
        catch (StudyLearningEvidencePendingException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "La evaluación todavía no permite confirmar evidencia",
                "No se creó evidencia ni notificación de progreso. Recupera una evaluación válida y vuelve a intentarlo.",
                "learning.study-evidence.evaluation.pending");
        }
        catch (StudyExerciseSessionUnavailableException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "La sesión no acepta evidencia nueva",
                "Continúa una sesión pausada antes de confirmar evidencia. Una sesión finalizada solo permite recuperar evidencia ya existente.",
                "learning.study-evidence.session.inactive");
        }
        catch (StudyLearningEvidenceDriftException)
        {
            return ReviewableConflict();
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Solicitud de evidencia no válida",
                exception.Message,
                "learning.study-evidence.request.invalid");
        }
        catch (NpgsqlException)
        {
            return StorageUnavailable();
        }
        catch (InvalidOperationException)
        {
            return StorageUnavailable();
        }
    }

    internal static StudyLearningEvidenceResponse ToResponse(StudyLearningEvidenceView result) =>
        new(
            result.EvidenceId,
            result.EvaluationId,
            result.CompetencyId,
            result.RecordingId,
            result.Outcome,
            result.EvidenceVersion,
            result.ConfirmedAt,
            result.ReusedExisting);

    private static IResult ReviewableConflict() =>
        Problem(
            StatusCodes.Status409Conflict,
            "La evidencia confirmada requiere revisión",
            "No se reescribió el historial. El linaje o la notificación existente no coincide con la evaluación y debe corregirse de forma trazable.",
            "learning.study-evidence.drift");

    private static IResult StorageUnavailable() =>
        Problem(
            StatusCodes.Status503ServiceUnavailable,
            "No pudimos confirmar la evidencia",
            "La evaluación se conserva. Un reintento reutiliza la misma evidencia lógica y su única notificación; este paso todavía no actualiza progreso.",
            "learning.study-evidence.unavailable");

    private static void SetPrivateNoStore(HttpContext httpContext)
    {
        httpContext.Response.Headers.CacheControl = "private, no-store";
    }

    private static IResult Problem(
        int status,
        string title,
        string detail,
        string code) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: detail,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = code
            });
}

public sealed record StudyLearningEvidenceResponse(
    Guid EvidenceId,
    Guid EvaluationId,
    Guid CompetencyId,
    Guid RecordingId,
    decimal Outcome,
    int EvidenceVersion,
    DateTimeOffset ConfirmedAt,
    bool ReusedExisting);
