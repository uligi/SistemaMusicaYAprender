using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.Administration;

public sealed record AnalysisReadingDraft(Guid TokenId, string ReadingKana, string? Furigana, string? Romaji, string ReadingType);
public sealed record AnalysisVocabularyDraft(Guid TokenId, string Lemma, string Reading, string PartOfSpeech, string SenseKey, string Definition, string? UsageNote, string? Inflection, string ConfidenceCode);
public sealed record AnalysisKanjiDraft(Guid TokenId, int CharOffset, string Character, string? Reading, string ReadingType, string? Meaning, string? GradeCode, string? JlptCode);
public sealed record AnalysisMorphologyDraft(Guid TokenId, string Lemma, string PartOfSpeechCode, string? ConjugationCode, string FeaturesJson);
public sealed record AnalysisGrammarDraft(Guid LineId, Guid? StartTokenId, Guid? EndTokenId, string GrammarCode, string Title, string? LevelCode, string? Note, string? Explanation, string? Examples);
public sealed record CreateLinguisticAnalysisRevisionInput(Guid LyricsRevisionId, string ExplanationLanguage, string ProvenanceCitation, List<AnalysisReadingDraft> Readings, List<AnalysisVocabularyDraft> Vocabulary, List<AnalysisKanjiDraft> Kanji, List<AnalysisMorphologyDraft> Morphology, List<AnalysisGrammarDraft> Grammar);

public sealed record AnalysisValidationIssue(string Severity, string Code, string Message, string? Location);
public sealed record AnalysisCoveragePreview(int TotalTokens, int ReadingTokens, int VocabularyTokens, int KanjiTokens, int MorphologyTokens, int TotalLines, int GrammarLines);
public sealed record AnalysisValidationReport(bool CanSave, int ErrorCount, int WarningCount, int OrphanCount, string ChecksumSha256, AnalysisCoveragePreview Coverage, string ProvenanceCitation, List<AnalysisValidationIssue> Issues);

public sealed class LinguisticAnalysisValidationException(AnalysisValidationReport report)
    : InvalidOperationException("El borrador de análisis contiene errores.")
{
    public AnalysisValidationReport Report { get; } = report;
}

public sealed partial class LinguisticAnalysisEditorialWriter(
    ILinguisticAnalysisAdministrationTransactionExecutor transactionExecutor,
    LinguisticAnalysisRevisionAdministrationService reader)
{
    private const int MaxAnnotations = 5000;
    private const int MaxTextLength = 4000;
    private const int MaxCitationLength = 1000;

    [GeneratedRegex("^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$", RegexOptions.CultureInvariant)]
    private static partial Regex LanguageTagPattern();

    [GeneratedRegex("^[A-Z0-9][A-Z0-9._-]{0,63}$", RegexOptions.CultureInvariant)]
    private static partial Regex CodePattern();

    public static string ETagFor(LinguisticAnalysisContextSnapshot context)
    {
        if (context.LyricsRevisionId is not { } lyricsId) return "\"analysis-none\"";
        if (context.Revision is not { } revision) return $"\"analysis-{lyricsId:N}-none\"";
        return $"\"analysis-{revision.AnalysisRevisionId:N}-r{revision.RevisionNo}\"";
    }

    public Task<AnalysisValidationReport> ValidateAsync(
        Guid actorAccountId,
        Guid recordingId,
        CreateLinguisticAnalysisRevisionInput input,
        string ifMatch,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);
        ValidateIdentity(actorAccountId, recordingId, correlationId);
        var prepared = Prepare(input);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ValidateCoreAsync(connection, transaction, recordingId, prepared, ifMatch, token),
            cancellationToken);
    }

    public async Task<LinguisticAnalysisContextSnapshot> CreateRevisionAsync(
        Guid actorAccountId,
        Guid recordingId,
        CreateLinguisticAnalysisRevisionInput input,
        string ifMatch,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);
        ValidateIdentity(actorAccountId, recordingId, correlationId);
        var prepared = Prepare(input);

        await transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await AcquireLockAsync(connection, transaction, recordingId, token);

                var validation = await ValidateCoreAsync(
                    connection, transaction, recordingId, prepared, ifMatch, token);

                if (!validation.CanSave)
                {
                    throw new LinguisticAnalysisValidationException(validation);
                }

                var current = await ReadCurrentHeaderAsync(
                    connection, transaction, prepared.LyricsRevisionId, token);

                if (current is not null
                    && string.Equals(current.ChecksumSha256, validation.ChecksumSha256, StringComparison.OrdinalIgnoreCase))
                {
                    return 0;
                }

                var revisionId = Guid.CreateVersion7();
                var revisionNo = (current?.RevisionNo ?? 0) + 1;
                await InsertRevisionAsync(
                    connection,
                    transaction,
                    revisionId,
                    prepared.LyricsRevisionId,
                    revisionNo,
                    current?.AnalysisRevisionId,
                    Convert.FromHexString(validation.ChecksumSha256),
                    token);

                foreach (var item in prepared.Readings)
                    await InsertReadingAsync(connection, transaction, revisionId, item, token);

                foreach (var item in prepared.Vocabulary)
                {
                    var vocabularyId = await ResolveVocabularyAsync(
                        connection, transaction, item, prepared.ExplanationLanguage, token);
                    await InsertVocabularyOccurrenceAsync(
                        connection, transaction, revisionId, vocabularyId, item, token);
                }

                foreach (var item in prepared.Kanji)
                {
                    var kanjiId = await ResolveKanjiAsync(
                        connection, transaction, item, prepared.ExplanationLanguage, token);
                    await InsertKanjiOccurrenceAsync(
                        connection, transaction, revisionId, kanjiId, item, token);
                }

                foreach (var item in prepared.Morphology)
                    await InsertMorphologyAsync(connection, transaction, revisionId, item, token);

                foreach (var item in prepared.Grammar)
                {
                    var grammarPointId = await ResolveGrammarAsync(
                        connection, transaction, item, prepared.ExplanationLanguage, token);
                    await InsertGrammarOccurrenceAsync(
                        connection, transaction, revisionId, grammarPointId, item, token);
                }

                await InsertProvenanceAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    revisionId,
                    prepared.LyricsRevisionId,
                    revisionNo,
                    prepared.ProvenanceCitation,
                    token);

                return 1;
            },
            cancellationToken);

        return await reader.ReadContextAsync(
            actorAccountId,
            recordingId,
            prepared.ExplanationLanguage,
            correlationId,
            cancellationToken);
    }

    private static async Task<AnalysisValidationReport> ValidateCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        PreparedAnalysisDraft prepared,
        string ifMatch,
        CancellationToken cancellationToken)
    {
        await AssertRecordingExistsAsync(connection, transaction, recordingId, cancellationToken);
        var lyrics = await ReadLatestLyricsAsync(connection, transaction, recordingId, cancellationToken);
        var current = lyrics is null
            ? null
            : await ReadCurrentHeaderAsync(connection, transaction, lyrics.LyricsRevisionId, cancellationToken);

        EnsureExpectedContext(lyrics, current, ifMatch);

        if (lyrics is null)
            throw new LinguisticAnalysisAdministrationException(
                "content.analysis.source.required",
                "El análisis necesita una revisión japonesa tokenizada.");

        if (prepared.LyricsRevisionId != lyrics.LyricsRevisionId)
            throw SourceConflict();

        var source = await ReadSourceStateAsync(
            connection, transaction, lyrics.LyricsRevisionId, cancellationToken);

        var issues = new List<AnalysisValidationIssue>();
        var orphanCount = 0;

        void Error(string code, string message, string? location = null) =>
            issues.Add(new AnalysisValidationIssue("ERROR", code, message, location));

        void Warning(string code, string message, string? location = null) =>
            issues.Add(new AnalysisValidationIssue("WARNING", code, message, location));

        if (string.IsNullOrWhiteSpace(prepared.ProvenanceCitation))
            Error("content.analysis.provenance.required", "Indica de dónde procede esta curaduría antes de guardar.", "procedencia");

        var annotationCount = prepared.Readings.Count + prepared.Vocabulary.Count + prepared.Kanji.Count + prepared.Morphology.Count + prepared.Grammar.Count;
        if (annotationCount == 0)
            Error("content.analysis.content.required", "Agrega al menos una lectura, sentido, kanji, morfología o punto gramatical.", "contenido");

        var readingKeys = new HashSet<(Guid, string)>();
        foreach (var item in prepared.Readings)
        {
            if (!source.Tokens.ContainsKey(item.TokenId))
            {
                orphanCount++;
                Error("content.analysis.token.orphan", "Una lectura apunta a una palabra que ya no pertenece a la letra vigente.", $"token:{item.TokenId:N}");
                continue;
            }

            if (!readingKeys.Add((item.TokenId, item.ReadingType)))
                Error("content.analysis.reading.duplicate", "Una palabra no puede repetir el mismo tipo de lectura.", $"token:{item.TokenId:N}");
        }

        var vocabularyKeys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in prepared.Vocabulary)
        {
            if (!source.Tokens.ContainsKey(item.TokenId))
            {
                orphanCount++;
                Error("content.analysis.token.orphan", "Un sentido apunta a una palabra que ya no pertenece a la letra vigente.", $"token:{item.TokenId:N}");
                continue;
            }

            if (!vocabularyKeys.Add($"{item.TokenId:N}|{item.Lemma}|{item.Reading}|{item.PartOfSpeech}|{item.SenseKey}"))
                Error("content.analysis.vocabulary.duplicate", "El mismo sentido aparece duplicado para esta palabra.", $"token:{item.TokenId:N}");
        }

        var kanjiKeys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in prepared.Kanji)
        {
            if (!source.Tokens.TryGetValue(item.TokenId, out var token))
            {
                orphanCount++;
                Error("content.analysis.token.orphan", "Un kanji apunta a una palabra que ya no pertenece a la letra vigente.", $"token:{item.TokenId:N}");
                continue;
            }

            var characters = token.Surface.EnumerateRunes().Select(rune => rune.ToString()).ToList();
            if (item.CharOffset < 0
                || item.CharOffset >= characters.Count
                || !string.Equals(characters[item.CharOffset], item.Character, StringComparison.Ordinal))
            {
                orphanCount++;
                Error("content.analysis.kanji.anchor.invalid", "La posición del kanji ya no coincide con la escritura original.", $"token:{item.TokenId:N}");
            }

            if ((item.Reading is null) != (item.Meaning is null))
                Error(
                    "content.analysis.kanji.reading-pair.required",
                    "Completa lectura general y significado educativo juntos, o deja ambos vacíos.",
                    $"token:{item.TokenId:N}");

            if (!kanjiKeys.Add($"{item.TokenId:N}|{item.CharOffset}|{item.Character}"))
                Error("content.analysis.kanji.duplicate", "El mismo kanji está repetido en la misma posición.", $"token:{item.TokenId:N}");
        }

        var morphologyTokens = new HashSet<Guid>();
        foreach (var item in prepared.Morphology)
        {
            if (!source.Tokens.ContainsKey(item.TokenId))
            {
                orphanCount++;
                Error("content.analysis.token.orphan", "Una anotación morfológica apunta a una palabra que ya no pertenece a la letra vigente.", $"token:{item.TokenId:N}");
                continue;
            }

            if (!morphologyTokens.Add(item.TokenId))
                Error("content.analysis.morphology.duplicate", "Solo puede existir una anotación morfológica por palabra.", $"token:{item.TokenId:N}");

            try { using var _ = JsonDocument.Parse(item.FeaturesJson); }
            catch (JsonException)
            {
                Error("content.analysis.morphology.features.invalid", "Los rasgos morfológicos avanzados no contienen JSON válido.", $"token:{item.TokenId:N}");
            }
        }

        var grammarKeys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in prepared.Grammar)
        {
            if (!source.Lines.Contains(item.LineId))
            {
                orphanCount++;
                Error("content.analysis.line.orphan", "Un punto gramatical apunta a una línea que ya no pertenece a la letra vigente.", $"line:{item.LineId:N}");
                continue;
            }

            SourceTokenState? start = null;
            SourceTokenState? end = null;

            if (item.StartTokenId is { } startId
                && (!source.Tokens.TryGetValue(startId, out start) || start.LineId != item.LineId))
            {
                orphanCount++;
                Error("content.analysis.grammar.start.invalid", "El inicio del rango gramatical no pertenece a la línea seleccionada.", $"line:{item.LineId:N}");
            }

            if (item.EndTokenId is { } endId
                && (!source.Tokens.TryGetValue(endId, out end) || end.LineId != item.LineId))
            {
                orphanCount++;
                Error("content.analysis.grammar.end.invalid", "El final del rango gramatical no pertenece a la línea seleccionada.", $"line:{item.LineId:N}");
            }

            if (start is not null && end is not null && start.TokenNo > end.TokenNo)
                Error("content.analysis.grammar.range.invalid", "El rango gramatical termina antes de empezar.", $"line:{item.LineId:N}");

            if (!grammarKeys.Add($"{item.LineId:N}|{item.GrammarCode}|{item.StartTokenId:N}|{item.EndTokenId:N}"))
                Error("content.analysis.grammar.duplicate", "El mismo punto gramatical y rango aparece duplicado.", $"line:{item.LineId:N}");
        }

        var readingCoverage = prepared.Readings.Select(x => x.TokenId).Where(source.Tokens.ContainsKey).Distinct().Count();
        var vocabularyCoverage = prepared.Vocabulary.Select(x => x.TokenId).Where(source.Tokens.ContainsKey).Distinct().Count();
        var kanjiCoverage = prepared.Kanji.Select(x => x.TokenId).Where(source.Tokens.ContainsKey).Distinct().Count();
        var morphologyCoverage = prepared.Morphology.Select(x => x.TokenId).Where(source.Tokens.ContainsKey).Distinct().Count();
        var grammarCoverage = prepared.Grammar.Select(x => x.LineId).Where(source.Lines.Contains).Distinct().Count();

        if (annotationCount > 0
            && (readingCoverage < source.Tokens.Count
                || vocabularyCoverage < source.Tokens.Count
                || morphologyCoverage < source.Tokens.Count
                || grammarCoverage < source.Lines.Count))
            Warning("content.analysis.coverage.partial", "El análisis es parcial. Puedes guardarlo así y continuar en otra revisión.", "cobertura");

        if (prepared.Kanji.Any(x => x.JlptCode is not null)
            || prepared.Grammar.Any(x => x.LevelCode is not null))
            Warning("content.analysis.level.orientative", "Los niveles JLPT se guardan como orientación educativa, no como certificación oficial.", "nivel");

        var checksum = BuildChecksum(prepared);
        var errors = issues.Count(x => x.Severity == "ERROR");
        var warnings = issues.Count(x => x.Severity == "WARNING");

        return new AnalysisValidationReport(
            errors == 0,
            errors,
            warnings,
            orphanCount,
            checksum,
            new AnalysisCoveragePreview(
                source.Tokens.Count,
                readingCoverage,
                vocabularyCoverage,
                kanjiCoverage,
                morphologyCoverage,
                source.Lines.Count,
                grammarCoverage),
            prepared.ProvenanceCitation,
            issues);
    }

    private static PreparedAnalysisDraft Prepare(CreateLinguisticAnalysisRevisionInput input)
    {
        if (input.LyricsRevisionId == Guid.Empty)
            throw new LinguisticAnalysisAdministrationException("content.analysis.source.invalid", "La revisión japonesa indicada no es válida.");

        var language = NormalizeLanguage(input.ExplanationLanguage);
        var citation = NormalizeRequired(input.ProvenanceCitation, MaxCitationLength, "content.analysis.provenance.invalid", "La procedencia es obligatoria y debe ser breve.");

        var readings = (input.Readings ?? []).Select(x => new PreparedReading(
            x.TokenId,
            NormalizeRequired(x.ReadingKana, MaxTextLength, "content.analysis.reading.invalid", "La lectura japonesa no es válida."),
            NormalizeOptional(x.Furigana, MaxTextLength),
            NormalizeOptional(x.Romaji, MaxTextLength),
            NormalizeCode(string.IsNullOrWhiteSpace(x.ReadingType) ? "CONTEXTUAL" : x.ReadingType, "content.analysis.reading.type.invalid")))
            .OrderBy(x => x.TokenId).ThenBy(x => x.ReadingType, StringComparer.Ordinal).ToList();

        var vocabulary = (input.Vocabulary ?? []).Select(x =>
        {
            var lemma = NormalizeRequired(x.Lemma, MaxTextLength, "content.analysis.vocabulary.lemma.invalid", "El lema no es válido.");
            var reading = NormalizeRequired(x.Reading, MaxTextLength, "content.analysis.vocabulary.reading.invalid", "La lectura del vocabulario no es válida.");
            var definition = NormalizeRequired(x.Definition, MaxTextLength, "content.analysis.vocabulary.definition.invalid", "El significado contextual no es válido.");
            var senseKey = string.IsNullOrWhiteSpace(x.SenseKey) ? $"editorial.{ShortHash($"{lemma}|{reading}|{definition}")}" : x.SenseKey.Trim();

            return new PreparedVocabulary(
                x.TokenId,
                lemma,
                reading,
                NormalizeCode(string.IsNullOrWhiteSpace(x.PartOfSpeech) ? "OTHER" : x.PartOfSpeech, "content.analysis.vocabulary.pos.invalid"),
                senseKey,
                definition,
                NormalizeOptional(x.UsageNote, MaxTextLength),
                NormalizeOptional(x.Inflection, MaxTextLength),
                NormalizeCode(string.IsNullOrWhiteSpace(x.ConfidenceCode) ? "EDITORIAL" : x.ConfidenceCode, "content.analysis.vocabulary.confidence.invalid"));
        }).OrderBy(x => x.TokenId).ThenBy(x => x.Lemma, StringComparer.Ordinal).ThenBy(x => x.SenseKey, StringComparer.Ordinal).ToList();

        var kanji = (input.Kanji ?? []).Select(x => new PreparedKanji(
            x.TokenId,
            x.CharOffset,
            NormalizeRequired(x.Character, 32, "content.analysis.kanji.character.invalid", "El carácter no es válido."),
            NormalizeOptional(x.Reading, MaxTextLength),
            NormalizeCode(string.IsNullOrWhiteSpace(x.ReadingType) ? "GENERAL" : x.ReadingType, "content.analysis.kanji.reading-type.invalid"),
            NormalizeOptional(x.Meaning, MaxTextLength),
            NormalizeOptionalCode(x.GradeCode),
            NormalizeOptionalCode(x.JlptCode)))
            .OrderBy(x => x.TokenId).ThenBy(x => x.CharOffset).ThenBy(x => x.Character, StringComparer.Ordinal).ToList();

        var morphology = (input.Morphology ?? []).Select(x => new PreparedMorphology(
            x.TokenId,
            NormalizeRequired(x.Lemma, MaxTextLength, "content.analysis.morphology.lemma.invalid", "El lema morfológico no es válido."),
            NormalizeCode(string.IsNullOrWhiteSpace(x.PartOfSpeechCode) ? "OTHER" : x.PartOfSpeechCode, "content.analysis.morphology.pos.invalid"),
            NormalizeOptionalCode(x.ConjugationCode),
            string.IsNullOrWhiteSpace(x.FeaturesJson) ? "{}" : x.FeaturesJson.Trim()))
            .OrderBy(x => x.TokenId).ToList();

        var grammar = (input.Grammar ?? []).Select(x =>
        {
            var title = NormalizeRequired(x.Title, MaxTextLength, "content.analysis.grammar.title.invalid", "El nombre del punto gramatical no es válido.");
            var code = string.IsNullOrWhiteSpace(x.GrammarCode)
                ? $"EDITORIAL.{ShortHash(title).ToUpperInvariant()}"
                : NormalizeCode(x.GrammarCode, "content.analysis.grammar.code.invalid");

            return new PreparedGrammar(
                x.LineId,
                x.StartTokenId,
                x.EndTokenId,
                code,
                title,
                NormalizeOptionalCode(x.LevelCode),
                NormalizeOptional(x.Note, MaxTextLength),
                NormalizeOptional(x.Explanation, MaxTextLength),
                NormalizeOptional(x.Examples, MaxTextLength));
        }).OrderBy(x => x.LineId).ThenBy(x => x.GrammarCode, StringComparer.Ordinal).ThenBy(x => x.StartTokenId).ThenBy(x => x.EndTokenId).ToList();

        if (readings.Count + vocabulary.Count + kanji.Count + morphology.Count + grammar.Count > MaxAnnotations)
            throw new LinguisticAnalysisAdministrationException("content.analysis.annotations.too-many", $"El borrador supera {MaxAnnotations} anotaciones.");

        return new PreparedAnalysisDraft(input.LyricsRevisionId, language, citation, readings, vocabulary, kanji, morphology, grammar);
    }

    private static string BuildChecksum(PreparedAnalysisDraft prepared) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(prepared)))).ToLowerInvariant();

    private static async Task AcquireLockAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid recordingId, CancellationToken token)
    {
        const string sql = "SELECT pg_advisory_xact_lock(hashtextextended(CAST(@recording_id AS text), 67));";
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task AssertRecordingExistsAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid recordingId, CancellationToken token)
    {
        const string sql = "SELECT EXISTS (SELECT 1 FROM catalog.recording WHERE recording_id=@recording_id);";
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        if (await command.ExecuteScalarAsync(token) is not true)
            throw new LinguisticAnalysisAdministrationException("content.analysis.recording.not-found", "La canción editorial indicada no existe.");
    }

    private static async Task<LyricsHeader?> ReadLatestLyricsAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid recordingId, CancellationToken token)
    {
        const string sql = """
            SELECT lyrics_revision_id, revision_no
            FROM content.lyrics_revision
            WHERE recording_id=@recording_id
            ORDER BY revision_no DESC, lyrics_revision_id DESC
            LIMIT 1;
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        await using var reader = await command.ExecuteReaderAsync(token);
        return await reader.ReadAsync(token) ? new LyricsHeader(reader.GetGuid(0), reader.GetInt32(1)) : null;
    }

    private static async Task<AnalysisHeader?> ReadCurrentHeaderAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid lyricsRevisionId, CancellationToken token)
    {
        const string sql = """
            SELECT analysis_revision_id, revision_no, encode(checksum,'hex')
            FROM content.linguistic_analysis_revision
            WHERE lyrics_revision_id=@lyrics_revision_id
            ORDER BY revision_no DESC, analysis_revision_id DESC
            LIMIT 1;
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("lyrics_revision_id", NpgsqlDbType.Uuid, lyricsRevisionId);
        await using var reader = await command.ExecuteReaderAsync(token);
        return await reader.ReadAsync(token) ? new AnalysisHeader(reader.GetGuid(0), reader.GetInt32(1), reader.GetString(2)) : null;
    }

    private static async Task<SourceState> ReadSourceStateAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid lyricsRevisionId, CancellationToken token)
    {
        const string sql = """
            SELECT line.line_id, token.token_id, token.token_no, token.surface
            FROM content.lyric_section section
            JOIN content.lyric_line line ON line.section_id=section.section_id
            LEFT JOIN content.lyric_token token ON token.line_id=line.line_id
            WHERE section.lyrics_revision_id=@lyrics_revision_id
            ORDER BY section.display_order, section.section_id, line.line_no, line.line_id, token.token_no, token.token_id;
            """;

        var lines = new HashSet<Guid>();
        var tokens = new Dictionary<Guid, SourceTokenState>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("lyrics_revision_id", NpgsqlDbType.Uuid, lyricsRevisionId);
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var lineId = reader.GetGuid(0);
            lines.Add(lineId);
            if (!reader.IsDBNull(1))
            {
                var tokenId = reader.GetGuid(1);
                tokens[tokenId] = new SourceTokenState(tokenId, lineId, reader.GetInt32(2), reader.GetString(3));
            }
        }
        return new SourceState(lines, tokens);
    }

    private static void EnsureExpectedContext(LyricsHeader? lyrics, AnalysisHeader? analysis, string ifMatch)
    {
        if (string.IsNullOrWhiteSpace(ifMatch))
            throw new LinguisticAnalysisAdministrationException("content.analysis.precondition-required", "Recarga el análisis antes de validar o guardar.");

        var expected = lyrics is null
            ? "\"analysis-none\""
            : analysis is null
                ? $"\"analysis-{lyrics.LyricsRevisionId:N}-none\""
                : $"\"analysis-{analysis.AnalysisRevisionId:N}-r{analysis.RevisionNo}\"";

        if (!string.Equals(ifMatch.Trim(), expected, StringComparison.Ordinal))
            throw new LinguisticAnalysisAdministrationException("content.analysis.conflict", "La letra o el análisis cambió mientras estabas trabajando. Tu borrador local se conserva.");
    }

    private static LinguisticAnalysisAdministrationException SourceConflict() =>
        new("content.analysis.source-changed", "La revisión japonesa cambió. Recarga antes de volver a guardar.");

    private static async Task InsertRevisionAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid revisionId, Guid lyricsId, int revisionNo, Guid? parentId, byte[] checksum, CancellationToken token)
    {
        const string sql = """
            INSERT INTO content.linguistic_analysis_revision
            (analysis_revision_id,lyrics_revision_id,revision_no,parent_revision_id,status_code,checksum)
            VALUES (@id,@lyrics,@revision,@parent,'DRAFT',@checksum);
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, revisionId);
        command.Parameters.AddWithValue("lyrics", NpgsqlDbType.Uuid, lyricsId);
        command.Parameters.AddWithValue("revision", NpgsqlDbType.Integer, revisionNo);
        AddNullableUuid(command, "parent", parentId);
        command.Parameters.AddWithValue("checksum", NpgsqlDbType.Bytea, checksum);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task InsertReadingAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid revisionId, PreparedReading item, CancellationToken token)
    {
        const string sql = """
            INSERT INTO content.token_reading
            (token_reading_id,analysis_revision_id,token_id,reading_kana,furigana,romaji,reading_type)
            VALUES (@id,@revision,@token,@reading,@furigana,@romaji,@type);
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
        command.Parameters.AddWithValue("revision", NpgsqlDbType.Uuid, revisionId);
        command.Parameters.AddWithValue("token", NpgsqlDbType.Uuid, item.TokenId);
        command.Parameters.AddWithValue("reading", item.ReadingKana);
        AddNullableText(command, "furigana", item.Furigana);
        AddNullableText(command, "romaji", item.Romaji);
        command.Parameters.AddWithValue("type", item.ReadingType);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task<Guid> ResolveVocabularyAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, PreparedVocabulary item, string language, CancellationToken token)
    {
        const string readSql = """
            SELECT vocabulary_id FROM content.vocabulary_entry
            WHERE lemma=@lemma AND reading=@reading AND part_of_speech=@pos AND sense_key=@sense
            LIMIT 1;
            """;
        Guid? id = null;
        await using (var read = new NpgsqlCommand(readSql, connection, transaction))
        {
            read.Parameters.AddWithValue("lemma", item.Lemma);
            read.Parameters.AddWithValue("reading", item.Reading);
            read.Parameters.AddWithValue("pos", item.PartOfSpeech);
            read.Parameters.AddWithValue("sense", item.SenseKey);
            if (await read.ExecuteScalarAsync(token) is Guid found) id = found;
        }

        if (id is null)
        {
            id = Guid.CreateVersion7();
            const string insert = """
                INSERT INTO content.vocabulary_entry
                (vocabulary_id,lemma,reading,part_of_speech,sense_key,status_code,version)
                VALUES (@id,@lemma,@reading,@pos,@sense,'ACTIVE',1);
                """;
            await using var command = new NpgsqlCommand(insert, connection, transaction);
            command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
            command.Parameters.AddWithValue("lemma", item.Lemma);
            command.Parameters.AddWithValue("reading", item.Reading);
            command.Parameters.AddWithValue("pos", item.PartOfSpeech);
            command.Parameters.AddWithValue("sense", item.SenseKey);
            await command.ExecuteNonQueryAsync(token);
        }

        const string latestMatches = """
            SELECT EXISTS (
              SELECT 1
              FROM (
                SELECT definition, usage_note
                FROM content.vocabulary_sense
                WHERE vocabulary_id=@id AND language_tag=@language
                ORDER BY display_order DESC, sense_id DESC
                LIMIT 1
              ) AS latest
              WHERE latest.definition=@definition
                AND latest.usage_note IS NOT DISTINCT FROM @usage_note
            );
            """;
        var hasLatestSense = false;
        await using (var command = new NpgsqlCommand(latestMatches, connection, transaction))
        {
            command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
            command.Parameters.AddWithValue("language", language);
            command.Parameters.AddWithValue("definition", item.Definition);
            AddNullableText(command, "usage_note", item.UsageNote);
            hasLatestSense = await command.ExecuteScalarAsync(token) is true;
        }

        if (!hasLatestSense)
        {
            const string insertSense = """
                INSERT INTO content.vocabulary_sense
                (sense_id,vocabulary_id,language_tag,definition,usage_note,display_order)
                SELECT @sense_id,@id,@language,@definition,@usage_note,COALESCE(MAX(display_order),-1)+1
                FROM content.vocabulary_sense
                WHERE vocabulary_id=@id AND language_tag=@language;
                """;
            await using var command = new NpgsqlCommand(insertSense, connection, transaction);
            command.Parameters.AddWithValue("sense_id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
            command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
            command.Parameters.AddWithValue("language", language);
            command.Parameters.AddWithValue("definition", item.Definition);
            AddNullableText(command, "usage_note", item.UsageNote);
            await command.ExecuteNonQueryAsync(token);
        }

        return id.Value;
    }

    private static async Task InsertVocabularyOccurrenceAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid revisionId, Guid vocabularyId, PreparedVocabulary item, CancellationToken token)
    {
        const string sql = """
            INSERT INTO content.vocabulary_occurrence
            (occurrence_id,analysis_revision_id,token_id,vocabulary_id,inflection,confidence_code)
            VALUES (@id,@revision,@token,@vocabulary,@inflection,@confidence);
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
        command.Parameters.AddWithValue("revision", NpgsqlDbType.Uuid, revisionId);
        command.Parameters.AddWithValue("token", NpgsqlDbType.Uuid, item.TokenId);
        command.Parameters.AddWithValue("vocabulary", NpgsqlDbType.Uuid, vocabularyId);
        AddNullableText(command, "inflection", item.Inflection);
        command.Parameters.AddWithValue("confidence", item.ConfidenceCode);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task<Guid> ResolveKanjiAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, PreparedKanji item, string language, CancellationToken token)
    {
        Guid? id = null;
        await using (var read = new NpgsqlCommand("SELECT kanji_id FROM content.kanji_entry WHERE character=@character LIMIT 1;", connection, transaction))
        {
            read.Parameters.AddWithValue("character", item.Character);
            if (await read.ExecuteScalarAsync(token) is Guid found) id = found;
        }

        if (id is null)
        {
            id = Guid.CreateVersion7();
            const string insert = """
                INSERT INTO content.kanji_entry
                (kanji_id,character,grade_code,jlpt_code,status_code,version)
                VALUES (@id,@character,@grade,@jlpt,'ACTIVE',1);
                """;
            await using var command = new NpgsqlCommand(insert, connection, transaction);
            command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
            command.Parameters.AddWithValue("character", item.Character);
            AddNullableText(command, "grade", item.GradeCode);
            AddNullableText(command, "jlpt", item.JlptCode);
            await command.ExecuteNonQueryAsync(token);
        }
        else
        {
            const string updateEntry = """
                UPDATE content.kanji_entry
                SET grade_code=@grade,
                    jlpt_code=@jlpt
                WHERE kanji_id=@id
                  AND (
                    grade_code IS DISTINCT FROM @grade
                    OR jlpt_code IS DISTINCT FROM @jlpt
                  );
                """;
            await using var command = new NpgsqlCommand(updateEntry, connection, transaction);
            command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
            AddNullableText(command, "grade", item.GradeCode);
            AddNullableText(command, "jlpt", item.JlptCode);
            await command.ExecuteNonQueryAsync(token);
        }

        if (item.Reading is not null && item.Meaning is not null)
        {
            Guid? readingId = null;
            const string readReading = """
                SELECT kanji_reading_id
                FROM content.kanji_reading
                WHERE kanji_id=@id
                  AND reading=@reading
                  AND reading_type=@type
                  AND language_tag=@language
                LIMIT 1;
                """;
            await using (var command = new NpgsqlCommand(readReading, connection, transaction))
            {
                command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
                command.Parameters.AddWithValue("reading", item.Reading);
                command.Parameters.AddWithValue("type", item.ReadingType);
                command.Parameters.AddWithValue("language", language);
                if (await command.ExecuteScalarAsync(token) is Guid found) readingId = found;
            }

            if (readingId is null)
            {
                const string insert = """
                    INSERT INTO content.kanji_reading
                    (kanji_reading_id,kanji_id,reading,reading_type,language_tag,meaning,display_order)
                    SELECT @reading_id,@id,@reading,@type,@language,@meaning,COALESCE(MAX(display_order),-1)+1
                    FROM content.kanji_reading
                    WHERE kanji_id=@id AND language_tag=@language;
                    """;
                await using var command = new NpgsqlCommand(insert, connection, transaction);
                command.Parameters.AddWithValue("reading_id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
                command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
                command.Parameters.AddWithValue("reading", item.Reading);
                command.Parameters.AddWithValue("type", item.ReadingType);
                command.Parameters.AddWithValue("language", language);
                command.Parameters.AddWithValue("meaning", item.Meaning);
                await command.ExecuteNonQueryAsync(token);
            }
            else
            {
                const string updateReading = """
                    UPDATE content.kanji_reading
                    SET meaning=@meaning,
                        display_order=(
                          SELECT COALESCE(MAX(other.display_order),-1)+1
                          FROM content.kanji_reading AS other
                          WHERE other.kanji_id=@id
                            AND other.language_tag=@language
                            AND other.kanji_reading_id<>@reading_id
                        )
                    WHERE kanji_reading_id=@reading_id
                      AND (
                        meaning IS DISTINCT FROM @meaning
                        OR display_order<>(
                          SELECT COALESCE(MAX(other.display_order),-1)+1
                          FROM content.kanji_reading AS other
                          WHERE other.kanji_id=@id
                            AND other.language_tag=@language
                            AND other.kanji_reading_id<>@reading_id
                        )
                      );
                    """;
                await using var command = new NpgsqlCommand(updateReading, connection, transaction);
                command.Parameters.AddWithValue("reading_id", NpgsqlDbType.Uuid, readingId.Value);
                command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
                command.Parameters.AddWithValue("language", language);
                command.Parameters.AddWithValue("meaning", item.Meaning);
                await command.ExecuteNonQueryAsync(token);
            }
        }

        return id.Value;
    }

    private static async Task InsertKanjiOccurrenceAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid revisionId, Guid kanjiId, PreparedKanji item, CancellationToken token)
    {
        const string sql = """
            INSERT INTO content.kanji_occurrence
            (occurrence_id,analysis_revision_id,token_id,kanji_id,char_offset)
            VALUES (@id,@revision,@token,@kanji,@offset);
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
        command.Parameters.AddWithValue("revision", NpgsqlDbType.Uuid, revisionId);
        command.Parameters.AddWithValue("token", NpgsqlDbType.Uuid, item.TokenId);
        command.Parameters.AddWithValue("kanji", NpgsqlDbType.Uuid, kanjiId);
        command.Parameters.AddWithValue("offset", NpgsqlDbType.Integer, item.CharOffset);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task InsertMorphologyAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid revisionId, PreparedMorphology item, CancellationToken token)
    {
        const string sql = """
            INSERT INTO content.morphology_annotation
            (annotation_id,analysis_revision_id,token_id,lemma,pos_code,conjugation_code,features)
            VALUES (@id,@revision,@token,@lemma,@pos,@conjugation,CAST(@features AS jsonb));
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
        command.Parameters.AddWithValue("revision", NpgsqlDbType.Uuid, revisionId);
        command.Parameters.AddWithValue("token", NpgsqlDbType.Uuid, item.TokenId);
        command.Parameters.AddWithValue("lemma", item.Lemma);
        command.Parameters.AddWithValue("pos", item.PartOfSpeechCode);
        AddNullableText(command, "conjugation", item.ConjugationCode);
        command.Parameters.AddWithValue("features", item.FeaturesJson);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task<Guid> ResolveGrammarAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, PreparedGrammar item, string language, CancellationToken token)
    {
        Guid? id = null;
        await using (var read = new NpgsqlCommand("SELECT grammar_point_id FROM content.grammar_point WHERE grammar_code=@code LIMIT 1;", connection, transaction))
        {
            read.Parameters.AddWithValue("code", item.GrammarCode);
            if (await read.ExecuteScalarAsync(token) is Guid found) id = found;
        }

        if (id is null)
        {
            id = Guid.CreateVersion7();
            const string insert = """
                INSERT INTO content.grammar_point
                (grammar_point_id,grammar_code,title,level_code,status_code,version)
                VALUES (@id,@code,@title,@level,'ACTIVE',1);
                """;
            await using var command = new NpgsqlCommand(insert, connection, transaction);
            command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
            command.Parameters.AddWithValue("code", item.GrammarCode);
            command.Parameters.AddWithValue("title", item.Title);
            AddNullableText(command, "level", item.LevelCode);
            await command.ExecuteNonQueryAsync(token);
        }
        else
        {
            const string updatePoint = """
                UPDATE content.grammar_point
                SET title=@title,
                    level_code=@level
                WHERE grammar_point_id=@id
                  AND (
                    title IS DISTINCT FROM @title
                    OR level_code IS DISTINCT FROM @level
                  );
                """;
            await using var command = new NpgsqlCommand(updatePoint, connection, transaction);
            command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
            command.Parameters.AddWithValue("title", item.Title);
            AddNullableText(command, "level", item.LevelCode);
            await command.ExecuteNonQueryAsync(token);
        }

        if (item.Explanation is not null)
        {
            const string latestMatches = """
                SELECT EXISTS (
                  SELECT 1
                  FROM (
                    SELECT explanation, examples
                    FROM content.grammar_explanation
                    WHERE grammar_point_id=@id AND language_tag=@language
                    ORDER BY revision_no DESC, explanation_id DESC
                    LIMIT 1
                  ) AS latest
                  WHERE latest.explanation=@explanation
                    AND latest.examples IS NOT DISTINCT FROM @examples
                );
                """;
            var hasLatestExplanation = false;
            await using (var command = new NpgsqlCommand(latestMatches, connection, transaction))
            {
                command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
                command.Parameters.AddWithValue("language", language);
                command.Parameters.AddWithValue("explanation", item.Explanation);
                AddNullableText(command, "examples", item.Examples);
                hasLatestExplanation = await command.ExecuteScalarAsync(token) is true;
            }

            if (!hasLatestExplanation)
            {
                const string insert = """
                    INSERT INTO content.grammar_explanation
                    (explanation_id,grammar_point_id,language_tag,explanation,examples,revision_no)
                    SELECT @explanation_id,@id,@language,@explanation,@examples,COALESCE(MAX(revision_no),0)+1
                    FROM content.grammar_explanation
                    WHERE grammar_point_id=@id AND language_tag=@language;
                    """;
                await using var command = new NpgsqlCommand(insert, connection, transaction);
                command.Parameters.AddWithValue("explanation_id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
                command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, id.Value);
                command.Parameters.AddWithValue("language", language);
                command.Parameters.AddWithValue("explanation", item.Explanation);
                AddNullableText(command, "examples", item.Examples);
                await command.ExecuteNonQueryAsync(token);
            }
        }

        return id.Value;
    }

    private static async Task InsertGrammarOccurrenceAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid revisionId, Guid grammarPointId, PreparedGrammar item, CancellationToken token)
    {
        const string sql = """
            INSERT INTO content.grammar_occurrence
            (occurrence_id,analysis_revision_id,grammar_point_id,line_id,start_token_id,end_token_id,note)
            VALUES (@id,@revision,@grammar,@line,@start,@end,@note);
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
        command.Parameters.AddWithValue("revision", NpgsqlDbType.Uuid, revisionId);
        command.Parameters.AddWithValue("grammar", NpgsqlDbType.Uuid, grammarPointId);
        command.Parameters.AddWithValue("line", NpgsqlDbType.Uuid, item.LineId);
        AddNullableUuid(command, "start", item.StartTokenId);
        AddNullableUuid(command, "end", item.EndTokenId);
        AddNullableText(command, "note", item.Note);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task InsertProvenanceAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, Guid actorId, Guid revisionId, Guid lyricsId, int revisionNo, string citation, CancellationToken token)
    {
        var sourceId = Guid.CreateVersion7();
        const string sourceSql = """
            INSERT INTO catalog.source_reference
            (source_reference_id,source_type,citation,locator,retrieved_at,checksum)
            VALUES (@id,'EDITORIAL',@citation,@locator,CURRENT_TIMESTAMP,NULL);
            """;
        await using (var command = new NpgsqlCommand(sourceSql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, sourceId);
            command.Parameters.AddWithValue("citation", citation);
            command.Parameters.AddWithValue("locator", $"lyrics_revision:{lyricsId:N};analysis_revision:{revisionNo}");
            await command.ExecuteNonQueryAsync(token);
        }

        const string provenanceSql = """
            INSERT INTO editorial.provenance_record
            (provenance_id,object_type,object_id,source_reference_id,contribution_type,recorded_by)
            VALUES (@id,'LINGUISTIC_ANALYSIS_REVISION',@object,@source,'ANALYSIS_AUTHOR',@actor);
            """;
        await using var provenance = new NpgsqlCommand(provenanceSql, connection, transaction);
        provenance.Parameters.AddWithValue("id", NpgsqlDbType.Uuid, Guid.CreateVersion7());
        provenance.Parameters.AddWithValue("object", NpgsqlDbType.Uuid, revisionId);
        provenance.Parameters.AddWithValue("source", NpgsqlDbType.Uuid, sourceId);
        provenance.Parameters.AddWithValue("actor", NpgsqlDbType.Uuid, actorId);
        await provenance.ExecuteNonQueryAsync(token);
    }

    private static void AddNullableText(NpgsqlCommand command, string name, string? value)
    {
        var parameter = command.Parameters.Add(name, NpgsqlDbType.Text);
        parameter.Value = value is null ? DBNull.Value : value;
    }

    private static void AddNullableUuid(NpgsqlCommand command, string name, Guid? value)
    {
        var parameter = command.Parameters.Add(name, NpgsqlDbType.Uuid);
        parameter.Value = value is { } id ? id : DBNull.Value;
    }

    private static string NormalizeLanguage(string value)
    {
        var normalized = value?.Trim() ?? "";
        if (!LanguageTagPattern().IsMatch(normalized))
            throw new LinguisticAnalysisAdministrationException("content.analysis.language.invalid", "El idioma de explicación no es válido.");
        return normalized;
    }

    private static string NormalizeRequired(string value, int max, string code, string message)
    {
        var normalized = value?.Trim() ?? "";
        if (normalized.Length == 0 || normalized.Length > max)
            throw new LinguisticAnalysisAdministrationException(code, message);
        return normalized;
    }

    private static string? NormalizeOptional(string? value, int max)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var normalized = value.Trim();
        if (normalized.Length > max)
            throw new LinguisticAnalysisAdministrationException("content.analysis.text.too-long", $"Un campo supera {max} caracteres.");
        return normalized;
    }

    private static string NormalizeCode(string value, string code)
    {
        var normalized = value.Trim().ToUpperInvariant();
        if (!CodePattern().IsMatch(normalized))
            throw new LinguisticAnalysisAdministrationException(code, "Un código interno del análisis no es válido.");
        return normalized;
    }

    private static string? NormalizeOptionalCode(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : NormalizeCode(value, "content.analysis.code.invalid");

    private static string ShortHash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)))[..16].ToLowerInvariant();

    private static void ValidateIdentity(Guid actorId, Guid recordingId, string correlationId)
    {
        if (actorId == Guid.Empty || recordingId == Guid.Empty || string.IsNullOrWhiteSpace(correlationId))
            throw new LinguisticAnalysisAdministrationException("content.analysis.identity.invalid", "No fue posible validar la identidad o el contexto editorial.");
    }

    private sealed record LyricsHeader(Guid LyricsRevisionId, int RevisionNo);
    private sealed record AnalysisHeader(Guid AnalysisRevisionId, int RevisionNo, string ChecksumSha256);
    private sealed record SourceTokenState(Guid TokenId, Guid LineId, int TokenNo, string Surface);
    private sealed record SourceState(HashSet<Guid> Lines, Dictionary<Guid, SourceTokenState> Tokens);
    private sealed record PreparedReading(Guid TokenId, string ReadingKana, string? Furigana, string? Romaji, string ReadingType);
    private sealed record PreparedVocabulary(Guid TokenId, string Lemma, string Reading, string PartOfSpeech, string SenseKey, string Definition, string? UsageNote, string? Inflection, string ConfidenceCode);
    private sealed record PreparedKanji(Guid TokenId, int CharOffset, string Character, string? Reading, string ReadingType, string? Meaning, string? GradeCode, string? JlptCode);
    private sealed record PreparedMorphology(Guid TokenId, string Lemma, string PartOfSpeechCode, string? ConjugationCode, string FeaturesJson);
    private sealed record PreparedGrammar(Guid LineId, Guid? StartTokenId, Guid? EndTokenId, string GrammarCode, string Title, string? LevelCode, string? Note, string? Explanation, string? Examples);
    private sealed record PreparedAnalysisDraft(Guid LyricsRevisionId, string ExplanationLanguage, string ProvenanceCitation, List<PreparedReading> Readings, List<PreparedVocabulary> Vocabulary, List<PreparedKanji> Kanji, List<PreparedMorphology> Morphology, List<PreparedGrammar> Grammar);
}
