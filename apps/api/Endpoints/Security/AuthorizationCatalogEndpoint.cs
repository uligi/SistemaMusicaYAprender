using System.Security.Claims;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Security.Infrastructure.Authorization;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Security;

public static class AuthorizationCatalogEndpoint
{
    public static IEndpointRouteBuilder MapAuthorizationCatalog(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/security/authorization/catalog",
                HandleAsync)
            .RequireEffectivePermission("SECURITY.MANAGE_ROLES")
            .Produces<AuthorizationCatalogResponse>(
                StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("GetAuthorizationCatalog")
            .WithTags("Security");

        return endpoints;
    }

    private static async Task<IResult> HandleAsync(
        ClaimsPrincipal user,
        HttpContext httpContext,
        EffectiveAuthorizationService authorization,
        CancellationToken cancellationToken)
    {
        var accountValue = user.FindFirstValue("account_id");
        if (!Guid.TryParse(accountValue, out var accountId)
            || accountId == Guid.Empty)
        {
            return Results.Unauthorized();
        }

        try
        {
            var catalog = await authorization.ReadCatalogAsync(
                accountId,
                httpContext.TraceIdentifier,
                cancellationToken);

            httpContext.Response.Headers.CacheControl = "no-store";

            return Results.Ok(new AuthorizationCatalogResponse(
                "AUTHORIZED",
                catalog.Roles,
                catalog.Permissions));
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
}

public sealed record AuthorizationCatalogResponse(
    string Status,
    IReadOnlyList<string> Roles,
    IReadOnlyList<string> Permissions);
