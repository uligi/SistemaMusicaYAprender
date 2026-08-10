using Microsoft.AspNetCore.Mvc;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Identity;

public static partial class PersonalAccountRegistrationEndpoint
{
    private const string IdempotencyHeader = "Idempotency-Key";

    public static IEndpointRouteBuilder MapPersonalAccountRegistration(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/v1/auth/register",
                HandleAsync)
            .AllowAnonymous()
            .Accepts<PersonalAccountRegistrationRequest>("application/json")
            .Produces<PersonalAccountRegistrationResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("RegisterPersonalAccount")
            .WithTags("Identity");

        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        [FromBody] PersonalAccountRegistrationRequest request,
        HttpContext httpContext,
        PersonalAccountRegistrationService registrationService,
        ILogger<PersonalAccountRegistrationService> logger,
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
            var response = await registrationService.RegisterAsync(
                request.Email,
                idempotencyKey,
                httpContext.TraceIdentifier,
                cancellationToken);

            return response is null
                ? ValidationProblem(
                    "email",
                    "Escribe una dirección de correo válida de hasta 254 caracteres.")
                : Results.Json(response, statusCode: StatusCodes.Status202Accepted);
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
                    ["code"] = "identity.registration.idempotency-conflict"
                });
        }
        catch (NpgsqlException exception)
        {
            LogRegistrationUnavailable(logger, httpContext.TraceIdentifier, exception);

            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Registro temporalmente no disponible",
                detail: "La solicitud puede reintentarse de forma segura con la misma clave.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "identity.registration.unavailable"
                });
        }
    }

    private static IResult ValidationProblem(string field, string message)
    {
        return Results.ValidationProblem(
            new Dictionary<string, string[]>
            {
                [field] = [message]
            },
            title: "Revisa los datos",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "identity.registration.invalid"
            });
    }

    [LoggerMessage(
        EventId = 2301,
        Level = LogLevel.Warning,
        Message = "Registro personal no disponible. CorrelationId={CorrelationId}.")]
    private static partial void LogRegistrationUnavailable(
        ILogger logger,
        string correlationId,
        Exception exception);
}
