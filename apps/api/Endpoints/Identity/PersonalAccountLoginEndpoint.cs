using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Security.Infrastructure.Authentication;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Identity;

public static partial class PersonalAccountLoginEndpoint
{
    public static IEndpointRouteBuilder MapPersonalAccountLogin(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/auth/csrf",
                GetAntiforgeryToken)
            .AllowAnonymous()
            .Produces<AntiforgeryTokenResponse>(StatusCodes.Status200OK)
            .WithName("GetLoginAntiforgeryToken")
            .WithTags("Identity");

        endpoints.MapPost(
                "/api/v1/auth/login",
                HandleAsync)
            .AllowAnonymous()
            .Accepts<PersonalAccountLoginRequest>("application/json")
            .Produces<PersonalAccountLoginResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("LoginPersonalAccount")
            .WithTags("Identity");

        endpoints.MapGet(
                "/api/v1/auth/session",
                GetCurrentSession)
            .RequireAuthorization()
            .Produces<PersonalSessionResponse>(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .WithName("GetPersonalSession")
            .WithTags("Identity");

        return endpoints;
    }

    private static IResult GetAntiforgeryToken(
        HttpContext httpContext,
        IAntiforgery antiforgery)
    {
        var tokens = antiforgery.GetAndStoreTokens(httpContext);
        httpContext.Response.Headers.CacheControl = "no-store";
        httpContext.Response.Headers.Pragma = "no-cache";

        return Results.Ok(new AntiforgeryTokenResponse(
            tokens.RequestToken
            ?? throw new InvalidOperationException(
                "No se pudo emitir el token antifalsificacion."),
            tokens.HeaderName
            ?? SessionAuthenticationDefaults.AntiforgeryHeaderName));
    }

    private static async Task<IResult> HandleAsync(
        [FromBody] PersonalAccountLoginRequest request,
        HttpContext httpContext,
        [FromServices] IAntiforgery antiforgery,
        PersonalAccountLoginService loginService,
        ILogger<PersonalAccountLoginService> logger,
        CancellationToken cancellationToken)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var result = await loginService.AuthenticateAsync(
                request.Email,
                request.Password,
                httpContext.TraceIdentifier,
                cancellationToken);

            if (!result.IsAuthenticated)
            {
                return LoginRejected();
            }

            var claims = new[]
            {
                new Claim(ClaimTypes.NameIdentifier, result.AccountId.ToString("D")),
                new Claim("sub", result.AccountId.ToString("D")),
                new Claim("account_id", result.AccountId.ToString("D")),
                new Claim(ClaimTypes.Role, SecuritySessionPolicy.SafeRoleCode),
                new Claim("role", SecuritySessionPolicy.SafeRoleCode),
                new Claim("active_role", SecuritySessionPolicy.SafeRoleCode)
            };
            var identity = new ClaimsIdentity(
                claims,
                SessionAuthenticationDefaults.Scheme,
                ClaimTypes.NameIdentifier,
                ClaimTypes.Role);
            var principal = new ClaimsPrincipal(identity);
            var issuedAt = DateTimeOffset.UtcNow;

            await httpContext.SignInAsync(
                SessionAuthenticationDefaults.Scheme,
                principal,
                new AuthenticationProperties
                {
                    AllowRefresh = false,
                    IsPersistent = true,
                    IssuedUtc = issuedAt,
                    ExpiresUtc = issuedAt + SecuritySessionPolicy.AbsoluteLifetime
                });

            httpContext.Response.Headers.CacheControl = "no-store";
            return Results.Ok(new PersonalAccountLoginResponse(
                "AUTHENTICATED",
                SecuritySessionPolicy.SafeRoleCode,
                "La sesión se inició de forma segura."));
        }
        catch (AntiforgeryValidationException)
        {
            return AntiforgeryRejected();
        }
        catch (NpgsqlException exception)
        {
            LogLoginUnavailable(logger, httpContext.TraceIdentifier, exception);

            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Acceso temporalmente no disponible",
                detail: "Conserva los datos y vuelve a intentarlo más tarde.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "identity.login.unavailable"
                });
        }
    }

    private static IResult GetCurrentSession(
        ClaimsPrincipal user,
        HttpContext httpContext)
    {
        httpContext.Response.Headers.CacheControl = "no-store";

        var role = user.FindFirstValue("active_role")
                   ?? SecuritySessionPolicy.SafeRoleCode;

        return Results.Ok(new PersonalSessionResponse(
            "AUTHENTICATED",
            role));
    }

    private static IResult LoginRejected() =>
        Results.Problem(
            statusCode: StatusCodes.Status401Unauthorized,
            title: "No se pudo iniciar sesión",
            detail: "Revisa el correo y la contraseña e inténtalo nuevamente.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "identity.login.failed"
            });

    private static IResult AntiforgeryRejected() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud no válida",
            detail: "Actualiza la página y vuelve a intentarlo.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "identity.login.csrf.invalid"
            });

    [LoggerMessage(
        EventId = 2601,
        Level = LogLevel.Warning,
        Message = "Personal account login is temporarily unavailable. CorrelationId={CorrelationId}")]
    private static partial void LogLoginUnavailable(
        ILogger logger,
        string correlationId,
        Exception exception);
}
