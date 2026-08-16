using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Learning.Infrastructure.Sessions;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Learning;

public static class StudyExerciseEndpoints
{
    private const string IdempotencyHeaderName = "Idempotency-Key";

    public static IEndpointRouteBuilder MapStudyExerciseFlow(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints
            .MapGroup("/api/v1/study")
            .RequireAuthorization()
            .WithTags("Learning");

        group.MapPost(
                "/sessions/{studySessionId:guid}/instances",
                PrepareFirstAsync)
            .Produces<FrozenExercisePreparedResponse>(StatusCodes.Status201Created)
            .Produces<FrozenExercisePreparedResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("PrepareFirstStudyExercise");

        group.MapGet(
                "/exercise-instances/{instanceId:guid}",
                ReadAsync)
            .Produces<FrozenExerciseResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("ReadFrozenStudyExercise");

        group.MapPost(
                "/exercise-instances/{instanceId:guid}/submissions",
                SubmitAsync)
            .Produces<AnswerSubmissionResponse>(StatusCodes.Status201Created)
            .Produces<AnswerSubmissionResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("SubmitStudyExerciseAnswer");

        return endpoints;
    }

    private static async Task<IResult> PrepareFirstAsync(
        Guid studySessionId,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudyExerciseFlowService service,
        CancellationToken cancellationToken)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var context = contextFactory.CreateRequired(httpContext);
            var result = await service.PrepareFirstAsync(
                context,
                studySessionId,
                cancellationToken);

            SetPrivateNoStore(httpContext);

            var response = new FrozenExercisePreparedResponse(
                result.InstanceId,
                result.ReusedExisting,
                result.ReusedExisting
                    ? "Reabrimos exactamente el ejercicio que ya habías recibido."
                    : "El primer ejercicio quedó congelado para esta sesión.");

            return Results.Json(
                response,
                statusCode: result.ReusedExisting
                    ? StatusCodes.Status200OK
                    : StatusCodes.Status201Created);
        }
        catch (AntiforgeryValidationException)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "La página necesita renovarse",
                "Actualiza la página antes de preparar el ejercicio.",
                "learning.exercise-instance.csrf.invalid");
        }
        catch (StudyExerciseSessionUnavailableException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "La sesión ya no está disponible",
                "Vuelve al inicio de práctica y abre una sesión vigente.",
                "learning.exercise-instance.session.unavailable");
        }
        catch (StudyExerciseNoEligibleExerciseException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "No hay un ejercicio publicado que podamos entregar",
                "No se creó una instancia vacía. Vuelve a la canción e inténtalo cuando exista una práctica compatible.",
                "learning.exercise-instance.activity.unavailable");
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Solicitud de ejercicio no válida",
                exception.Message,
                "learning.exercise-instance.request.invalid");
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

    private static async Task<IResult> ReadAsync(
        Guid instanceId,
        HttpContext httpContext,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudyExerciseFlowService service,
        CancellationToken cancellationToken)
    {
        try
        {
            var context = contextFactory.CreateRequired(httpContext);
            var exercise = await service.ReadAsync(
                context,
                instanceId,
                cancellationToken);

            SetPrivateNoStore(httpContext);
            return Results.Ok(ToResponse(exercise));
        }
        catch (StudyExerciseInstanceNotFoundException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "No encontramos este ejercicio privado",
                "Vuelve al inicio de práctica para recuperar una actividad de tu propia sesión.",
                "learning.exercise-instance.not-found");
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Instancia no válida",
                exception.Message,
                "learning.exercise-instance.request.invalid");
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

    private static async Task<IResult> SubmitAsync(
        Guid instanceId,
        StudyAnswerRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudyExerciseFlowService service,
        CancellationToken cancellationToken)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var idempotencyKey =
                httpContext.Request.Headers[IdempotencyHeaderName].ToString();

            if (string.IsNullOrWhiteSpace(idempotencyKey))
            {
                return Problem(
                    StatusCodes.Status400BadRequest,
                    "Falta confirmar la respuesta de forma segura",
                    "Actualiza la página e inténtalo de nuevo. No se guardó una segunda respuesta.",
                    "learning.answer-submission.idempotency.required");
            }

            var context = contextFactory.CreateRequired(httpContext);
            var result = await service.SubmitAsync(
                context,
                instanceId,
                request.SelectedInstanceItemId,
                idempotencyKey,
                cancellationToken);

            SetPrivateNoStore(httpContext);

            var response = new AnswerSubmissionResponse(
                result.SubmissionId,
                result.InstanceId,
                result.StatusCode,
                result.SubmittedAt,
                result.SelectedInstanceItemId,
                result.ReusedExisting,
                result.ReusedExisting
                    ? "Esta respuesta ya estaba confirmada. Conservamos la misma entrega."
                    : "Respuesta confirmada. La corrección se calculará en el siguiente paso.");

            return Results.Json(
                response,
                statusCode: result.ReusedExisting
                    ? StatusCodes.Status200OK
                    : StatusCodes.Status201Created);
        }
        catch (AntiforgeryValidationException)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "La página necesita renovarse",
                "Actualiza la página antes de volver a confirmar. La respuesta anterior, si existe, se conserva.",
                "learning.answer-submission.csrf.invalid");
        }
        catch (StudyExerciseInstanceNotFoundException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "La instancia no está disponible",
                "Vuelve a tu sesión y recupera un ejercicio válido.",
                "learning.answer-submission.instance.not-found");
        }
        catch (StudyExerciseSessionUnavailableException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "La sesión ya no acepta respuestas nuevas",
                "La respuesta no se confirmó. Vuelve al inicio de práctica para recuperar el último estado confirmado.",
                "learning.answer-submission.session.closed");
        }
        catch (StudyExerciseInvalidSelectionException)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Esa opción no pertenece a este ejercicio",
                "Elige una de las opciones visibles. El intento sigue abierto y no se reveló la solución.",
                "learning.answer-submission.selection.invalid");
        }
        catch (StudyExerciseIdempotencyConflictException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "La confirmación ya se usó para otra respuesta",
                "Recarga el ejercicio para recuperar el último estado confirmado antes de intentar otra acción.",
                "learning.answer-submission.idempotency.conflict");
        }
        catch (StudyExerciseAlreadySubmittedException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "Este ejercicio ya tiene una respuesta confirmada",
                "Recarga la pantalla para recuperar exactamente la entrega guardada. No se creó una segunda respuesta.",
                "learning.answer-submission.already-confirmed");
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Respuesta no válida",
                exception.Message,
                "learning.answer-submission.request.invalid");
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

    private static FrozenExerciseResponse ToResponse(
        FrozenExerciseView exercise) =>
        new(
            exercise.InstanceId,
            exercise.StudySessionId,
            exercise.StateCode,
            exercise.InstanceNo,
            exercise.DeliveredAt,
            exercise.Version,
            exercise.ExerciseRevisionNo,
            exercise.Prompt,
            exercise.LineNo,
            exercise.MaskedJapaneseText,
            exercise.Options
                .Select(option =>
                    new FrozenExerciseOptionResponse(
                        option.InstanceItemId,
                        option.DisplayOrder,
                        option.Value))
                .ToArray(),
            exercise.Submission is null
                ? null
                : new FrozenExerciseSubmissionResponse(
                    exercise.Submission.SubmissionId,
                    exercise.Submission.StatusCode,
                    exercise.Submission.SubmittedAt,
                    exercise.Submission.SelectedInstanceItemId));

    private static void SetPrivateNoStore(HttpContext httpContext)
    {
        httpContext.Response.Headers.CacheControl = "private, no-store";
    }

    private static IResult StorageUnavailable() =>
        Problem(
            StatusCodes.Status503ServiceUnavailable,
            "No pudimos confirmar el estado del ejercicio",
            "No se inventó ni sustituyó ningún dato. Puedes volver a intentarlo cuando el servicio esté disponible.",
            "learning.study-exercise.unavailable");

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

public sealed record FrozenExercisePreparedResponse(
    Guid InstanceId,
    bool ReusedExisting,
    string Message);

public sealed record FrozenExerciseOptionResponse(
    Guid InstanceItemId,
    int DisplayOrder,
    string Value);

public sealed record FrozenExerciseSubmissionResponse(
    Guid SubmissionId,
    string StatusCode,
    DateTimeOffset SubmittedAt,
    Guid SelectedInstanceItemId);

public sealed record FrozenExerciseResponse(
    Guid InstanceId,
    Guid StudySessionId,
    string StateCode,
    int InstanceNo,
    DateTimeOffset DeliveredAt,
    long Version,
    int ExerciseRevisionNo,
    string Prompt,
    int LineNo,
    string MaskedJapaneseText,
    IReadOnlyList<FrozenExerciseOptionResponse> Options,
    FrozenExerciseSubmissionResponse? Submission);

public sealed record StudyAnswerRequest(
    Guid SelectedInstanceItemId);

public sealed record AnswerSubmissionResponse(
    Guid SubmissionId,
    Guid InstanceId,
    string StatusCode,
    DateTimeOffset SubmittedAt,
    Guid SelectedInstanceItemId,
    bool ReusedExisting,
    string Message);
