using System.Buffers;
using System.Globalization;
using System.Text;

namespace MusicaAprender.Modules.Security.Infrastructure.Credentials;

public static class PasswordPolicy
{
    public const string Version = "PASSWORD_V1_2026-08-10";
    public const int MinimumLength = 15;
    public const int MaximumLength = 128;

    private static readonly HashSet<string> BlockedValues = new(
        StringComparer.OrdinalIgnoreCase)
    {
        "123456789012345",
        "adminadminadmin",
        "correcthorsebatterystaple",
        "iloveyouiloveyou",
        "japonesjapones",
        "letmeinletmein",
        "musicayaprender",
        "passwordpassword",
        "qwertyuiopasdfgh",
        "thisisapassword",
        "thisismypassword",
        "welcomehome123"
    };

    public static PasswordPolicyResult Validate(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return PasswordPolicyResult.Invalid(PasswordValidationError.Required);
        }

        if (string.IsNullOrWhiteSpace(value))
        {
            return PasswordPolicyResult.Invalid(PasswordValidationError.Blocked);
        }

        string normalized;
        try
        {
            normalized = value.Normalize(NormalizationForm.FormC);
        }
        catch (ArgumentException)
        {
            return PasswordPolicyResult.Invalid(PasswordValidationError.InvalidCharacters);
        }

        var length = 0;
        var remaining = normalized.AsSpan();
        while (!remaining.IsEmpty)
        {
            var status = Rune.DecodeFromUtf16(
                remaining,
                out var rune,
                out var charactersConsumed);

            if (status != OperationStatus.Done)
            {
                return PasswordPolicyResult.Invalid(PasswordValidationError.InvalidCharacters);
            }

            if (Rune.GetUnicodeCategory(rune) is
                UnicodeCategory.Control or
                UnicodeCategory.LineSeparator or
                UnicodeCategory.ParagraphSeparator)
            {
                return PasswordPolicyResult.Invalid(PasswordValidationError.InvalidCharacters);
            }

            length++;
            remaining = remaining[charactersConsumed..];
        }

        if (length < MinimumLength)
        {
            return PasswordPolicyResult.Invalid(PasswordValidationError.TooShort);
        }

        if (length > MaximumLength)
        {
            return PasswordPolicyResult.Invalid(PasswordValidationError.TooLong);
        }

        if (BlockedValues.Contains(normalized))
        {
            return PasswordPolicyResult.Invalid(PasswordValidationError.Blocked);
        }

        return PasswordPolicyResult.Valid(normalized);
    }
}

public enum PasswordValidationError
{
    None,
    Required,
    TooShort,
    TooLong,
    InvalidCharacters,
    Blocked
}

public sealed record PasswordPolicyResult(
    bool IsValid,
    string? NormalizedPassword,
    PasswordValidationError Error)
{
    public static PasswordPolicyResult Valid(string normalizedPassword) =>
        new(true, normalizedPassword, PasswordValidationError.None);

    public static PasswordPolicyResult Invalid(PasswordValidationError error) =>
        new(false, null, error);
}
