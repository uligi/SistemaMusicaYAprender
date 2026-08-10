namespace MusicaAprender.Modules.Identity.Application.Consent;

public sealed record RequiredRegistrationConsentNotice(
    string PurposeCode,
    string Title,
    string NoticeVersion,
    DateTimeOffset EffectiveFromUtc,
    DateTimeOffset? EffectiveToUtc,
    bool Required);

public sealed record RegistrationConsentSubmission(
    string? PurposeCode,
    string? NoticeVersion,
    bool Decision);

public sealed record AcceptedRegistrationConsent(
    string PurposeCode,
    string NoticeVersion,
    bool Decision);

public enum RegistrationConsentValidationError
{
    None,
    Missing,
    Duplicate,
    UnknownPurpose,
    Rejected,
    ObsoleteVersion
}

public sealed record RegistrationConsentValidationResult(
    RegistrationConsentValidationError Error,
    IReadOnlyList<AcceptedRegistrationConsent> AcceptedConsents)
{
    public bool IsValid => Error == RegistrationConsentValidationError.None;
}

public static class RequiredRegistrationConsentPolicy
{
    private static readonly IReadOnlyList<RequiredRegistrationConsentNotice> PublishedNotices =
    [
        new(
            "TERMS_OF_USE",
            "Términos de uso",
            "2026-08-10",
            new DateTimeOffset(2026, 8, 10, 0, 0, 0, TimeSpan.Zero),
            EffectiveToUtc: null,
            Required: true),
        new(
            "PRIVACY_POLICY",
            "Política de privacidad",
            "2026-08-10",
            new DateTimeOffset(2026, 8, 10, 0, 0, 0, TimeSpan.Zero),
            EffectiveToUtc: null,
            Required: true)
    ];

    public static IReadOnlyList<RequiredRegistrationConsentNotice> GetCurrentNotices(
        DateTimeOffset utcNow)
    {
        var current = PublishedNotices
            .Where(notice =>
                notice.Required
                && notice.EffectiveFromUtc <= utcNow
                && (notice.EffectiveToUtc is null || notice.EffectiveToUtc > utcNow))
            .ToArray();

        if (current.Length == 0
            || current.GroupBy(static notice => notice.PurposeCode, StringComparer.Ordinal)
                .Any(static group => group.Count() != 1))
        {
            throw new InvalidOperationException(
                "La publicación de consentimientos obligatorios no contiene una versión vigente única por finalidad.");
        }

        return current;
    }

    public static RegistrationConsentValidationResult Validate(
        IReadOnlyCollection<RegistrationConsentSubmission>? submissions,
        DateTimeOffset utcNow)
    {
        var current = GetCurrentNotices(utcNow);

        if (submissions is null || submissions.Count != current.Count)
        {
            return Invalid(RegistrationConsentValidationError.Missing);
        }

        var submittedByPurpose = new Dictionary<string, RegistrationConsentSubmission>(
            StringComparer.Ordinal);

        foreach (var submission in submissions)
        {
            if (string.IsNullOrWhiteSpace(submission.PurposeCode))
            {
                return Invalid(RegistrationConsentValidationError.UnknownPurpose);
            }

            if (!submittedByPurpose.TryAdd(submission.PurposeCode, submission))
            {
                return Invalid(RegistrationConsentValidationError.Duplicate);
            }
        }

        var currentPurposes = current
            .Select(static notice => notice.PurposeCode)
            .ToHashSet(StringComparer.Ordinal);

        if (submittedByPurpose.Keys.Any(purpose => !currentPurposes.Contains(purpose)))
        {
            return Invalid(RegistrationConsentValidationError.UnknownPurpose);
        }

        var accepted = new List<AcceptedRegistrationConsent>(current.Count);
        foreach (var notice in current)
        {
            if (!submittedByPurpose.TryGetValue(notice.PurposeCode, out var submission))
            {
                return Invalid(RegistrationConsentValidationError.Missing);
            }

            if (!submission.Decision)
            {
                return Invalid(RegistrationConsentValidationError.Rejected);
            }

            if (!string.Equals(
                    submission.NoticeVersion,
                    notice.NoticeVersion,
                    StringComparison.Ordinal))
            {
                return Invalid(RegistrationConsentValidationError.ObsoleteVersion);
            }

            accepted.Add(new AcceptedRegistrationConsent(
                notice.PurposeCode,
                notice.NoticeVersion,
                Decision: true));
        }

        return new RegistrationConsentValidationResult(
            RegistrationConsentValidationError.None,
            accepted);
    }

    private static RegistrationConsentValidationResult Invalid(
        RegistrationConsentValidationError error) =>
        new(error, Array.Empty<AcceptedRegistrationConsent>());
}
