namespace MusicaAprender.Modules.Security.Infrastructure.Authorization;

public sealed record AuthorizationDecision(
    bool Allowed,
    string ReasonCode)
{
    public static AuthorizationDecision Grant() =>
        new(true, "GRANTED");

    public static AuthorizationDecision Deny(string reasonCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(reasonCode);
        return new AuthorizationDecision(false, reasonCode);
    }
}
