using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Learning.Infrastructure.Sessions;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Learning;

public static class StudyExerciseEvaluationEndpoints
{
    public static IEndpointRouteBuilder MapStudyExerciseEvaluation(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints
            .MapGroup("/api/v1/study")
            .RequireAuthorization()
            .WithTags("Learning");

        group.MapGet(
                "/exercise-instances/{instanceId:guid}/evaluation",
                ReadAsync)
            .Produces<StudyEvaluationResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("ReadStudyExerciseEvaluation");

        group.MapPost(
                "/exercise-instances/{instanceId:guid}/evaluation",
                EnsureAsync)
            .Produces<StudyEvaluationResponse>(StatusCodes.Status201Created)
            .Produces<StudyEvaluationResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("EnsureStudyExerciseEvaluation");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid instanceId,
        HttpContext httpContext,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudyExerciseEvaluationService service,
        StudyLearningEvidenceService evidenceService,
        CancellationToken cancellationToken)
    {
        try
        {
            var context = contextFactory.CreateRequired(httpContext);
            var result = await service.ReadAsync(context, instanceId, cancellationToken);
            StudyLearningEvidenceView? evidence = null;

            try
            {
                evidence = await evidenceService.ReadAsync(context, instanceId, cancellationToken);
            }
            catch (StudyLearningEvidencePendingException)
            {
                // Una evaluación histórica puede existir antes de que BL077 confirme su evidencia.
            }
            catch (StudyLearningEvidenceDriftException)
            {
                return EvidenceReviewableConflict();
            }

            SetPrivateNoStore(httpContext);
            return Results.Ok(ToResponse(result, evidence));
        }
        catch (StudyExerciseEvaluationPendingException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "La corrección todavía está pendiente",
                "La respuesta confirmada se conserva. Puedes iniciar la evaluación reproducible cuando estés listo.",
                "learning.study-evaluation.pending");
        }
        catch (StudyExerciseEvaluationDriftException)
        {
            return ReviewableConflict();
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Instancia no válida",
                exception.Message,
                "learning.study-evaluation.request.invalid");
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
        StudyExerciseEvaluationService service,
        StudyLearningEvidenceService evidenceService,
        CancellationToken cancellationToken)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var context = contextFactory.CreateRequired(httpContext);
            var result = await service.EnsureAsync(context, instanceId, cancellationToken);
            StudyLearningEvidenceView evidence;

            try
            {
                evidence = await evidenceService.EnsureAsync(context, instanceId, cancellationToken);
            }
            catch (StudyLearningEvidencePendingException)
            {
                return EvidencePendingConflict();
            }
            catch (StudyLearningEvidenceDriftException)
            {
                return EvidenceReviewableConflict();
            }

            SetPrivateNoStore(httpContext);
            return Results.Json(
                ToResponse(result, evidence),
                statusCode: result.ReusedExisting
                    ? StatusCodes.Status200OK
                    : StatusCodes.Status201Created);
        }
        catch (AntiforgeryValidationException)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "La página necesita renovarse",
                "Actualiza la página antes de evaluar. La respuesta confirmada no se pierde.",
                "learning.study-evaluation.csrf.invalid");
        }
        catch (StudyExerciseEvaluationInstanceNotFoundException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "No hay una respuesta evaluable disponible",
                "Vuelve a tu sesión y recupera una respuesta confirmada de tu propia cuenta.",
                "learning.study-evaluation.instance.not-found");
        }
        catch (StudyExerciseEvaluationRuleUnavailableException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "La regla congelada necesita revisión",
                "No se confirmó una evaluación definitiva. La respuesta se conserva para que una revisión editorial pueda corregir la fuente sin crear evidencia ni progreso.",
                "learning.study-evaluation.rule.unavailable");
        }
        catch (StudyExerciseSessionUnavailableException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "La sesión no acepta una evaluación nueva",
                "Continúa una sesión pausada antes de crear una evaluación. Una sesión finalizada solo permite recuperar hechos ya confirmados.",
                "learning.study-evaluation.session.inactive");
        }
        catch (StudyExerciseEvaluationDriftException)
        {
            return ReviewableConflict();
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Solicitud de evaluación no válida",
                exception.Message,
                "learning.study-evaluation.request.invalid");
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

    private static StudyEvaluationResponse ToResponse(
        StudyEvaluationView result,
        StudyLearningEvidenceView? evidence) =>
        new(
            result.EvaluationId,
            result.SubmissionId,
            result.EvaluatorVersion,
            result.Score,
            result.Correct,
            result.EvaluatedAt,
            result.ResultDigestSha256,
            result.ReusedExisting,
            result.Feedback
                .Select(item =>
                    new StudyEvaluationFeedbackResponse(
                        item.FeedbackCode,
                        item.LanguageTag,
                        item.Message,
                        item.DisplayOrder))
                .ToArray(),
            evidence is null
                ? null
                : StudyLearningEvidenceEndpoints.ToResponse(evidence));

    private static IResult ReviewableConflict() =>
        Problem(
            StatusCodes.Status409Conflict,
            "La corrección confirmada requiere revisión",
            "No se sobrescribió el resultado histórico. Conservamos la respuesta y la evaluación existente para una corrección trazable posterior.",
            "learning.study-evaluation.drift");

    private static IResult EvidencePendingConflict() =>
        Problem(
            StatusCodes.Status409Conflict,
            "La evaluación quedó guardada y la evidencia sigue pendiente",
            "Reintenta la operación. La evaluación persistida se reutiliza y BL077 confirmará como máximo una evidencia lógica.",
            "learning.study-evidence.pending-after-evaluation");

    private static IResult EvidenceReviewableConflict() =>
        Problem(
            StatusCodes.Status409Conflict,
            "La evidencia asociada requiere revisión",
            "La evaluación no se reescribió. El linaje o la notificación de evidencia existente no coincide y debe revisarse de forma trazable.",
            "learning.study-evidence.drift");

    private static IResult StorageUnavailable() =>
        Problem(
            StatusCodes.Status503ServiceUnavailable,
            "No pudimos completar la corrección y su evidencia",
            "La respuesta confirmada se conserva. Si la evaluación o evidencia ya se persistieron, el reintento reutiliza esos registros; este paso todavía no actualiza progreso.",
            "learning.study-evaluation.unavailable");

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

public sealed record StudyEvaluationFeedbackResponse(
    string FeedbackCode,
    string LanguageTag,
    string Message,
    int DisplayOrder);

public sealed record StudyEvaluationResponse(
    Guid EvaluationId,
    Guid SubmissionId,
    string EvaluatorVersion,
    decimal Score,
    bool Correct,
    DateTimeOffset EvaluatedAt,
    string ResultDigestSha256,
    bool ReusedExisting,
    IReadOnlyList<StudyEvaluationFeedbackResponse> Feedback,
    StudyLearningEvidenceResponse? Evidence);
