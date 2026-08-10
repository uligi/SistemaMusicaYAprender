namespace MusicaAprender.Api.Security;

internal static class SessionAuthenticationDefaults
{
    public const string Scheme = "MusicaAprender.Session";
    public const string CookieName = "__Host-MusicaAprender.Session";
    public const string AntiforgeryCookieName = "__Host-MusicaAprender.Csrf";
    public const string AntiforgeryHeaderName = "X-CSRF-TOKEN";
}
