namespace MusicaAprender.Api.Endpoints.Identity;

public sealed record PersonalAccountLoginResponse(
    string Status,
    string Role,
    string Message);

public sealed record PersonalSessionResponse(
    string Status,
    string Role);

public sealed record AntiforgeryTokenResponse(
    string RequestToken,
    string HeaderName);
