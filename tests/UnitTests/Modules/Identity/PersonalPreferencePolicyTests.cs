using MusicaAprender.Modules.Identity.Application.Preferences;
using Xunit;

namespace MusicaAprender.UnitTests.Modules.Identity;

public sealed class PersonalPreferencePolicyTests
{
    [Fact]
    public void SafeDefaultsUseSpanishPrivateAndProtectiveAccessibility()
    {
        var values =
            PersonalPreferencePolicy.CreateSafeDefaults(3);

        Assert.Equal("ES", values.InterfaceLanguage);
        Assert.Equal("ES", values.TranslationLanguage);
        Assert.Equal("PRIVATE", values.Privacy.ActivityVisibility);
        Assert.True(values.Accessibility.ReducedMotion);
        Assert.True(values.Accessibility.FlashProtection);
        Assert.Equal(3, values.Provenance.LanguageCatalogVersion);
    }

    [Fact]
    public void ValidateRejectsUnsupportedLanguage()
    {
        var draft = ValidDraft() with
        {
            InterfaceLanguage = "EN"
        };

        var result =
            PersonalPreferencePolicy.Validate(draft);

        Assert.False(result.IsValid);
        Assert.Equal("interfaceLanguage", result.Field);
    }

    [Fact]
    public void ValidateRequiresAtLeastOneJapaneseLayer()
    {
        var current = ValidDraft();
        var draft = current with
        {
            Japanese = current.Japanese! with
            {
                ShowKanji = false,
                ShowKana = false
            }
        };

        var result =
            PersonalPreferencePolicy.Validate(draft);

        Assert.False(result.IsValid);
        Assert.Equal("japanese", result.Field);
    }

    [Fact]
    public void NormalizeProducesCanonicalCodesAndServerProvenance()
    {
        var draft = ValidDraft() with
        {
            InterfaceLanguage = "es",
            TranslationLanguage = "es",
            Japanese = ValidDraft().Japanese! with
            {
                FuriganaMode = "always",
                RomajiMode = "hidden"
            }
        };

        var values =
            PersonalPreferencePolicy.Normalize(
                draft,
                languageCatalogVersion: 7);

        Assert.Equal("ES", values.InterfaceLanguage);
        Assert.Equal("ALWAYS", values.Japanese.FuriganaMode);
        Assert.Equal("HIDDEN", values.Japanese.RomajiMode);
        Assert.Equal(7, values.Provenance.LanguageCatalogVersion);
    }

    private static PersonalPreferenceDraft ValidDraft() =>
        new(
            Version: 1,
            InterfaceLanguage: "ES",
            TranslationLanguage: "ES",
            Japanese: new JapaneseReadingPreferences(
                ShowKanji: true,
                ShowKana: true,
                FuriganaMode: "AUTO",
                RomajiMode: "HELP",
                ShowNaturalTranslation: true),
            Accessibility: new AccessibilityPreferences(
                FontScalePercent: 100,
                HighContrast: false,
                ReducedMotion: true,
                FlashProtection: true),
            Privacy: new PrivacyPreferences(
                ActivityVisibility: "PRIVATE"));
}
