namespace MusicaAprender.Modules.Content.Infrastructure.Administration;

public sealed record EditorialKaraokeTimelineToken(
    int TokenNo,
    string Surface,
    long StartMs,
    long EndMs);

public sealed record EditorialKaraokeTimelineLine(
    int SectionOrder,
    int LineNo,
    string JapaneseText,
    string? SpeakerLabel,
    string PrecisionCode,
    long StartMs,
    long EndMs,
    IReadOnlyList<EditorialKaraokeTimelineToken> Tokens);

public sealed record EditorialKaraokeTimeline(
    bool Available,
    string MaximumPrecision,
    long OffsetMs,
    IReadOnlyList<EditorialKaraokeTimelineLine> Lines);

public sealed record EditorialKaraokeReading(
    string ReadingKana,
    string? Furigana,
    string? Romaji,
    string ReadingType);

public sealed record EditorialKaraokeToken(
    int TokenNo,
    string Surface,
    int StartOffset,
    int EndOffset,
    IReadOnlyList<EditorialKaraokeReading> Readings);

public sealed record EditorialKaraokeTranslation(
    string VariantCode,
    string TranslatedText,
    int DisplayOrder);

public sealed record EditorialKaraokeLine(
    int SectionOrder,
    string? SectionLabel,
    int LineNo,
    string JapaneseText,
    string? SpeakerLabel,
    IReadOnlyList<EditorialKaraokeToken> Tokens,
    IReadOnlyList<EditorialKaraokeTranslation> Translations);

public sealed record EditorialKaraokeLayers(
    bool Available,
    string TargetLanguage,
    bool HasFurigana,
    bool HasRomaji,
    bool HasSpanish,
    IReadOnlyList<EditorialKaraokeLine> Lines);

public sealed record EditorialKaraokePreviewSnapshot(
    string PreviewMode,
    string ProviderCode,
    string ExternalRef,
    int LyricsRevisionNo,
    string LyricsStatusCode,
    string TimingStatusCode,
    string TranslationStatusCode,
    string AnalysisStatusCode,
    EditorialKaraokeTimeline Timeline,
    EditorialKaraokeLayers Layers);

public sealed class EditorialKaraokePreviewException(
    string code,
    string message)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed class EditorialKaraokePreviewService(
    LyricsStructureAdministrationService lyricsService,
    TimingRevisionAdministrationService timingService,
    TranslationRevisionAdministrationService translationService,
    LinguisticAnalysisRevisionAdministrationService analysisService)
{
    public async Task<EditorialKaraokePreviewSnapshot> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        Guid sourceId,
        string targetLanguage,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (actorAccountId == Guid.Empty
            || recordingId == Guid.Empty
            || sourceId == Guid.Empty
            || string.IsNullOrWhiteSpace(correlationId))
        {
            throw new ArgumentException(
                "Actor, grabacion, fuente y correlacion son obligatorios.");
        }

        var timingContext = await timingService.ReadContextAsync(
            actorAccountId,
            recordingId,
            correlationId,
            cancellationToken);

        var source = timingContext.Sources.SingleOrDefault(
            candidate => candidate.SourceId == sourceId);

        if (source is null)
        {
            throw new EditorialKaraokePreviewException(
                "content.karaoke-preview.source.not-found",
                "La fuente seleccionada no pertenece a la grabacion editorial.");
        }

        if (!string.Equals(
                source.ProviderCode,
                "YOUTUBE",
                StringComparison.OrdinalIgnoreCase))
        {
            throw new EditorialKaraokePreviewException(
                "content.karaoke-preview.provider.unsupported",
                "La previsualizacion de karaoke requiere una fuente de YouTube.");
        }

        var lyrics = await lyricsService.ReadLatestAsync(
            actorAccountId,
            recordingId,
            correlationId,
            cancellationToken);

        var language = string.IsNullOrWhiteSpace(targetLanguage)
            ? "es"
            : targetLanguage.Trim();

        if (lyrics is null)
        {
            return Empty(
                source.ProviderCode,
                source.ExternalRef,
                language);
        }

        if (timingContext.LyricsRevisionId is not { } timingLyricsRevisionId
            || timingLyricsRevisionId != lyrics.LyricsRevisionId)
        {
            throw new EditorialKaraokePreviewException(
                "content.karaoke-preview.lyrics.changed",
                "La revision japonesa cambio mientras se preparaba la previsualizacion.");
        }

        var translation = await translationService.ReadContextAsync(
            actorAccountId,
            recordingId,
            language,
            "HUMAN",
            correlationId,
            cancellationToken);

        var analysis = await analysisService.ReadContextAsync(
            actorAccountId,
            recordingId,
            language,
            correlationId,
            cancellationToken);

        var timingRevision =
            source.TimingRevision is { } candidateTiming
            && candidateTiming.LyricsRevisionId == lyrics.LyricsRevisionId
                ? candidateTiming
                : null;

        var translationRevision =
            translation.LyricsRevisionId == lyrics.LyricsRevisionId
            && translation.Revision is { } candidateTranslation
            && candidateTranslation.LyricsRevisionId == lyrics.LyricsRevisionId
                ? candidateTranslation
                : null;

        var analysisRevision =
            analysis.LyricsRevisionId == lyrics.LyricsRevisionId
            && analysis.Revision is { } candidateAnalysis
            && candidateAnalysis.LyricsRevisionId == lyrics.LyricsRevisionId
                ? candidateAnalysis
                : null;

        var translationsByLine =
            (translationRevision?.Lines
                ?? [])
            .GroupBy(static item => item.AnchorLineId)
            .ToDictionary(
                static group => group.Key,
                static group =>
                    (IReadOnlyList<EditorialKaraokeTranslation>)group
                        .OrderBy(static item => item.DisplayOrder)
                        .ThenBy(static item => item.VariantCode, StringComparer.Ordinal)
                        .Select(static item => new EditorialKaraokeTranslation(
                            item.VariantCode,
                            item.TranslatedText,
                            item.DisplayOrder))
                        .ToList());

        var readingsByToken =
            (analysisRevision?.Readings
                ?? [])
            .GroupBy(static item => item.TokenId)
            .ToDictionary(
                static group => group.Key,
                static group =>
                    (IReadOnlyList<EditorialKaraokeReading>)group
                        .OrderBy(static item => ReadingRank(item.ReadingType))
                        .ThenBy(static item => item.ReadingType, StringComparer.Ordinal)
                        .ThenBy(static item => item.ReadingKana, StringComparer.Ordinal)
                        .Select(static item => new EditorialKaraokeReading(
                            item.ReadingKana,
                            item.Furigana,
                            item.Romaji,
                            item.ReadingType))
                        .ToList());

        var lines = lyrics.Sections
            .OrderBy(static section => section.DisplayOrder)
            .SelectMany(
                section => section.Lines
                    .OrderBy(static line => line.LineNo)
                    .Select(line => new EditorialKaraokeLine(
                        section.DisplayOrder,
                        section.Label,
                        line.LineNo,
                        line.JapaneseText,
                        line.SpeakerLabel,
                        line.Tokens
                            .OrderBy(static token => token.TokenNo)
                            .Select(token => new EditorialKaraokeToken(
                                token.TokenNo,
                                token.Surface,
                                token.StartOffset,
                                token.EndOffset,
                                readingsByToken.TryGetValue(
                                    token.TokenId,
                                    out var tokenReadings)
                                        ? tokenReadings
                                        : Array.Empty<EditorialKaraokeReading>()))
                            .ToList(),
                        translationsByLine.TryGetValue(
                            line.LineId,
                            out var lineTranslations)
                                ? lineTranslations
                                : Array.Empty<EditorialKaraokeTranslation>())))
            .ToList();

        var hasReadings =
            analysisRevision?.Readings.Count > 0;
        var hasSpanish =
            translationRevision?.Lines.Count > 0;

        return new EditorialKaraokePreviewSnapshot(
            "DRAFT",
            source.ProviderCode,
            source.ExternalRef,
            lyrics.RevisionNo,
            lyrics.StatusCode,
            timingRevision?.StatusCode ?? "MISSING",
            translationRevision?.StatusCode
                ?? (translation.HasStaleRevision ? "STALE" : "MISSING"),
            analysisRevision?.StatusCode
                ?? (analysis.HasStaleRevision ? "STALE" : "MISSING"),
            BuildTimeline(timingRevision),
            new EditorialKaraokeLayers(
                lines.Count > 0,
                language,
                hasReadings,
                hasReadings,
                hasSpanish,
                lines));
    }

    private static EditorialKaraokePreviewSnapshot Empty(
        string providerCode,
        string externalRef,
        string targetLanguage) =>
        new(
            "DRAFT",
            providerCode,
            externalRef,
            0,
            "MISSING",
            "MISSING",
            "MISSING",
            "MISSING",
            new EditorialKaraokeTimeline(
                false,
                "NONE",
                0,
                Array.Empty<EditorialKaraokeTimelineLine>()),
            new EditorialKaraokeLayers(
                false,
                targetLanguage,
                false,
                false,
                false,
                Array.Empty<EditorialKaraokeLine>()));

    private static EditorialKaraokeTimeline BuildTimeline(
        TimingRevisionSnapshot? revision)
    {
        if (revision is null)
        {
            return new EditorialKaraokeTimeline(
                false,
                "NONE",
                0,
                Array.Empty<EditorialKaraokeTimelineLine>());
        }

        var lines = revision.Lines
            .OrderBy(static line => line.SectionOrder)
            .ThenBy(static line => line.LineNo)
            .Select(line => new EditorialKaraokeTimelineLine(
                line.SectionOrder,
                line.LineNo,
                line.JapaneseText,
                line.SpeakerLabel,
                line.PrecisionCode,
                line.StartMs,
                line.EndMs,
                line.Tokens
                    .OrderBy(static token => token.TokenNo)
                    .Select(static token => new EditorialKaraokeTimelineToken(
                        token.TokenNo,
                        token.Surface,
                        token.StartMs,
                        token.EndMs))
                    .ToList()))
            .ToList();

        var precision = lines.Any(
            static line =>
                string.Equals(
                    line.PrecisionCode,
                    "TOKEN",
                    StringComparison.OrdinalIgnoreCase)
                && line.Tokens.Count > 0)
            ? "TOKEN"
            : lines.Count > 0
                ? "LINE"
                : "NONE";

        return new EditorialKaraokeTimeline(
            lines.Count > 0,
            precision,
            revision.OffsetMs,
            lines);
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
