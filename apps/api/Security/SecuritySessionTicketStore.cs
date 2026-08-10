using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using MusicaAprender.Modules.Security.Infrastructure.Authentication;

namespace MusicaAprender.Api.Security;

internal sealed class SecuritySessionTicketStore(
    SecuritySessionPersistence persistence,
    IHttpContextAccessor httpContextAccessor) : ITicketStore
{
    public async Task<string> StoreAsync(AuthenticationTicket ticket)
    {
        ArgumentNullException.ThrowIfNull(ticket);

        var accountValue = ticket.Principal.FindFirstValue("account_id");
        if (!Guid.TryParse(accountValue, out var accountId) || accountId == Guid.Empty)
        {
            throw new InvalidOperationException(
                "La sesion autenticada no contiene un account_id valido.");
        }

        var token = SecuritySessionTokenService.CreateToken();
        if (!SecuritySessionTokenService.TryHashToken(token, out var sessionHash))
        {
            throw new InvalidOperationException(
                "No se pudo proteger el identificador opaco de sesion.");
        }

        try
        {
            await persistence.CreateAsync(
                accountId,
                sessionHash,
                CorrelationId());
            return token;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(sessionHash);
        }
    }

    public Task RenewAsync(string key, AuthenticationTicket ticket)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentNullException.ThrowIfNull(ticket);

        // BL-MVP-029 implementara la renovacion controlada por actividad y riesgo.
        return Task.CompletedTask;
    }

    public async Task<AuthenticationTicket?> RetrieveAsync(string key)
    {
        if (!SecuritySessionTokenService.TryHashToken(key, out var sessionHash))
        {
            return null;
        }

        try
        {
            var session = await persistence.ResolveAsync(
                sessionHash,
                CorrelationId());
            if (session is null)
            {
                return null;
            }

            var accountId = session.AccountId.ToString("D");
            var claims = new[]
            {
                new Claim(ClaimTypes.NameIdentifier, accountId),
                new Claim("sub", accountId),
                new Claim("account_id", accountId),
                new Claim(ClaimTypes.Role, SecuritySessionPolicy.SafeRoleCode),
                new Claim("role", SecuritySessionPolicy.SafeRoleCode),
                new Claim("active_role", SecuritySessionPolicy.SafeRoleCode),
                new Claim("session_id", session.SessionId.ToString("D")),
                new Claim("assurance_level", session.AssuranceLevel)
            };
            var identity = new ClaimsIdentity(
                claims,
                SessionAuthenticationDefaults.Scheme,
                ClaimTypes.NameIdentifier,
                ClaimTypes.Role);
            var properties = new AuthenticationProperties
            {
                AllowRefresh = false,
                IsPersistent = true,
                IssuedUtc = session.CreatedAt,
                ExpiresUtc = session.AbsoluteExpiresAt
            };

            return new AuthenticationTicket(
                new ClaimsPrincipal(identity),
                properties,
                SessionAuthenticationDefaults.Scheme);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(sessionHash);
        }
    }

    public async Task RemoveAsync(string key)
    {
        if (!SecuritySessionTokenService.TryHashToken(key, out var sessionHash))
        {
            return;
        }

        try
        {
            await persistence.RevokeAsync(
                sessionHash,
                CorrelationId());
        }
        finally
        {
            CryptographicOperations.ZeroMemory(sessionHash);
        }
    }

    private string CorrelationId() =>
        httpContextAccessor.HttpContext?.TraceIdentifier
        ?? Guid.NewGuid().ToString("N");
}
