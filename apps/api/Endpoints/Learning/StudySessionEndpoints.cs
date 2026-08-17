using System.Globalization;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Catalog.Infrastructure.Search;
using MusicaAprender.Modules.Learning.Infrastructure.Sessions;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Learning;

public static class StudySessionEndpoints
{
    private const string IdempotencyHeaderName = "Idempotency-Key";

    public static IEndpointRouteBuilder MapStudySessions(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints
            .MapGroup("/api/v1/study/songs/{slug}")
            .RequireAuthorization()
            .WithTags("Learning");

        group.MapGet(
                "/session-start",
                ReadStartContextAsync)
            .Produces<StudySessionStartContextResponse>(
                StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("ReadStudySessionStartContext");

        group.MapPost(
                "/sessions",
                StartAsync)
            .Produces<StudySessionStartResponse>(
                StatusCodes.Status201Created)
            .Produces<StudySessionStartResponse>(
                StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("StartStudySession");

        var lifecycle = endpoints
            .MapGroup("/api/v1/study/sessions")
            .RequireAuthorization()
            .WithTags("Learning");

        lifecycle.MapGet(
                "/{studySessionId:guid}",
                ReadLifecycleAsync)
            .Produces<StudySessionLifecycleResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("ReadStudySessionLifecycle");

        lifecycle.MapPost(
                "/{studySessionId:guid}/pause",
                PauseLifecycleAsync)
            .Produces<StudySessionLifecycleResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("PauseStudySession");

        lifecycle.MapPost(
                "/{studySessionId:guid}/resume",
                ResumeLifecycleAsync)
            .Produces<StudySessionLifecycleResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("ResumeStudySession");

        lifecycle.MapPost(
                "/{studySessionId:guid}/complete",
                CompleteLifecycleAsync)
            .Produces<StudySessionLifecycleResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("CompleteStudySession");

        return endpoints;
    }

    private static async Task<IResult> ReadStartContextAsync(
        string slug,
        string? territory,
        string? language,
        HttpContext httpContext,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudySessionStartService service,
        CancellationToken cancellationToken)
    {
        try
        {
            var context = contextFactory.CreateRequired(httpContext);
            var slugKey = PublicSongSlug.ExtractKey(slug);

            var startContext =
                await service.ReadStartContextAsync(
                    context,
                    slugKey,
                    territory ?? "CR",
                    language ?? "es",
                    cancellationToken);

            SetPrivateNoStore(httpContext);

            return Results.Ok(
                new StudySessionStartContextResponse(
                    startContext.Eligible,
                    startContext.BlockingReason,
                    startContext.EligibleExerciseCount,
                    startContext.PublicationNo,
                    startContext.ActiveSession is null
                        ? null
                        : ToSummary(startContext.ActiveSession)));
        }
        catch (StudySessionPublicationAmbiguousException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "No se puede elegir una publicación con seguridad",
                "Hay más de una publicación elegible. No se iniciará una sesión hasta resolver la ambigüedad.",
                "learning.study-session.publication.ambiguous");
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Ruta de práctica no válida",
                exception.Message,
                "learning.study-session.route.invalid");
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

    private static async Task<IResult> StartAsync(
        string slug,
        string? territory,
        string? language,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudySessionStartService service,
        CancellationToken cancellationToken)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var idempotencyKey =
                httpContext.Request.Headers[IdempotencyHeaderName]
                    .ToString();

            if (string.IsNullOrWhiteSpace(idempotencyKey))
            {
                return Problem(
                    StatusCodes.Status400BadRequest,
                    "Falta confirmar la operación de forma segura",
                    "Actualiza la página e inténtalo de nuevo. No se creó ninguna sesión.",
                    "learning.study-session.idempotency.required");
            }

            var context = contextFactory.CreateRequired(httpContext);
            var slugKey = PublicSongSlug.ExtractKey(slug);

            var result =
                await service.StartAsync(
                    context,
                    slugKey,
                    territory ?? "CR",
                    language ?? "es",
                    idempotencyKey,
                    cancellationToken);

            SetPrivateNoStore(httpContext);

            var response = new StudySessionStartResponse(
                result.StudySessionId,
                result.StatusCode,
                result.StartedAt,
                result.Version,
                result.PublicationNo,
                result.ReusedExisting,
                result.ReusedExisting
                    ? "Ya había una sesión en curso. Conservamos la misma sesión privada."
                    : "Tu sesión privada está lista.");

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
                "Actualiza la página antes de volver a iniciar la práctica. No se creó ninguna sesión.",
                "learning.study-session.csrf.invalid");
        }
        catch (StudySessionPublicationUnavailableException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "La canción ya no está disponible para estudiar",
                "Vuelve a la canción publicada y comprueba su disponibilidad antes de intentarlo otra vez.",
                "learning.study-session.publication.unavailable");
        }
        catch (StudySessionNoEligibleActivityException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "Todavía no hay una práctica publicada",
                "No se creó una sesión vacía ni se registró progreso. Los borradores editoriales no cuentan como actividad publicada.",
                "learning.study-session.activity.unavailable");
        }
        catch (StudySessionPublicationAmbiguousException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "No se puede elegir una publicación con seguridad",
                "No se creó ninguna sesión. La publicación debe resolverse de forma unívoca.",
                "learning.study-session.publication.ambiguous");
        }
        catch (StudySessionIdempotencyConflictException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "La confirmación ya se usó para otra solicitud",
                "Recarga la pantalla antes de volver a iniciar una sesión diferente.",
                "learning.study-session.idempotency.conflict");
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Solicitud de práctica no válida",
                exception.Message,
                "learning.study-session.request.invalid");
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


    private static async Task<IResult> ReadLifecycleAsync(
        Guid studySessionId,
        HttpContext httpContext,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudySessionLifecycleService service,
        CancellationToken cancellationToken)
    {
        SetPrivateNoStore(httpContext);

        try
        {
            var context = contextFactory.CreateRequired(httpContext);
            var result = await service.ReadAsync(
                context,
                studySessionId,
                cancellationToken);

            return Results.Ok(ToLifecycleResponse(result));
        }
        catch (StudySessionLifecycleNotFoundException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "No encontramos esta sesión privada",
                "Vuelve al inicio de estudio para recuperar una sesión de tu propia cuenta.",
                "learning.study-session.lifecycle.not-found");
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Sesión de estudio no válida",
                exception.Message,
                "learning.study-session.lifecycle.request.invalid");
        }
        catch (NpgsqlException)
        {
            return LifecycleStorageUnavailable();
        }
        catch (InvalidOperationException)
        {
            return LifecycleStorageUnavailable();
        }
    }

    private static Task<IResult> PauseLifecycleAsync(
        Guid studySessionId,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudySessionLifecycleService service,
        CancellationToken cancellationToken) =>
        MutateLifecycleAsync(
            studySessionId,
            "pause",
            httpContext,
            antiforgery,
            contextFactory,
            service,
            cancellationToken);

    private static Task<IResult> ResumeLifecycleAsync(
        Guid studySessionId,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudySessionLifecycleService service,
        CancellationToken cancellationToken) =>
        MutateLifecycleAsync(
            studySessionId,
            "resume",
            httpContext,
            antiforgery,
            contextFactory,
            service,
            cancellationToken);

    private static Task<IResult> CompleteLifecycleAsync(
        Guid studySessionId,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudySessionLifecycleService service,
        CancellationToken cancellationToken) =>
        MutateLifecycleAsync(
            studySessionId,
            "complete",
            httpContext,
            antiforgery,
            contextFactory,
            service,
            cancellationToken);

    private static async Task<IResult> MutateLifecycleAsync(
        Guid studySessionId,
        string action,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        StudySessionLifecycleService service,
        CancellationToken cancellationToken)
    {
        SetPrivateNoStore(httpContext);

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            if (!TryReadExpectedVersion(
                    httpContext,
                    out var expectedVersion,
                    out var missingIfMatch))
            {
                return missingIfMatch
                    ? Problem(
                        StatusCodes.Status428PreconditionRequired,
                        "Falta la versión observada de la sesión",
                        "Recarga la sesión antes de cambiar su estado. No se aplicó ninguna transición.",
                        "learning.study-session.lifecycle.if-match.required")
                    : Problem(
                        StatusCodes.Status400BadRequest,
                        "La versión de sesión no es válida",
                        "If-Match debe contener una única versión positiva, por ejemplo \"3\".",
                        "learning.study-session.lifecycle.if-match.invalid");
            }

            var context = contextFactory.CreateRequired(httpContext);
            var result = action switch
            {
                "pause" => await service.PauseAsync(
                    context,
                    studySessionId,
                    expectedVersion,
                    cancellationToken),
                "resume" => await service.ResumeAsync(
                    context,
                    studySessionId,
                    expectedVersion,
                    cancellationToken),
                "complete" => await service.CompleteAsync(
                    context,
                    studySessionId,
                    expectedVersion,
                    cancellationToken),
                _ => throw new ArgumentOutOfRangeException(
                    nameof(action),
                    action,
                    "Acción de ciclo de vida no soportada.")
            };

            return Results.Ok(ToLifecycleResponse(result));
        }
        catch (AntiforgeryValidationException)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "La página necesita renovarse",
                "Actualiza la página antes de cambiar el estado de la sesión.",
                "learning.study-session.lifecycle.csrf.invalid");
        }
        catch (StudySessionLifecycleNotFoundException)
        {
            return Problem(
                StatusCodes.Status404NotFound,
                "No encontramos esta sesión privada",
                "Vuelve al inicio de estudio para recuperar una sesión de tu propia cuenta.",
                "learning.study-session.lifecycle.not-found");
        }
        catch (StudySessionLifecycleVersionConflictException)
        {
            return Problem(
                StatusCodes.Status412PreconditionFailed,
                "La sesión cambió en otra operación",
                "Recarga el estado autoritativo antes de volver a pausar, continuar o finalizar.",
                "learning.study-session.lifecycle.version-conflict");
        }
        catch (StudySessionLifecycleTransitionConflictException)
        {
            return Problem(
                StatusCodes.Status409Conflict,
                "La sesión ya no permite esa transición",
                "Recarga la sesión para continuar desde su estado autoritativo actual.",
                "learning.study-session.lifecycle.transition-conflict");
        }
        catch (ArgumentException exception)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                "Cambio de sesión no válido",
                exception.Message,
                "learning.study-session.lifecycle.request.invalid");
        }
        catch (NpgsqlException)
        {
            return LifecycleStorageUnavailable();
        }
        catch (InvalidOperationException)
        {
            return LifecycleStorageUnavailable();
        }
    }

    private static bool TryReadExpectedVersion(
        HttpContext httpContext,
        out long expectedVersion,
        out bool missing)
    {
        expectedVersion = 0;
        var raw = httpContext.Request.Headers["If-Match"].ToString().Trim();
        missing = string.IsNullOrWhiteSpace(raw);

        if (missing
            || string.Equals(raw, "*", StringComparison.Ordinal)
            || raw.Contains(',')
            || raw.StartsWith("W/", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (raw.Length >= 2 && raw[0] == '"' && raw[^1] == '"')
        {
            raw = raw[1..^1];
        }

        return long.TryParse(
                   raw,
                   NumberStyles.None,
                   CultureInfo.InvariantCulture,
                   out expectedVersion)
               && expectedVersion > 0;
    }

    private static StudySessionLifecycleResponse ToLifecycleResponse(
        StudySessionLifecycleView result) =>
        new(
            result.StudySessionId,
            result.StatusCode,
            result.StartedAt,
            result.EndedAt,
            result.Version,
            result.ReusedExisting,
            result.StatusCode switch
            {
                "ACTIVE" => "Tu sesión está activa y puede aceptar nuevas acciones educativas.",
                "PAUSED" => "Tu sesión quedó pausada. Continuar recuperará la misma sesión e instancia.",
                "COMPLETED" => "Sesión finalizada. Los hechos ya confirmados se conservan sin crear progreso adicional.",
                _ => "Estado de sesión recuperado."
            });

    private static IResult LifecycleStorageUnavailable() =>
        Problem(
            StatusCodes.Status503ServiceUnavailable,
            "No pudimos confirmar el estado de la sesión",
            "No se inventó ninguna transición. Recarga antes de volver a intentarlo.",
            "learning.study-session.lifecycle.unavailable");

    private static StudySessionSummaryResponse ToSummary(
        StudySessionSummary session) =>
        new(
            session.StudySessionId,
            session.StatusCode,
            session.StartedAt,
            session.Version);

    private static void SetPrivateNoStore(
        HttpContext httpContext)
    {
        httpContext.Response.Headers.CacheControl =
            "private, no-store";
    }

    private static IResult StorageUnavailable() =>
        Problem(
            StatusCodes.Status503ServiceUnavailable,
            "No pudimos preparar tu sesión",
            "No se confirmó ninguna sesión nueva. Puedes volver a intentarlo cuando el servicio esté disponible.",
            "learning.study-session.unavailable");

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

public sealed record StudySessionSummaryResponse(
    Guid StudySessionId,
    string StatusCode,
    DateTimeOffset StartedAt,
    long Version);

public sealed record StudySessionStartContextResponse(
    bool Eligible,
    string? BlockingReason,
    int EligibleExerciseCount,
    int? PublicationNo,
    StudySessionSummaryResponse? ActiveSession);

public sealed record StudySessionStartResponse(
    Guid StudySessionId,
    string StatusCode,
    DateTimeOffset StartedAt,
    long Version,
    int PublicationNo,
    bool ReusedExisting,
    string Message);

public sealed record StudySessionLifecycleResponse(
    Guid StudySessionId,
    string StatusCode,
    DateTimeOffset StartedAt,
    DateTimeOffset? EndedAt,
    long Version,
    bool ReusedExisting,
    string Message);
