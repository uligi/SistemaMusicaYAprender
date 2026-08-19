using System.Text.RegularExpressions;

namespace MusicaAprender.Modules.Identity.Application.Profile;

public enum UsernameValidationError
{
    None,
    Required,
    Length,
    Format,
    Reserved,
    Unavailable
}

public sealed record UsernameValidationResult(
    bool IsValid,
    string? NormalizedUsername,
    UsernameValidationError Error);

public static partial class UsernamePolicy
{
    public const int MinLength = 3;
    public const int MaxLength = 32;

    private static readonly HashSet<string> Reserved =
        new(StringComparer.Ordinal)
        {
            "admin",
            "administrator",
            "api",
            "editor",
            "moderator",
            "musicayaprender",
            "reviewer",
            "root",
            "security",
            "support",
            "system",
            "www"
        };

    public static UsernameValidationResult Validate(string? value)
    {
        var normalized = value?.Trim().ToLowerInvariant();

        if (string.IsNullOrWhiteSpace(normalized))
        {
            return Invalid(UsernameValidationError.Required);
        }

        if (normalized.Length is < MinLength or > MaxLength)
        {
            return Invalid(UsernameValidationError.Length);
        }

        if (!UsernamePattern().IsMatch(normalized))
        {
            return Invalid(UsernameValidationError.Format);
        }

        if (Reserved.Contains(normalized))
        {
            return Invalid(UsernameValidationError.Reserved);
        }

        return new UsernameValidationResult(
            IsValid: true,
            normalized,
            UsernameValidationError.None);
    }

    private static UsernameValidationResult Invalid(
        UsernameValidationError error) =>
        new(
            IsValid: false,
            NormalizedUsername: null,
            error);

    [GeneratedRegex(
        "^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$",
        RegexOptions.CultureInvariant)]
    private static partial Regex UsernamePattern();
}
