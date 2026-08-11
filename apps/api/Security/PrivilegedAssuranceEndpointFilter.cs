using System.Security.Claims;
using MusicaAprender.Modules.Security.Infrastructure.Mfa;
using Npgsql;

namespace MusicaAprender.Api.Security;

internal sealed class PrivilegedAssuranceEndpointFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var httpContext = context.HttpContext;
        var accountValue =
            httpContext.User.FindFirstValue("account_id");
        var sessionValue =
            httpContext.User.FindFirstValue("session_id");

        if (!Guid.TryParse(accountValue, out var accountId)
            || accountId == Guid.Empty
            || !Guid.TryParse(sessionValue, out var sessionId)
            || sessionId == Guid.Empty)
        {
            return Results.Unauthorized();
        }

        try
        {
            var service =
                httpContext.RequestServices
                    .GetRequiredService<PrivilegedMfaService>();

            var allowed =
                await service.HasRecentPrivilegedAssuranceAsync(
                    accountId,
                    sessionId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            var audit =
                httpContext.RequestServices
                    .GetRequiredService<PrimaryAuditRecorder>();

            await audit.RecordPrivilegedAssuranceDecisionAsync(
                accountId,
                sessionId,
                allowed,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            if (!allowed)
            {
                return StepUpRequired();
            }

            return await next(context);
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

    private static IResult StepUpRequired() =>
        Results.Problem(
            statusCode: StatusCodes.Status403Forbidden,
            title: "Verificación reforzada requerida",
            detail:
                "Esta acción privilegiada exige un segundo factor "
                + "confirmado recientemente.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.authentication.step-up-required"
            });

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Verificación temporalmente no disponible",
            detail:
                "La operación privilegiada se cerró de forma segura. "
                + "Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.authentication.assurance-unavailable"
            });
}

internal static class PrivilegedAssuranceRouteHandlerExtensions
{
    public static RouteHandlerBuilder RequireRecentPrivilegedAssurance(
        this RouteHandlerBuilder builder)
    {
        ArgumentNullException.ThrowIfNull(builder);

        builder.RequireAuthorization();
        builder.AddEndpointFilter(
            new PrivilegedAssuranceEndpointFilter());

        return builder;
    }
}
