namespace MusicaAprender.Modules.Security.Infrastructure.Authentication;

public sealed record ActivePasswordCredential(
    Guid AccountId,
    string Hash,
    string Algorithm,
    string Parameters);
