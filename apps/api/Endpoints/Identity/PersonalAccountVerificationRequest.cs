namespace MusicaAprender.Api.Endpoints.Identity;

public sealed record PersonalAccountVerificationRequest(string? Token);

public sealed record PersonalAccountVerificationResendRequest(string? Email);

public sealed record PersonalAccountVerificationResponse(
    string Status,
    string Message);
