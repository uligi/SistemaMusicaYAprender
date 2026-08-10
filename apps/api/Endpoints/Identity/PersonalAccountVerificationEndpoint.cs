using Microsoft.AspNetCore.Mvc;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Identity;

public static partial class PersonalAccountVerificationEndpoint
{
    private const string IdempotencyHeader = "Idempotency-Key";

    public static IEndpointRouteBuilder MapPersonalAccountVerification(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/v1/auth/verify-account",
                VerifyAsync)
            .AllowAnonymous()
            .Accepts<PersonalAccountVerificationRequest>("application/json")
            .Produces<PersonalAccountVerificationResponse>(StatusCodes.Status200OK)
            .ProducesValidationProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("VerifyPersonalAccount")
            .WithTags("Identity");

        endpoints.MapPost(
                "/api/v1/auth/verification/resend",
                ResendAsync)
            .AllowAnonymous()
            .Accepts<PersonalAccountVerificationResendRequest>("application/json")
            .Produces<PersonalAccountVerificationResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("ResendPersonalAccountVerification")
            .WithTags("Identity");

        return endpoints;
    }

    private static async Task<IResult> VerifyAsync(
        [FromBody] PersonalAccountVerificationRequest request,
        HttpContext httpContext,
        PersonalAccountVerificationService service,
        ILogger<PersonalAccountVerificationService> logger,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await service.VerifyAsync(
                request.Token,
                httpContext.TraceIdentifier,
                cancellationToken);

            return result.Kind switch
            {
                PersonalAccountVerificationResultKind.Verified
                    when result.Response is not null => Results.Ok(result.Response),
                PersonalAccountVerificationResultKind.PrerequisitesNotCurrent =>
                    Results.Problem(
                        statusCode: StatusCodes.Status409Conflict,
                        title: "La cuenta no puede activarse todavía",
                        detail: "Las condiciones obligatorias ya no están vigentes. Inicia nuevamente el registro.",
                        extensions: new Dictionary<string, object?>
                        {
                            ["code"] = "identity.verification.prerequisites-not-current"
                        }),
                _ => InvalidTokenProblem()
            };
        }
        catch (NpgsqlException exception)
        {
            LogVerificationUnavailable(logger, httpContext.TraceIdentifier, exception);
            return UnavailableProblem();
        }
    }

    private static async Task<IResult> ResendAsync(
        [FromBody] PersonalAccountVerificationResendRequest request,
        HttpContext httpContext,
        PersonalAccountVerificationService service,
        ILogger<PersonalAccountVerificationService> logger,
        CancellationToken cancellationToken)
    {
        var idempotencyKey = httpContext.Request.Headers[IdempotencyHeader].ToString();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
        {
            return ValidationProblem(
                "idempotencyKey",
                "La solicitud requiere una clave de idempotencia.");
        }

        try
        {
            var result = await service.ResendAsync(
                request.Email,
                idempotencyKey,
                httpContext.TraceIdentifier,
                cancellationToken);

            return result.Kind switch
            {
                PersonalAccountVerificationResendResultKind.InvalidEmail =>
                    ValidationProblem(
                        "email",
                        "Escribe una dirección de correo válida de hasta 254 caracteres."),
                PersonalAccountVerificationResendResultKind.Accepted
                    when result.Response is not null =>
                    Results.Json(
                        result.Response,
                        statusCode: StatusCodes.Status202Accepted),
                _ => throw new InvalidOperationException(
                    "El reenvio no contiene un estado reconocido.")
            };
        }
        catch (ArgumentException exception)
            when (exception.ParamName is "idempotencyKey")
        {
            return ValidationProblem(
                "idempotencyKey",
                "La clave de idempotencia no cumple el formato admitido.");
        }
        catch (IdempotencyConflictException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "La clave ya representa otra solicitud",
                detail: "Genera una nueva clave de idempotencia para datos diferentes.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "identity.verification-resend.idempotency-conflict"
                });
        }
        catch (NpgsqlException exception)
        {
            LogResendUnavailable(logger, httpContext.TraceIdentifier, exception);
            return UnavailableProblem();
        }
    }

    private static IResult InvalidTokenProblem() =>
        Results.ValidationProblem(
            new Dictionary<string, string[]>
            {
                ["token"] =
                ["El código no es válido o ya venció. Solicita uno nuevo."]
            },
            title: "No pudimos verificar la cuenta",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "identity.verification.invalid"
            });

    private static IResult ValidationProblem(string field, string message) =>
        Results.ValidationProblem(
            new Dictionary<string, string[]>
            {
                [field] = [message]
            },
            title: "Revisa los datos",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "identity.verification.invalid-request"
            });

    private static IResult UnavailableProblem() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Verificación temporalmente no disponible",
            detail: "La solicitud puede reintentarse de forma segura.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "identity.verification.unavailable"
            });

    [LoggerMessage(
        EventId = 2501,
        Level = LogLevel.Warning,
        Message = "Verificacion de cuenta no disponible. CorrelationId={CorrelationId}.")]
    private static partial void LogVerificationUnavailable(
        ILogger logger,
        string correlationId,
        Exception exception);

    [LoggerMessage(
        EventId = 2502,
        Level = LogLevel.Warning,
        Message = "Reenvio de verificacion no disponible. CorrelationId={CorrelationId}.")]
    private static partial void LogResendUnavailable(
        ILogger logger,
        string correlationId,
        Exception exception);
}
