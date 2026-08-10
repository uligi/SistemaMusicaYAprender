namespace MusicaAprender.Api.Endpoints.Identity;

public sealed record PersonalAccountLoginRequest(
    string? Email,
    string? Password);
