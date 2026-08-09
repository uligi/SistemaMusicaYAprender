using System.Security.Claims;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;

namespace MusicaAprender.Api.Security;

internal sealed class HttpDatabaseSessionContextFactory : IHttpDatabaseSessionContextFactory
{
    private const string AccountIdClaim = "account_id";
    private const string ActiveRoleClaim = "active_role";
    private const string SubjectClaim = "sub";
    private const string RoleClaim = "role";

    public DatabaseSessionContext CreateRequired(HttpContext httpContext)
    {
        ArgumentNullException.ThrowIfNull(httpContext);

        if (httpContext.User.Identity?.IsAuthenticated != true)
        {
            throw new InvalidOperationException(
                "No se puede crear contexto de base para una solicitud no autenticada.");
        }

        var accountValues = ReadDistinctClaims(
            httpContext.User,
            AccountIdClaim,
            ClaimTypes.NameIdentifier,
            SubjectClaim);

        if (accountValues.Count != 1
            || !Guid.TryParse(accountValues[0], out var accountId)
            || accountId == Guid.Empty)
        {
            throw new InvalidOperationException(
                "La identidad autenticada debe contener un unico account_id UUID coherente.");
        }

        var activeRoleValues = ReadDistinctClaims(
            httpContext.User,
            ActiveRoleClaim);

        string roleCode;

        if (activeRoleValues.Count == 1)
        {
            roleCode = activeRoleValues[0];
        }
        else if (activeRoleValues.Count > 1)
        {
            throw new InvalidOperationException(
                "La identidad autenticada contiene mas de un rol activo.");
        }
        else
        {
            var fallbackRoles = ReadDistinctClaims(
                httpContext.User,
                ClaimTypes.Role,
                RoleClaim);

            if (fallbackRoles.Count != 1)
            {
                throw new InvalidOperationException(
                    "La identidad autenticada debe resolver exactamente un rol activo.");
            }

            roleCode = fallbackRoles[0];
        }

        return DatabaseSessionContext.Create(
            accountId,
            roleCode,
            httpContext.TraceIdentifier);
    }

    private static List<string> ReadDistinctClaims(
        ClaimsPrincipal principal,
        params string[] claimTypes)
    {
        return claimTypes
            .SelectMany(principal.FindAll)
            .Select(static claim => claim.Value.Trim())
            .Where(static value => value.Length > 0)
            .Distinct(StringComparer.Ordinal)
            .ToList();
    }
}
