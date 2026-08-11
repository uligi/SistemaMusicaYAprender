using System.Security.Claims;
using MusicaAprender.Modules.Security.Infrastructure.Authorization;
using Npgsql;

namespace MusicaAprender.Api.Security;

internal sealed class EffectivePermissionEndpointFilter(
    string permissionCode,
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

            var decision = await authorization.AuthorizeAsync(
                accountId,
                permissionCode,
                requiredScope,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            if (!decision.Allowed)
            {
                return AuthorizationDenied();
            }

            return await next(context);
        }
        catch (NpgsqlException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Autorización temporalmente no disponible",
                detail:
                    "La operación protegida se cerró de forma segura. "
                    + "Vuelve a intentarlo más tarde.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "security.authorization.unavailable"
                });
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

internal static class EffectivePermissionRouteHandlerExtensions
{
    public static RouteHandlerBuilder RequireEffectivePermission(
        this RouteHandlerBuilder builder,
        string permissionCode,
        string? moduleCode = null,
        string? routeObjectKey = null)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentException.ThrowIfNullOrWhiteSpace(permissionCode);

        builder.RequireAuthorization();
        builder.AddEndpointFilter(
            new EffectivePermissionEndpointFilter(
                permissionCode,
                moduleCode,
                routeObjectKey));

        return builder;
    }
}
