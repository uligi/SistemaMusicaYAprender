namespace MusicaAprender.Modules.Identity.Application.Preferences;

public sealed record JapaneseReadingPreferences(
    bool ShowKanji,
    bool ShowKana,
    string FuriganaMode,
    string RomajiMode,
    bool ShowNaturalTranslation);

public sealed record AccessibilityPreferences(
    int FontScalePercent,
    bool HighContrast,
    bool ReducedMotion,
    bool FlashProtection);

public sealed record PrivacyPreferences(
    string ActivityVisibility);

public sealed record PreferenceProvenance(
    int ContractVersion,
    long LanguageCatalogVersion);

public sealed record PersonalPreferenceValues(
    string InterfaceLanguage,
    string TranslationLanguage,
    JapaneseReadingPreferences Japanese,
    AccessibilityPreferences Accessibility,
    PrivacyPreferences Privacy,
    PreferenceProvenance Provenance);

public sealed record PersonalPreferenceDraft(
    long Version,
    string? InterfaceLanguage,
    string? TranslationLanguage,
    JapaneseReadingPreferences? Japanese,
    AccessibilityPreferences? Accessibility,
    PrivacyPreferences? Privacy);

public sealed record PersonalPreferenceValidation(
    bool IsValid,
    string? ErrorCode,
    string? Field)
{
    public static PersonalPreferenceValidation Valid { get; } =
        new(true, null, null);

    public static PersonalPreferenceValidation Invalid(
        string errorCode,
        string field) =>
        new(false, errorCode, field);
}

public static class PersonalPreferencePolicy
{
    public const int ContractVersion = 1;
    public const string SpanishLanguageCode = "ES";
    public const string DefaultTimeZone = "America/Costa_Rica";

    public static IReadOnlyList<string> FuriganaModes { get; } =
        ["ALWAYS", "AUTO", "HIDDEN"];

    public static IReadOnlyList<string> RomajiModes { get; } =
        ["ALWAYS", "HELP", "HIDDEN"];

    public static IReadOnlyList<int> FontScalePercents { get; } =
        [100, 125, 150, 175, 200];

    public static IReadOnlyList<string> PrivacyVisibilities { get; } =
        ["PRIVATE"];

    public static PersonalPreferenceValues CreateSafeDefaults(
        long languageCatalogVersion)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(
            languageCatalogVersion);

        return new PersonalPreferenceValues(
            SpanishLanguageCode,
            SpanishLanguageCode,
            new JapaneseReadingPreferences(
                ShowKanji: true,
                ShowKana: true,
                FuriganaMode: "AUTO",
                RomajiMode: "HELP",
                ShowNaturalTranslation: true),
            new AccessibilityPreferences(
                FontScalePercent: 100,
                HighContrast: false,
                ReducedMotion: true,
                FlashProtection: true),
            new PrivacyPreferences(
                ActivityVisibility: "PRIVATE"),
            new PreferenceProvenance(
                ContractVersion,
                languageCatalogVersion));
    }

    public static PersonalPreferenceValidation Validate(
        PersonalPreferenceDraft draft)
    {
        ArgumentNullException.ThrowIfNull(draft);

        if (draft.Version <= 0)
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.version.invalid",
                "version");
        }

        if (!IsSpanish(draft.InterfaceLanguage))
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.interface-language.invalid",
                "interfaceLanguage");
        }

        if (!IsSpanish(draft.TranslationLanguage))
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.translation-language.invalid",
                "translationLanguage");
        }

        if (draft.Japanese is null)
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.japanese.required",
                "japanese");
        }

        if (!draft.Japanese.ShowKanji
            && !draft.Japanese.ShowKana)
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.japanese-layer.required",
                "japanese");
        }

        if (!Contains(
                FuriganaModes,
                draft.Japanese.FuriganaMode))
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.furigana.invalid",
                "japanese.furiganaMode");
        }

        if (!Contains(
                RomajiModes,
                draft.Japanese.RomajiMode))
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.romaji.invalid",
                "japanese.romajiMode");
        }

        if (draft.Accessibility is null)
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.accessibility.required",
                "accessibility");
        }

        if (!FontScalePercents.Contains(
                draft.Accessibility.FontScalePercent))
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.font-scale.invalid",
                "accessibility.fontScalePercent");
        }

        if (draft.Privacy is null
            || !Contains(
                PrivacyVisibilities,
                draft.Privacy.ActivityVisibility))
        {
            return PersonalPreferenceValidation.Invalid(
                "identity.preferences.privacy.invalid",
                "privacy.activityVisibility");
        }

        return PersonalPreferenceValidation.Valid;
    }

    public static PersonalPreferenceValues Normalize(
        PersonalPreferenceDraft draft,
        long languageCatalogVersion)
    {
        var validation = Validate(draft);
        if (!validation.IsValid)
        {
            throw new PersonalPreferenceValidationException(validation);
        }

        return new PersonalPreferenceValues(
            SpanishLanguageCode,
            SpanishLanguageCode,
            new JapaneseReadingPreferences(
                draft.Japanese!.ShowKanji,
                draft.Japanese.ShowKana,
                draft.Japanese.FuriganaMode.Trim().ToUpperInvariant(),
                draft.Japanese.RomajiMode.Trim().ToUpperInvariant(),
                draft.Japanese.ShowNaturalTranslation),
            new AccessibilityPreferences(
                draft.Accessibility!.FontScalePercent,
                draft.Accessibility.HighContrast,
                draft.Accessibility.ReducedMotion,
                draft.Accessibility.FlashProtection),
            new PrivacyPreferences(
                "PRIVATE"),
            new PreferenceProvenance(
                ContractVersion,
                languageCatalogVersion));
    }

    private static bool IsSpanish(string? value) =>
        string.Equals(
            value?.Trim(),
            SpanishLanguageCode,
            StringComparison.OrdinalIgnoreCase);

    private static bool Contains(
        IReadOnlyList<string> allowed,
        string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var normalized = value.Trim().ToUpperInvariant();
        return allowed.Contains(
            normalized,
            StringComparer.Ordinal);
    }
}

public sealed class PersonalPreferenceValidationException(
    PersonalPreferenceValidation validation)
    : Exception("La preferencia solicitada no cumple el contrato vigente.")
{
    public PersonalPreferenceValidation Validation { get; } = validation;
}

public sealed class PersonalPreferenceConcurrencyException(
    long currentVersion)
    : Exception("La revisión de preferencias cambió antes de confirmar.")
{
    public long CurrentVersion { get; } = currentVersion;
}
