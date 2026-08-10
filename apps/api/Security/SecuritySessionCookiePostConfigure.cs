using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.Extensions.Options;

namespace MusicaAprender.Api.Security;

internal sealed class SecuritySessionCookiePostConfigure(
    SecuritySessionTicketStore ticketStore)
    : IPostConfigureOptions<CookieAuthenticationOptions>
{
    public void PostConfigure(
        string? name,
        CookieAuthenticationOptions options)
    {
        if (string.Equals(
                name,
                SessionAuthenticationDefaults.Scheme,
                StringComparison.Ordinal))
        {
            options.SessionStore = ticketStore;
        }
    }
}
