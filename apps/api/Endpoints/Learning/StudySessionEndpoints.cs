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
