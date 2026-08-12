using System.Security.Claims;
using MusicaAprender.Modules.Security.Infrastructure.Authorization;
using Npgsql;

namespace MusicaAprender.Api.Security;

internal sealed class AnyEffectivePermissionEndpointFilter(
    string[] permissionCodes,
    string auditCode,
    string? moduleCode = null,
    string? routeObjectKey = null) : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var httpContext = context.HttpContext;
        var accountValue =
            httpContext.User.FindFirstValue("account_id");

        if (!Guid.TryParse(accountValue, out var accountId)
            || accountId == Guid.Empty)
        {
            return Results.Unauthorized();
        }

        AuthorizationScope requiredScope;
        try
        {
            requiredScope = ResolveScope(httpContext);
        }
        catch (ArgumentException)
        {
            return AuthorizationDenied();
        }

        try
        {
            var authorization =
                httpContext.RequestServices
                    .GetRequiredService<EffectiveAuthorizationService>();

            AuthorizationDecision? granted = null;
            foreach (var permissionCode in permissionCodes)
            {
                var decision = await authorization.AuthorizeAsync(
                    accountId,
                    permissionCode,
                    requiredScope,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

                if (decision.Allowed)
                {
                    granted = decision;
                    break;
                }
            }

            var combined = granted
                ?? AuthorizationDecision.Deny("NO_VALID_GRANT");

            var audit =
                httpContext.RequestServices
                    .GetRequiredService<PrimaryAuditRecorder>();

            await audit.RecordAuthorizationDecisionAsync(
                accountId,
                auditCode,
                requiredScope,
                combined,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            if (!combined.Allowed)
            {
                return AuthorizationDenied();
            }

            return await next(context);
        }
        catch (NpgsqlException)
        {
            return AuthorizationUnavailable();
        }
        catch (InvalidOperationException)
        {
            return AuthorizationUnavailable();
        }
    }

    private AuthorizationScope ResolveScope(HttpContext httpContext)
    {
        if (routeObjectKey is not null)
        {
            if (moduleCode is null
                || !httpContext.Request.RouteValues.TryGetValue(
                    routeObjectKey,
                    out var rawObjectId)
                || !Guid.TryParse(
                    Convert.ToString(
                        rawObjectId,
                        System.Globalization.CultureInfo.InvariantCulture),
                    out var objectId)
                || objectId == Guid.Empty)
            {
                throw new ArgumentException(
                    "El objeto de autorización no es válido.");
            }

            return AuthorizationScope.ForObject(
                moduleCode,
                objectId);
        }

        return moduleCode is null
            ? AuthorizationScope.Global
            : AuthorizationScope.ForModule(moduleCode);
    }

    private static IResult AuthorizationUnavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Autorización temporalmente no disponible",
            detail:
                "La operación protegida se cerró de forma segura. "
                + "Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.authorization.unavailable"
            });

    private static IResult AuthorizationDenied() =>
        Results.Problem(
            statusCode: StatusCodes.Status403Forbidden,
            title: "Acceso no concedido",
            detail:
                "La sesión no posee un permiso vigente para este ámbito.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.authorization.denied"
            });
}

internal static class AnyEffectivePermissionRouteHandlerExtensions
{
    public static RouteHandlerBuilder RequireAnyEffectivePermission(
        this RouteHandlerBuilder builder,
        string[] permissionCodes,
        string auditCode,
        string? moduleCode = null,
        string? routeObjectKey = null)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentNullException.ThrowIfNull(permissionCodes);
        ArgumentException.ThrowIfNullOrWhiteSpace(auditCode);

        if (permissionCodes.Length == 0
            || permissionCodes.Any(string.IsNullOrWhiteSpace))
        {
            throw new ArgumentException(
                "Debe indicarse al menos un permiso válido.",
                nameof(permissionCodes));
        }

        builder.RequireAuthorization();
        builder.AddEndpointFilter(
            new AnyEffectivePermissionEndpointFilter(
                permissionCodes,
                auditCode,
                moduleCode,
                routeObjectKey));

        return builder;
    }
}
