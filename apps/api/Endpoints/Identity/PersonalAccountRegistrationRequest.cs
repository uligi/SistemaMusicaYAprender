namespace MusicaAprender.Api.Endpoints.Identity;

public sealed record PersonalAccountRegistrationConsentRequest(
    string? PurposeCode,
    string? NoticeVersion,
    bool Decision);

public sealed record PersonalAccountRegistrationRequest(
    string? Email,
    string? Password,
    IReadOnlyList<PersonalAccountRegistrationConsentRequest>? Consents);

public sealed record RegistrationConsentNoticeResponse(
    string PurposeCode,
    string Title,
    string NoticeVersion,
    DateTimeOffset EffectiveFromUtc,
    bool Required);

public sealed record RegistrationConsentCatalogResponse(
    IReadOnlyList<RegistrationConsentNoticeResponse> Notices);
