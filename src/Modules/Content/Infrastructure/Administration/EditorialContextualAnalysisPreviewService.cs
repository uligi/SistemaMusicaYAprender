using MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

namespace MusicaAprender.Modules.Content.Infrastructure.Administration;

public sealed record EditorialContextualReading(
    string ReadingKana,
    string? Furigana,
    string? Romaji,
    string ReadingType);

public sealed record EditorialContextualVocabularySense(
    string LanguageTag,
    string Definition,
    string? UsageNote,
    int DisplayOrder);

public sealed record EditorialContextualVocabulary(
    string Lemma,
    string? Reading,
    string? PartOfSpeech,
    string SenseKey,
    string? Inflection,
    string ConfidenceCode,
    IReadOnlyList<EditorialContextualVocabularySense> Senses);

public sealed record EditorialContextualKanjiReading(
    string Reading,
    string ReadingType,
    string LanguageTag,
    string Meaning,
    int DisplayOrder);

public sealed record EditorialContextualKanji(
    string Character,
    int CharOffset,
    string? GradeCode,
    string? JlptCode,
    IReadOnlyList<EditorialContextualKanjiReading> Readings);

public sealed record EditorialContextualMorphology(
    string Lemma,
    string PartOfSpeechCode,
    string? ConjugationCode);

public sealed record EditorialContextualGrammar(
    string GrammarCode,
    string Title,
    string? LevelCode,
    string? Note,
    string? Explanation,
    string? Examples);

public sealed record EditorialContextualProvenance(
    string SourceType,
    string Citation,
    string? Locator,
    string ContributionType);

public sealed record EditorialContextualLine(
    int SectionOrder,
    string? SectionLabel,
    int LineNo,
    string JapaneseText,
    string? SpeakerLabel);

public sealed record EditorialContextualAnalysisPreview(
    bool Available,
    string TokenKey,
    string Surface,
    int TokenNo,
    string TargetLanguage,
    EditorialContextualLine Line,
    IReadOnlyList<EditorialContextualReading> Readings,
    IReadOnlyList<EditorialContextualVocabulary> Vocabulary,
    IReadOnlyList<EditorialContextualKanji> Kanji,
    IReadOnlyList<EditorialContextualMorphology> Morphology,
    IReadOnlyList<EditorialContextualGrammar> Grammar,
    IReadOnlyList<EditorialContextualProvenance> Provenance);

public sealed class EditorialContextualAnalysisPreviewException(
    string code,
    string message)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed class EditorialContextualAnalysisPreviewService(
    LinguisticAnalysisRevisionAdministrationService analysisService)
{
    public async Task<EditorialContextualAnalysisPreview?> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        string tokenKey,
        string targetLanguage,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (actorAccountId == Guid.Empty
            || recordingId == Guid.Empty
            || string.IsNullOrWhiteSpace(correlationId))
        {
            throw new ArgumentException(
                "Actor, grabación y correlación son obligatorios.");
        }

        var normalizedTokenKey = PublicAnalysisTokenKey.Normalize(tokenKey);
        var language = string.IsNullOrWhiteSpace(targetLanguage)
            ? "es"
            : targetLanguage.Trim();

        var context = await analysisService.ReadContextAsync(
            actorAccountId,
            recordingId,
            language,
            correlationId,
            cancellationToken);

        if (context.LyricsRevisionId is null)
        {
            return null;
        }

        if (context.Revision is null)
        {
            if (context.HasStaleRevision)
            {
                throw new EditorialContextualAnalysisPreviewException(
                    "content.analysis-preview.stale",
                    "Existe análisis de otra revisión de letra. No se mezclará con el borrador actual.");
            }

            return null;
        }

        var revision = context.Revision;
        if (revision.LyricsRevisionId != context.LyricsRevisionId)
        {
            throw new EditorialContextualAnalysisPreviewException(
                "content.analysis-preview.incompatible",
                "La revisión de análisis no corresponde a la revisión DRAFT de letra actual.");
        }

        var matches = context.SourceLines
            .SelectMany(
                line => line.Tokens.Select(
                    token => new
                    {
                        Line = line,
                        Token = token,
                        Key = PublicAnalysisTokenKey.FromTokenId(token.TokenId)
                    }))
            .Where(
                candidate => string.Equals(
                    candidate.Key,
                    normalizedTokenKey,
                    StringComparison.Ordinal))
            .Take(2)
            .ToList();

        if (matches.Count == 0)
        {
            return null;
        }

        if (matches.Count > 1)
        {
            throw new EditorialContextualAnalysisPreviewException(
                "content.analysis-preview.ambiguous",
                "La referencia opaca coincide con más de un token del borrador.");
        }

        var target = matches[0];
        var tokenId = target.Token.TokenId;
        var lineId = target.Line.LineId;

        var readings = revision.Readings
            .Where(item => item.TokenId == tokenId)
            .OrderBy(item => ReadingRank(item.ReadingType))
            .ThenBy(item => item.ReadingType, StringComparer.Ordinal)
            .ThenBy(item => item.ReadingKana, StringComparer.Ordinal)
            .Select(item => new EditorialContextualReading(
                item.ReadingKana,
                item.Furigana,
                item.Romaji,
                item.ReadingType))
            .ToList();

        var vocabulary = revision.Vocabulary
            .Where(item => item.TokenId == tokenId)
            .OrderBy(item => item.Lemma, StringComparer.Ordinal)
            .ThenBy(item => item.SenseKey, StringComparer.Ordinal)
            .Select(item => new EditorialContextualVocabulary(
                item.Lemma,
                item.Reading,
                item.PartOfSpeech,
                item.SenseKey,
                item.Inflection,
                item.ConfidenceCode,
                item.Senses
                    .OrderBy(sense => sense.DisplayOrder)
                    .ThenBy(sense => sense.SenseId)
                    .Select(sense => new EditorialContextualVocabularySense(
                        sense.LanguageTag,
                        sense.Definition,
                        sense.UsageNote,
                        sense.DisplayOrder))
                    .ToList()))
            .ToList();

        var kanji = revision.Kanji
            .Where(item => item.TokenId == tokenId)
            .OrderBy(item => item.CharOffset)
            .ThenBy(item => item.Character, StringComparer.Ordinal)
            .Select(item => new EditorialContextualKanji(
                item.Character,
                item.CharOffset,
                item.GradeCode,
                item.JlptCode,
                item.Readings
                    .OrderBy(reading => reading.DisplayOrder)
                    .ThenBy(reading => reading.KanjiReadingId)
                    .Select(reading => new EditorialContextualKanjiReading(
                        reading.Reading,
                        reading.ReadingType,
                        reading.LanguageTag,
                        reading.Meaning,
                        reading.DisplayOrder))
                    .ToList()))
            .ToList();

        var morphology = revision.Morphology
            .Where(item => item.TokenId == tokenId)
            .OrderBy(item => item.AnnotationId)
            .Select(item => new EditorialContextualMorphology(
                item.Lemma,
                item.PartOfSpeechCode,
                item.ConjugationCode))
            .ToList();

        var grammar = revision.Grammar
            .Where(item => AppliesToToken(item, target.Line, tokenId))
            .OrderBy(item => item.GrammarCode, StringComparer.Ordinal)
            .ThenBy(item => item.OccurrenceId)
            .Select(item => new EditorialContextualGrammar(
                item.GrammarCode,
                item.Title,
                item.LevelCode,
                item.Note,
                item.Explanation,
                item.Examples))
            .ToList();

        var provenance = revision.Provenance
            .OrderBy(item => item.SourceType, StringComparer.Ordinal)
            .ThenBy(item => item.Citation, StringComparer.Ordinal)
            .ThenBy(item => item.SourceReferenceId)
            .Select(item => new EditorialContextualProvenance(
                item.SourceType,
                item.Citation,
                item.Locator,
                item.ContributionType))
            .ToList();

        var available =
            vocabulary.Count > 0
            || kanji.Count > 0
            || morphology.Count > 0
            || grammar.Count > 0;

        return new EditorialContextualAnalysisPreview(
            available,
            normalizedTokenKey,
            target.Token.Surface,
            target.Token.TokenNo,
            context.ExplanationLanguage,
            new EditorialContextualLine(
                target.Line.SectionDisplayOrder,
                target.Line.SectionLabel,
                target.Line.LineNo,
                target.Line.JapaneseText,
                null),
            readings,
            vocabulary,
            kanji,
            morphology,
            grammar,
            provenance);
    }

    private static bool AppliesToToken(
        GrammarOccurrenceAnalysisSnapshot grammar,
        LinguisticSourceLineSnapshot line,
        Guid tokenId)
    {
        if (grammar.LineId != line.LineId)
        {
            return false;
        }

        var selectedIndex = line.Tokens.FindIndex(token => token.TokenId == tokenId);
        if (selectedIndex < 0)
        {
            return false;
        }

        var startIndex = 0;
        if (grammar.StartTokenId is { } startTokenId)
        {
            startIndex = line.Tokens.FindIndex(token => token.TokenId == startTokenId);
            if (startIndex < 0)
            {
                return false;
            }
        }

        var endIndex = line.Tokens.Count - 1;
        if (grammar.EndTokenId is { } endTokenId)
        {
            endIndex = line.Tokens.FindIndex(token => token.TokenId == endTokenId);
            if (endIndex < 0)
            {
                return false;
            }
        }

        return startIndex <= endIndex
            && selectedIndex >= startIndex
            && selectedIndex <= endIndex;
    }

    private static int ReadingRank(string readingType)
    {
        if (string.Equals(
                readingType,
                "PRIMARY",
                StringComparison.OrdinalIgnoreCase))
        {
            return 0;
        }

        if (string.Equals(
                readingType,
                "CONTEXTUAL",
                StringComparison.OrdinalIgnoreCase))
        {
            return 1;
        }

        return 2;
    }
}
