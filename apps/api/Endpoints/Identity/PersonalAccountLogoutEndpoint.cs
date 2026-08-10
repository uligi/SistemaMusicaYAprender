using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using MusicaAprender.Api.Security;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Identity;

public sealed record PersonalAccountLogoutResponse(
    string Status,
    string Message);

public static partial class PersonalAccountLogoutEndpoint
{
    public static IEndpointRouteBuilder MapPersonalAccountLogout(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost(
                "/api/v1/auth/logout",
                HandleAsync)
            .RequireAuthorization()
            .Produces<PersonalAccountLogoutResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("LogoutPersonalAccount")
            .WithTags("Identity");

        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        HttpContext httpContext,
        IAntiforgery antiforgery,
        ILoggerFactory loggerFactory)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            await httpContext.SignOutAsync(SessionAuthenticationDefaults.Scheme);

            httpContext.Response.Headers.CacheControl = "no-store";
            httpContext.Response.Headers.Pragma = "no-cache";

            return Results.Ok(new PersonalAccountLogoutResponse(
                "SIGNED_OUT",
                "La sesión actual se cerró de forma segura."));
        }
        catch (AntiforgeryValidationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Solicitud no válida",
                detail: "Actualiza la página y vuelve a intentarlo.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "identity.logout.csrf.invalid"
                });
        }
        catch (NpgsqlException exception)
        {
            var logger = loggerFactory.CreateLogger(
                "MusicaAprender.Api.Endpoints.Identity.PersonalAccountLogout");
            LogLogoutUnavailable(
                logger,
                httpContext.TraceIdentifier,
                exception);

            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Cierre de sesión temporalmente no disponible",
                detail: "Conserva la sesión abierta y vuelve a intentarlo más tarde.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "identity.logout.unavailable"
                });
        }
    }

    [LoggerMessage(
        EventId = 2701,
        Level = LogLevel.Warning,
        Message = "Personal account logout is temporarily unavailable. CorrelationId={CorrelationId}")]
    private static partial void LogLogoutUnavailable(
        ILogger logger,
        string correlationId,
        Exception exception);
}
