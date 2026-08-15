param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedHead = "10aa6a5579d145cabf6fc776f5eb5992f47e6217"
$ExpectedBranch = "main"

function Fail([string]$Message) {
    throw "BL-MVP-068: $Message"
}

function Invoke-Git([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args) {
    $output = & git.exe @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail ("git {0} fallo:`n{1}" -f ($Args -join " "), ($output -join "`n"))
    }
    return @($output)
}

function Write-Utf8Lf([string]$Path, [string]$Content) {
    $full = Join-Path $script:Root $Path
    $directory = Split-Path -Parent $full
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($full, $normalized, $utf8)
    Write-Host "OK: $Path"
}

function Replace-Once(
    [string]$Path,
    [string]$Old,
    [string]$New,
    [string]$Description
) {
    $full = Join-Path $script:Root $Path
    if (-not (Test-Path $full -PathType Leaf)) {
        Fail "no existe $Path"
    }

    $text = [System.IO.File]::ReadAllText($full)
    $first = $text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        Fail "no se encontro bloque esperado para $Description en $Path"
    }

    $second = $text.IndexOf(
        $Old,
        $first + $Old.Length,
        [System.StringComparison]::Ordinal
    )
    if ($second -ge 0) {
        Fail "el bloque para $Description aparece mas de una vez en $Path"
    }

    $updated = $text.Substring(0, $first) + $New + $text.Substring($first + $Old.Length)
    Write-Utf8Lf $Path $updated
}

$script:Root = (Resolve-Path $RepoRoot).Path
Set-Location $script:Root

$gitRoot = ([string]((Invoke-Git rev-parse --show-toplevel) | Select-Object -First 1)).Trim()
if ([System.IO.Path]::GetFullPath($gitRoot) -ne [System.IO.Path]::GetFullPath($script:Root)) {
    Fail "RepoRoot no coincide con la raiz real de Git."
}

$branch = ([string]((Invoke-Git branch --show-current) | Select-Object -First 1)).Trim()
if ($branch -ne $ExpectedBranch) {
    Fail "se esperaba rama $ExpectedBranch y se obtuvo $branch."
}

$head = ([string]((Invoke-Git rev-parse HEAD) | Select-Object -First 1)).Trim()
if ($head -ne $ExpectedHead) {
    Fail "HEAD inesperado. Se esperaba $ExpectedHead y se obtuvo $head."
}

$selfRelative = "scripts/apply-bl-mvp-068-contextual-analysis-panel.ps1"
$status = @(Invoke-Git status --porcelain=v1 --untracked-files=all)
$unexpected = @(
    $status | Where-Object {
        $line = $_.ToString()
        -not ($line -eq "?? $selfRelative" -or $line -eq "?? `"${selfRelative}`"")
    }
)
if ($unexpected.Count -gt 0) {
    Fail ("el worktree debe estar limpio salvo este instalador temporal:`n{0}" -f ($unexpected -join "`n"))
}

$newFiles = @(
    "src/Modules/Content/Infrastructure/PublicPlayback/PublicAnalysisTokenKey.cs",
    "src/Modules/Content/Infrastructure/PublicPlayback/PublicContextualAnalysisService.cs",
    "apps/api/Endpoints/PublicCatalog/PublicContextualAnalysisEndpoints.cs",
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx",
    "apps/web/src/routes/student/contextual-analysis-panel.css",
    "apps/web/src/routes/student/ContextualAnalysisPage.tsx",
    "tests/E2ETests/contextual-analysis-panel.spec.ts",
    "scripts/ci/content/verify-contextual-analysis-panel.sh",
    "README/BL-MVP-068_README.md",
    "docs/engineering/content/contextual-analysis-panel.md"
)

foreach ($path in $newFiles) {
    if (Test-Path (Join-Path $script:Root $path)) {
        Fail "el archivo nuevo ya existe: $path"
    }
}

Write-Host "BL-MVP-068: panel de analisis contextual publico y embebido..."

$tokenKey = @'
using System.Security.Cryptography;
using System.Text;

namespace MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

internal static class PublicAnalysisTokenKey
{
    internal const int Length = 20;
    private const string Salt = ":public-analysis-token-v1";

    internal static string FromTokenId(Guid tokenId)
    {
        if (tokenId == Guid.Empty)
        {
            throw new ArgumentException(
                "El token canónico es obligatorio.",
                nameof(tokenId));
        }

        var payload = Encoding.UTF8.GetBytes($"{tokenId:D}{Salt}");
        return Convert.ToHexString(MD5.HashData(payload))[..Length];
    }

    internal static string Normalize(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length != Length
            || normalized.Any(static character =>
                character is not (>= '0' and <= '9')
                && character is not (>= 'A' and <= 'F')))
        {
            throw new ArgumentException(
                $"La referencia pública de análisis debe contener {Length} caracteres hexadecimales.",
                nameof(value));
        }

        return normalized;
    }
}
'@

$service = @'
using Microsoft.Extensions.Configuration;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

public sealed record PublicContextualReading(
    string ReadingKana,
    string? Furigana,
    string? Romaji,
    string ReadingType);

public sealed record PublicContextualVocabularySense(
    string LanguageTag,
    string Definition,
    string? UsageNote,
    int DisplayOrder);

public sealed record PublicContextualVocabulary(
    string Lemma,
    string? Reading,
    string? PartOfSpeech,
    string SenseKey,
    string? Inflection,
    string ConfidenceCode,
    IReadOnlyList<PublicContextualVocabularySense> Senses);

public sealed record PublicContextualKanjiReading(
    string Reading,
    string ReadingType,
    string LanguageTag,
    string Meaning,
    int DisplayOrder);

public sealed record PublicContextualKanji(
    string Character,
    int CharOffset,
    string? GradeCode,
    string? JlptCode,
    IReadOnlyList<PublicContextualKanjiReading> Readings);

public sealed record PublicContextualMorphology(
    string Lemma,
    string PartOfSpeechCode,
    string? ConjugationCode);

public sealed record PublicContextualGrammar(
    string GrammarCode,
    string Title,
    string? LevelCode,
    string? Note,
    string? Explanation,
    string? Examples);

public sealed record PublicContextualProvenance(
    string SourceType,
    string Citation,
    string? Locator,
    string ContributionType);

public sealed record PublicContextualLine(
    int SectionOrder,
    string? SectionLabel,
    int LineNo,
    string JapaneseText,
    string? SpeakerLabel);

public sealed record PublicContextualAnalysis(
    bool Available,
    string TokenKey,
    string Surface,
    int TokenNo,
    string TargetLanguage,
    PublicContextualLine Line,
    IReadOnlyList<PublicContextualReading> Readings,
    IReadOnlyList<PublicContextualVocabulary> Vocabulary,
    IReadOnlyList<PublicContextualKanji> Kanji,
    IReadOnlyList<PublicContextualMorphology> Morphology,
    IReadOnlyList<PublicContextualGrammar> Grammar,
    IReadOnlyList<PublicContextualProvenance> Provenance);

public sealed class AmbiguousPublicContextualAnalysisException : Exception
{
    public AmbiguousPublicContextualAnalysisException()
        : base("El análisis contextual coincide con más de una publicación o token elegible.")
    {
    }
}

public sealed class IncompatiblePublicContextualAnalysisException : Exception
{
    public IncompatiblePublicContextualAnalysisException()
        : base("La revisión publicada de análisis no pertenece a la letra publicada seleccionada.")
    {
    }
}

public sealed class PublicContextualAnalysisService
{
    private const int PublicSongKeyLength = 20;
    private const int MaximumSlugLength = 160;
    private readonly string _connectionString;

    public PublicContextualAnalysisService(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        _connectionString = configuration.GetConnectionString("PostgreSQL")
            ?? throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para el análisis contextual público.");
    }

    public async Task<PublicContextualAnalysis?> ReadAsync(
        string slug,
        string tokenKey,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken = default)
    {
        var slugKey = ExtractSlugKey(slug);
        var normalizedTokenKey = PublicAnalysisTokenKey.Normalize(tokenKey);
        var normalizedTerritory = NormalizeCode(territoryCode, nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag) ?? "es";

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        var headers = await ReadEligibleHeadersAsync(
            connection,
            slugKey,
            normalizedTerritory,
            normalizedLanguage,
            cancellationToken);

        if (headers.Count == 0)
        {
            return null;
        }

        if (headers.Count > 1)
        {
            throw new AmbiguousPublicContextualAnalysisException();
        }

        var header = headers[0];
        if (header.LyricsRevisionId is not { } lyricsRevisionId
            || header.AnalysisRevisionId is not { } analysisRevisionId)
        {
            return null;
        }

        await EnsureCompatibleAsync(
            connection,
            header.RecordingId,
            lyricsRevisionId,
            analysisRevisionId,
            cancellationToken);

        var token = await ReadTargetTokenAsync(
            connection,
            lyricsRevisionId,
            normalizedTokenKey,
            cancellationToken);

        if (token is null)
        {
            return null;
        }

        var readings = await ReadReadingsAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.TokenId,
            cancellationToken);

        var vocabulary = await ReadVocabularyAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.TokenId,
            normalizedLanguage,
            cancellationToken);

        var kanji = await ReadKanjiAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.TokenId,
            normalizedLanguage,
            cancellationToken);

        var morphology = await ReadMorphologyAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.TokenId,
            cancellationToken);

        var grammar = await ReadGrammarAsync(
            connection,
            analysisRevisionId,
            lyricsRevisionId,
            token.LineId,
            token.TokenNo,
            normalizedLanguage,
            cancellationToken);

        var provenance = await ReadProvenanceAsync(
            connection,
            analysisRevisionId,
            cancellationToken);

        var available = readings.Count > 0
            || vocabulary.Count > 0
            || kanji.Count > 0
            || morphology.Count > 0
            || grammar.Count > 0;

        return new PublicContextualAnalysis(
            available,
            normalizedTokenKey,
            token.Surface,
            token.TokenNo,
            normalizedLanguage,
            new PublicContextualLine(
                token.SectionOrder,
                token.SectionLabel,
                token.LineNo,
                token.JapaneseText,
                token.SpeakerLabel),
            readings,
            vocabulary,
            kanji,
            morphology,
            grammar,
            provenance);
    }

    private static async Task<List<EligibleHeader>> ReadEligibleHeadersAsync(
        NpgsqlConnection connection,
        string slugKey,
        string territoryCode,
        string languageTag,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                recording.recording_id,
                lyrics_component.lyrics_revision_id,
                analysis_component.analysis_revision_id
            FROM editorial.published_package_projection AS projection
            INNER JOIN editorial.publication AS publication
                ON publication.publication_id = projection.publication_id
               AND publication.recording_id = projection.recording_id
            INNER JOIN catalog.recording AS recording
                ON recording.recording_id = publication.recording_id
            INNER JOIN catalog.recording_source AS source
                ON source.source_id = NULLIF(
                    projection.component_versions #>> '{source,sourceId}',
                    ''
                )::uuid
               AND source.recording_id = recording.recording_id
               AND source.provider_code =
                    projection.component_versions #>> '{source,providerCode}'
               AND source.external_ref =
                    projection.component_versions #>> '{source,externalRef}'
               AND source.version = NULLIF(
                    projection.component_versions #>> '{source,version}',
                    ''
                )::bigint
            INNER JOIN LATERAL (
                SELECT
                    availability_row.territory_code,
                    availability_row.language_tag
                FROM editorial.publication_availability AS availability_row
                WHERE availability_row.publication_id = publication.publication_id
                  AND availability_row.territory_code = @territory_code
                  AND availability_row.audience_code = 'PUBLIC'
                  AND availability_row.status_code = 'ACTIVE'
                  AND availability_row.valid_from <= CURRENT_TIMESTAMP
                  AND (
                      availability_row.valid_to IS NULL
                      OR availability_row.valid_to > CURRENT_TIMESTAMP
                  )
                  AND (
                      availability_row.language_tag IS NULL
                      OR lower(availability_row.language_tag) = lower(@language_tag)
                  )
                ORDER BY
                    CASE
                        WHEN availability_row.language_tag IS NOT NULL
                             AND lower(availability_row.language_tag) = lower(@language_tag)
                        THEN 0
                        ELSE 1
                    END,
                    availability_row.valid_from DESC,
                    availability_row.availability_id
                LIMIT 1
            ) AS availability ON true
            LEFT JOIN LATERAL (
                SELECT package_component.lyrics_revision_id
                FROM editorial.publication_component AS published_component
                INNER JOIN editorial.package_component AS package_component
                    ON package_component.package_component_id =
                         published_component.source_component_id
                   AND package_component.package_id = publication.package_id
                   AND package_component.component_kind = 'LYRICS'
                WHERE published_component.publication_id = publication.publication_id
                  AND published_component.component_kind = 'LYRICS'
                  AND package_component.lyrics_revision_id IS NOT NULL
                ORDER BY
                    published_component.display_order,
                    published_component.publication_component_id
                LIMIT 1
            ) AS lyrics_component ON true
            LEFT JOIN LATERAL (
                SELECT package_component.analysis_revision_id
                FROM editorial.publication_component AS published_component
                INNER JOIN editorial.package_component AS package_component
                    ON package_component.package_component_id =
                         published_component.source_component_id
                   AND package_component.package_id = publication.package_id
                   AND package_component.component_kind = 'ANALYSIS'
                WHERE published_component.publication_id = publication.publication_id
                  AND published_component.component_kind = 'ANALYSIS'
                  AND package_component.analysis_revision_id IS NOT NULL
                ORDER BY
                    published_component.display_order,
                    published_component.publication_component_id
                LIMIT 1
            ) AS analysis_component ON true
            WHERE upper(
                      substring(
                          md5(recording.recording_id::text || ':public-song-v1')
                          from 1 for 20
                      )
                  ) = @slug_key
              AND publication.status_code = 'ACTIVE'
              AND publication.active_from <= CURRENT_TIMESTAMP
              AND (
                  publication.active_to IS NULL
                  OR publication.active_to > CURRENT_TIMESTAMP
              )
              AND source.provider_code = 'YOUTUBE'
              AND source.status_code IN ('ACTIVE', 'PUBLISHED')
              AND source.external_ref ~ '^[A-Za-z0-9_-]{11}$'
            ORDER BY publication.active_from DESC, publication.publication_no DESC
            LIMIT 2;
            """;

        var result = new List<EligibleHeader>(2);

        await using var command = new NpgsqlCommand(sql, connection)
        {
            CommandTimeout = 15
        };

        command.Parameters.AddWithValue("slug_key", NpgsqlDbType.Varchar, slugKey);
        command.Parameters.AddWithValue(
            "territory_code",
            NpgsqlDbType.Varchar,
            territoryCode);
        command.Parameters.AddWithValue(
            "language_tag",
            NpgsqlDbType.Varchar,
            languageTag);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new EligibleHeader(
                    reader.GetGuid(0),
                    reader.IsDBNull(1) ? null : reader.GetGuid(1),
                    reader.IsDBNull(2) ? null : reader.GetGuid(2)));
        }

        return result;
    }

    private static async Task EnsureCompatibleAsync(
        NpgsqlConnection connection,
        Guid recordingId,
        Guid lyricsRevisionId,
        Guid analysisRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                EXISTS (
                    SELECT 1
                    FROM content.lyrics_revision AS lyrics
                    WHERE lyrics.lyrics_revision_id = @lyrics_revision_id
                      AND lyrics.recording_id = @recording_id
                ),
                EXISTS (
                    SELECT 1
                    FROM content.linguistic_analysis_revision AS analysis
                    WHERE analysis.analysis_revision_id = @analysis_revision_id
                      AND analysis.lyrics_revision_id = @lyrics_revision_id
                );
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)
            || !reader.GetBoolean(0)
            || !reader.GetBoolean(1))
        {
            throw new IncompatiblePublicContextualAnalysisException();
        }
    }

    private static async Task<TargetToken?> ReadTargetTokenAsync(
        NpgsqlConnection connection,
        Guid lyricsRevisionId,
        string tokenKey,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                section.display_order,
                section.label,
                line.line_id,
                line.line_no,
                line.japanese_text,
                line.speaker_label,
                token.token_id,
                token.token_no,
                token.surface
            FROM content.lyric_section AS section
            INNER JOIN content.lyric_line AS line
                ON line.section_id = section.section_id
            INNER JOIN content.lyric_token AS token
                ON token.line_id = line.line_id
            WHERE section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                section.display_order,
                section.section_id,
                line.line_no,
                line.line_id,
                token.token_no,
                token.token_id;
            """;

        TargetToken? match = null;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var tokenId = reader.GetGuid(6);
            if (!string.Equals(
                    PublicAnalysisTokenKey.FromTokenId(tokenId),
                    tokenKey,
                    StringComparison.Ordinal))
            {
                continue;
            }

            if (match is not null)
            {
                throw new AmbiguousPublicContextualAnalysisException();
            }

            match = new TargetToken(
                reader.GetInt32(0),
                reader.IsDBNull(1) ? null : reader.GetString(1),
                reader.GetGuid(2),
                reader.GetInt32(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                tokenId,
                reader.GetInt32(7),
                reader.GetString(8));
        }

        return match;
    }

    private static async Task<List<PublicContextualReading>> ReadReadingsAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                reading.reading_kana,
                reading.furigana,
                reading.romaji,
                reading.reading_type
            FROM content.token_reading AS reading
            INNER JOIN content.lyric_token AS token
                ON token.token_id = reading.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            WHERE reading.analysis_revision_id = @analysis_revision_id
              AND reading.token_id = @token_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                CASE upper(reading.reading_type)
                    WHEN 'PRIMARY' THEN 0
                    WHEN 'CONTEXTUAL' THEN 1
                    ELSE 2
                END,
                reading.reading_type,
                reading.token_reading_id;
            """;

        var result = new List<PublicContextualReading>();

        await using var command = new NpgsqlCommand(sql, connection);
        AddAnalysisTokenParameters(
            command,
            analysisRevisionId,
            lyricsRevisionId,
            tokenId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new PublicContextualReading(
                    reader.GetString(0),
                    reader.IsDBNull(1) ? null : reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3)));
        }

        return result;
    }

    private static async Task<List<PublicContextualVocabulary>> ReadVocabularyAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId,
        string language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                occurrence.occurrence_id,
                entry.lemma,
                entry.reading,
                entry.part_of_speech,
                entry.sense_key,
                occurrence.inflection,
                occurrence.confidence_code,
                sense.language_tag,
                sense.definition,
                sense.usage_note,
                sense.display_order
            FROM content.vocabulary_occurrence AS occurrence
            INNER JOIN content.lyric_token AS token
                ON token.token_id = occurrence.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            INNER JOIN content.vocabulary_entry AS entry
                ON entry.vocabulary_id = occurrence.vocabulary_id
            LEFT JOIN content.vocabulary_sense AS sense
                ON sense.vocabulary_id = entry.vocabulary_id
               AND lower(sense.language_tag) = lower(@language)
            WHERE occurrence.analysis_revision_id = @analysis_revision_id
              AND occurrence.token_id = @token_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                occurrence.occurrence_id,
                sense.display_order,
                sense.sense_id;
            """;

        var builders = new Dictionary<Guid, VocabularyBuilder>();
        var order = new List<Guid>();

        await using var command = new NpgsqlCommand(sql, connection);
        AddAnalysisTokenParameters(
            command,
            analysisRevisionId,
            lyricsRevisionId,
            tokenId);
        command.Parameters.AddWithValue("language", NpgsqlDbType.Varchar, language);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var occurrenceId = reader.GetGuid(0);
            if (!builders.TryGetValue(occurrenceId, out var builder))
            {
                builder = new VocabularyBuilder(
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetString(5),
                    reader.GetString(6));
                builders.Add(occurrenceId, builder);
                order.Add(occurrenceId);
            }

            if (!reader.IsDBNull(7))
            {
                builder.Senses.Add(
                    new PublicContextualVocabularySense(
                        reader.GetString(7),
                        reader.GetString(8),
                        reader.IsDBNull(9) ? null : reader.GetString(9),
                        reader.GetInt32(10)));
            }
        }

        return order.Select(id => builders[id].Build()).ToList();
    }

    private static async Task<List<PublicContextualKanji>> ReadKanjiAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId,
        string language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                occurrence.occurrence_id,
                entry.character,
                occurrence.char_offset,
                entry.grade_code,
                entry.jlpt_code,
                reading.reading,
                reading.reading_type,
                reading.language_tag,
                reading.meaning,
                reading.display_order
            FROM content.kanji_occurrence AS occurrence
            INNER JOIN content.lyric_token AS token
                ON token.token_id = occurrence.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            INNER JOIN content.kanji_entry AS entry
                ON entry.kanji_id = occurrence.kanji_id
            LEFT JOIN content.kanji_reading AS reading
                ON reading.kanji_id = entry.kanji_id
               AND lower(reading.language_tag) = lower(@language)
            WHERE occurrence.analysis_revision_id = @analysis_revision_id
              AND occurrence.token_id = @token_id
              AND section.lyrics_revision_id = @lyrics_revision_id
              AND substring(
                    token.surface
                    FROM occurrence.char_offset + 1
                    FOR char_length(entry.character)
                  ) = entry.character
            ORDER BY
                occurrence.char_offset,
                occurrence.occurrence_id,
                reading.display_order,
                reading.kanji_reading_id;
            """;

        var builders = new Dictionary<Guid, KanjiBuilder>();
        var order = new List<Guid>();

        await using var command = new NpgsqlCommand(sql, connection);
        AddAnalysisTokenParameters(
            command,
            analysisRevisionId,
            lyricsRevisionId,
            tokenId);
        command.Parameters.AddWithValue("language", NpgsqlDbType.Varchar, language);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var occurrenceId = reader.GetGuid(0);
            if (!builders.TryGetValue(occurrenceId, out var builder))
            {
                builder = new KanjiBuilder(
                    reader.GetString(1),
                    reader.GetInt32(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4));
                builders.Add(occurrenceId, builder);
                order.Add(occurrenceId);
            }

            if (!reader.IsDBNull(5))
            {
                builder.Readings.Add(
                    new PublicContextualKanjiReading(
                        reader.GetString(5),
                        reader.GetString(6),
                        reader.GetString(7),
                        reader.GetString(8),
                        reader.GetInt32(9)));
            }
        }

        return order.Select(id => builders[id].Build()).ToList();
    }

    private static async Task<List<PublicContextualMorphology>> ReadMorphologyAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                annotation.lemma,
                annotation.pos_code,
                annotation.conjugation_code
            FROM content.morphology_annotation AS annotation
            INNER JOIN content.lyric_token AS token
                ON token.token_id = annotation.token_id
            INNER JOIN content.lyric_line AS line
                ON line.line_id = token.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            WHERE annotation.analysis_revision_id = @analysis_revision_id
              AND annotation.token_id = @token_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY annotation.annotation_id;
            """;

        var result = new List<PublicContextualMorphology>();

        await using var command = new NpgsqlCommand(sql, connection);
        AddAnalysisTokenParameters(
            command,
            analysisRevisionId,
            lyricsRevisionId,
            tokenId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new PublicContextualMorphology(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2)));
        }

        return result;
    }

    private static async Task<List<PublicContextualGrammar>> ReadGrammarAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid lineId,
        int tokenNo,
        string language,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                point.grammar_code,
                point.title,
                point.level_code,
                occurrence.note,
                explanation.explanation,
                explanation.examples
            FROM content.grammar_occurrence AS occurrence
            INNER JOIN content.lyric_line AS line
                ON line.line_id = occurrence.line_id
            INNER JOIN content.lyric_section AS section
                ON section.section_id = line.section_id
            INNER JOIN content.grammar_point AS point
                ON point.grammar_point_id = occurrence.grammar_point_id
            LEFT JOIN content.lyric_token AS start_token
                ON start_token.token_id = occurrence.start_token_id
               AND start_token.line_id = occurrence.line_id
            LEFT JOIN content.lyric_token AS end_token
                ON end_token.token_id = occurrence.end_token_id
               AND end_token.line_id = occurrence.line_id
            LEFT JOIN LATERAL (
                SELECT
                    item.explanation,
                    item.examples
                FROM content.grammar_explanation AS item
                WHERE item.grammar_point_id = point.grammar_point_id
                  AND lower(item.language_tag) = lower(@language)
                ORDER BY item.revision_no DESC, item.explanation_id DESC
                LIMIT 1
            ) AS explanation ON true
            WHERE occurrence.analysis_revision_id = @analysis_revision_id
              AND occurrence.line_id = @line_id
              AND section.lyrics_revision_id = @lyrics_revision_id
              AND (
                    occurrence.start_token_id IS NULL
                    OR start_token.token_no <= @token_no
                  )
              AND (
                    occurrence.end_token_id IS NULL
                    OR end_token.token_no >= @token_no
                  )
            ORDER BY occurrence.occurrence_id;
            """;

        var result = new List<PublicContextualGrammar>();

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue("line_id", NpgsqlDbType.Uuid, lineId);
        command.Parameters.AddWithValue("token_no", NpgsqlDbType.Integer, tokenNo);
        command.Parameters.AddWithValue("language", NpgsqlDbType.Varchar, language);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new PublicContextualGrammar(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetString(5)));
        }

        return result;
    }

    private static async Task<List<PublicContextualProvenance>> ReadProvenanceAsync(
        NpgsqlConnection connection,
        Guid analysisRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                source.source_type,
                source.citation,
                source.locator,
                provenance.contribution_type
            FROM editorial.provenance_record AS provenance
            INNER JOIN catalog.source_reference AS source
                ON source.source_reference_id = provenance.source_reference_id
            WHERE provenance.object_type = 'LINGUISTIC_ANALYSIS_REVISION'
              AND provenance.object_id = @analysis_revision_id
            ORDER BY
                provenance.recorded_at,
                provenance.provenance_id;
            """;

        var result = new List<PublicContextualProvenance>();

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(
                new PublicContextualProvenance(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3)));
        }

        return result;
    }

    private static void AddAnalysisTokenParameters(
        NpgsqlCommand command,
        Guid analysisRevisionId,
        Guid lyricsRevisionId,
        Guid tokenId)
    {
        command.Parameters.AddWithValue(
            "analysis_revision_id",
            NpgsqlDbType.Uuid,
            analysisRevisionId);
        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue("token_id", NpgsqlDbType.Uuid, tokenId);
    }

    private static string ExtractSlugKey(string slug)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(slug);

        var normalized = slug.Trim();
        if (normalized.Length > MaximumSlugLength)
        {
            throw new ArgumentException(
                $"El slug no puede superar {MaximumSlugLength} caracteres.",
                nameof(slug));
        }

        var separator = normalized.LastIndexOf('-');
        if (separator <= 0 || separator == normalized.Length - 1)
        {
            throw new ArgumentException(
                "El slug público no tiene el formato esperado.",
                nameof(slug));
        }

        var key = normalized[(separator + 1)..].ToUpperInvariant();
        if (key.Length != PublicSongKeyLength
            || key.Any(static character =>
                character is not (>= '0' and <= '9')
                && character is not (>= 'A' and <= 'F')))
        {
            throw new ArgumentException(
                $"La clave pública debe contener {PublicSongKeyLength} caracteres hexadecimales.",
                nameof(slug));
        }

        return key;
    }

    private static string NormalizeCode(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length is < 1 or > 64
            || !IsUpperAsciiLetterOrDigit(normalized[0]))
        {
            throw new ArgumentException(
                "El código debe usar formato [A-Z0-9][A-Z0-9._-]*.",
                parameterName);
        }

        for (var index = 1; index < normalized.Length; index++)
        {
            var character = normalized[index];
            if (!(IsUpperAsciiLetterOrDigit(character)
                  || character is '.' or '_' or '-'))
            {
                throw new ArgumentException(
                    "El código debe usar formato [A-Z0-9][A-Z0-9._-]*.",
                    parameterName);
            }
        }

        return normalized;
    }

    private static string? NormalizeLanguageTag(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = value.Trim();
        if (normalized.Length > 35)
        {
            throw new ArgumentException(
                "La etiqueta de idioma excede 35 caracteres.",
                nameof(value));
        }

        var parts = normalized.Split('-', StringSplitOptions.None);
        if (parts.Length == 0
            || parts[0].Length is < 2 or > 8
            || !parts[0].All(char.IsAsciiLetter))
        {
            throw new ArgumentException(
                "La etiqueta de idioma no cumple el formato BCP-47 mínimo esperado.",
                nameof(value));
        }

        foreach (var part in parts.Skip(1))
        {
            if (part.Length is < 1 or > 8
                || !part.All(char.IsAsciiLetterOrDigit))
            {
                throw new ArgumentException(
                    "La etiqueta de idioma no cumple el formato BCP-47 mínimo esperado.",
                    nameof(value));
            }
        }

        return normalized;
    }

    private static bool IsUpperAsciiLetterOrDigit(char character) =>
        character is >= 'A' and <= 'Z' || char.IsAsciiDigit(character);

    private sealed record EligibleHeader(
        Guid RecordingId,
        Guid? LyricsRevisionId,
        Guid? AnalysisRevisionId);

    private sealed record TargetToken(
        int SectionOrder,
        string? SectionLabel,
        Guid LineId,
        int LineNo,
        string JapaneseText,
        string? SpeakerLabel,
        Guid TokenId,
        int TokenNo,
        string Surface);

    private sealed class VocabularyBuilder(
        string lemma,
        string? reading,
        string? partOfSpeech,
        string senseKey,
        string? inflection,
        string confidenceCode)
    {
        public List<PublicContextualVocabularySense> Senses { get; } = [];

        public PublicContextualVocabulary Build() =>
            new(
                lemma,
                reading,
                partOfSpeech,
                senseKey,
                inflection,
                confidenceCode,
                Senses);
    }

    private sealed class KanjiBuilder(
        string character,
        int charOffset,
        string? gradeCode,
        string? jlptCode)
    {
        public List<PublicContextualKanjiReading> Readings { get; } = [];

        public PublicContextualKanji Build() =>
            new(
                character,
                charOffset,
                gradeCode,
                jlptCode,
                Readings);
    }
}
'@

$endpoint = @'
using MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

namespace MusicaAprender.Api.Endpoints.PublicCatalog;

public static class PublicContextualAnalysisEndpoints
{
    public static IEndpointRouteBuilder MapPublicContextualAnalysis(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/public/catalog/songs/{slug}/analysis/{token}",
            ReadAsync);

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        string slug,
        string token,
        string? territory,
        string? language,
        PublicContextualAnalysisService service,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        httpContext.Response.Headers["Cache-Control"] = "no-store";

        try
        {
            var analysis = await service.ReadAsync(
                slug,
                token,
                territory ?? string.Empty,
                language,
                cancellationToken);

            return analysis is null
                ? Results.NotFound()
                : Results.Ok(analysis);
        }
        catch (AmbiguousPublicContextualAnalysisException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Análisis contextual no disponible de forma segura",
                detail:
                    "La publicación o el token no puede resolverse de forma unívoca. No se mezclará otro análisis.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-analysis.ambiguous"
                });
        }
        catch (IncompatiblePublicContextualAnalysisException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Análisis contextual incompatible",
                detail:
                    "El análisis publicado no corresponde a la revisión japonesa activa. Se conserva un estado seguro.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-analysis.incompatible"
                });
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Ruta de análisis contextual inválida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-analysis.invalid-route"
                });
        }
    }
}
'@

$panel = @'
import { useEffect, useMemo, useState } from 'react';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import { romanizeApprovedReading } from '../editorial/ContextualReading';
import './contextual-analysis-panel.css';

const client = createHttpClient();
const territory = 'CR';
const language = 'es';

export type PublicContextualReading = {
  readingKana: string;
  furigana: string | null;
  romaji: string | null;
  readingType: string;
};

type PublicContextualVocabularySense = {
  languageTag: string;
  definition: string;
  usageNote: string | null;
  displayOrder: number;
};

type PublicContextualVocabulary = {
  lemma: string;
  reading: string | null;
  partOfSpeech: string | null;
  senseKey: string;
  inflection: string | null;
  confidenceCode: string;
  senses: PublicContextualVocabularySense[];
};

type PublicContextualKanjiReading = {
  reading: string;
  readingType: string;
  languageTag: string;
  meaning: string;
  displayOrder: number;
};

type PublicContextualKanji = {
  character: string;
  charOffset: number;
  gradeCode: string | null;
  jlptCode: string | null;
  readings: PublicContextualKanjiReading[];
};

type PublicContextualMorphology = {
  lemma: string;
  partOfSpeechCode: string;
  conjugationCode: string | null;
};

type PublicContextualGrammar = {
  grammarCode: string;
  title: string;
  levelCode: string | null;
  note: string | null;
  explanation: string | null;
  examples: string | null;
};

type PublicContextualProvenance = {
  sourceType: string;
  citation: string;
  locator: string | null;
  contributionType: string;
};

type PublicContextualLine = {
  sectionOrder: number;
  sectionLabel: string | null;
  lineNo: number;
  japaneseText: string;
  speakerLabel: string | null;
};

export type PublicContextualAnalysis = {
  available: boolean;
  tokenKey: string;
  surface: string;
  tokenNo: number;
  targetLanguage: string;
  line: PublicContextualLine;
  readings: PublicContextualReading[];
  vocabulary: PublicContextualVocabulary[];
  kanji: PublicContextualKanji[];
  morphology: PublicContextualMorphology[];
  grammar: PublicContextualGrammar[];
  provenance: PublicContextualProvenance[];
};

type AnalysisState =
  | { phase: 'idle' }
  | { phase: 'loading' }
  | { phase: 'ready'; data: PublicContextualAnalysis }
  | { phase: 'unavailable' }
  | { phase: 'failed'; problem: ClientProblem };

export type ContextualAnalysisPanelProps = {
  slug: string;
  tokenKey: string | null;
  surfaceHint?: string | null;
  onClose?: () => void;
  showStandaloneLink?: boolean;
};

function readingRank(readingType: string) {
  const normalized = readingType.toUpperCase();
  if (normalized === 'PRIMARY') return 0;
  if (normalized === 'CONTEXTUAL') return 1;
  return 2;
}

function orderedReadings(readings: PublicContextualReading[]) {
  return [...readings].sort(
    (left, right) =>
      readingRank(left.readingType) - readingRank(right.readingType) ||
      left.readingType.localeCompare(right.readingType) ||
      left.readingKana.localeCompare(right.readingKana),
  );
}

function romaji(reading: PublicContextualReading) {
  return reading.romaji?.trim() || romanizeApprovedReading(reading.readingKana);
}

function humanCode(value: string | null) {
  return value?.replaceAll('_', ' ') ?? 'No disponible';
}

function EmptyDetail({ children }: { children: string }) {
  return <p className="contextual-analysis__empty">{children}</p>;
}

export function ContextualAnalysisPanel({
  slug,
  tokenKey,
  surfaceHint,
  onClose,
  showStandaloneLink = true,
}: ContextualAnalysisPanelProps) {
  const [state, setState] = useState<AnalysisState>({ phase: 'idle' });

  useEffect(() => {
    if (!tokenKey) {
      setState({ phase: 'idle' });
      return;
    }

    const controller = new AbortController();
    setState({ phase: 'loading' });

    const load = async () => {
      const params = new URLSearchParams({ territory, language });
      const result = await client.get<PublicContextualAnalysis>(
        `/public/catalog/songs/${encodeURIComponent(slug)}/analysis/${encodeURIComponent(tokenKey)}?${params.toString()}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') return;

      if (!result.ok) {
        setState(
          result.problem.status === 404
            ? { phase: 'unavailable' }
            : { phase: 'failed', problem: result.problem },
        );
        return;
      }

      setState({ phase: 'ready', data: result.data });
    };

    void load();
    return () => controller.abort();
  }, [slug, tokenKey]);

  const readings = useMemo(
    () => (state.phase === 'ready' ? orderedReadings(state.data.readings) : []),
    [state],
  );

  return (
    <aside
      className="contextual-analysis"
      id="contextual-analysis-panel"
      aria-labelledby="contextual-analysis-title"
      data-contextual-analysis-panel
    >
      <header className="contextual-analysis__header">
        <div>
          <p className="eyebrow">BL-MVP-068 · ANÁLISIS CONTEXTUAL</p>
          <h2 id="contextual-analysis-title">Comprende esta parte</h2>
          <p>
            Lectura, significado, forma, kanji y gramática proceden del análisis publicado compatible
            con esta letra.
          </p>
        </div>
        {onClose && tokenKey ? (
          <button type="button" className="contextual-analysis__close" onClick={onClose}>
            Cerrar análisis
          </button>
        ) : null}
      </header>

      {state.phase === 'idle' ? (
        <div className="contextual-analysis__prompt">
          <strong>Selecciona una palabra de la letra.</strong>
          <span>
            El video puede seguir reproduciéndose mientras consultas el análisis. No se enviará texto
            a diccionarios ni servicios externos.
          </span>
        </div>
      ) : null}

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title={`Preparando ${surfaceHint?.trim() || 'el análisis'}`}
          description="Resolviendo el token dentro de la misma revisión publicada."
        />
      ) : null}

      {state.phase === 'unavailable' ? (
        <StateMessage
          state="UI-EST-06"
          title="Análisis no disponible"
          description="Este token ya no pertenece a la publicación activa o no tiene análisis compatible. No se sustituye por otro."
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          state="UI-EST-06"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      ) : null}

      {state.phase === 'ready' ? (
        <>
          <section className="contextual-analysis__selection" aria-labelledby="analysis-selection">
            <p className="eyebrow">
              {state.data.line.sectionLabel?.trim() ||
                `Sección ${state.data.line.sectionOrder + 1}`}{' '}
              · línea {state.data.line.lineNo}
            </p>
            <h3 id="analysis-selection" lang="ja">
              {state.data.surface}
            </h3>
            <p lang="ja">{state.data.line.japaneseText}</p>

            {readings.length === 0 ? (
              <EmptyDetail>Sin lectura contextual publicada para este token.</EmptyDetail>
            ) : readings.length === 1 ? (
              <dl className="contextual-analysis__facts">
                <div>
                  <dt>Lectura contextual</dt>
                  <dd lang="ja">{readings[0]!.readingKana}</dd>
                </div>
                <div>
                  <dt>Romaji</dt>
                  <dd>{romaji(readings[0]!)}</dd>
                </div>
              </dl>
            ) : (
              <div className="contextual-analysis__alternatives">
                <strong>Lectura ambigua: se conservan las alternativas.</strong>
                <ul>
                  {readings.map((reading) => (
                    <li key={`${reading.readingType}-${reading.readingKana}`}>
                      <span lang="ja">{reading.readingKana}</span> · {romaji(reading)} ·{' '}
                      {humanCode(reading.readingType)}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </section>

          {!state.data.available ? (
            <StateMessage
              state="UI-EST-12"
              title="Sin detalle lingüístico adicional"
              description="El token es válido y pertenece a la publicación, pero todavía no tiene vocabulario, kanji, morfología o gramática autorizados."
            />
          ) : null}

          <section className="contextual-analysis__section" aria-labelledby="analysis-vocabulary">
            <h3 id="analysis-vocabulary">Vocabulario y significado</h3>
            {state.data.vocabulary.length === 0 ? (
              <EmptyDetail>Sin entrada de vocabulario para este token.</EmptyDetail>
            ) : (
              state.data.vocabulary.map((item, index) => {
                const firstSense = item.senses[0] ?? null;
                return (
                  <article
                    className="contextual-analysis__card"
                    key={`${item.lemma}-${item.senseKey}-${index}`}
                  >
                    <h4 lang="ja">{item.lemma}</h4>
                    {firstSense ? (
                      <>
                        <p className="contextual-analysis__context-meaning">
                          <strong>Significado en esta canción:</strong> {firstSense.definition}
                        </p>
                        {firstSense.usageNote ? <p>{firstSense.usageNote}</p> : null}
                      </>
                    ) : (
                      <EmptyDetail>Sin glosa localizada publicada.</EmptyDetail>
                    )}
                    <dl className="contextual-analysis__facts">
                      <div>
                        <dt>Lectura</dt>
                        <dd lang="ja">{item.reading ?? 'No disponible'}</dd>
                      </div>
                      <div>
                        <dt>Clase</dt>
                        <dd>{humanCode(item.partOfSpeech)}</dd>
                      </div>
                      <div>
                        <dt>Forma en contexto</dt>
                        <dd>{item.inflection ?? 'Forma base o no especificada'}</dd>
                      </div>
                    </dl>
                    {item.senses.length > 1 ? (
                      <details>
                        <summary>Ver definiciones adicionales publicadas</summary>
                        <ul>
                          {item.senses.slice(1).map((sense) => (
                            <li key={`${sense.displayOrder}-${sense.definition}`}>
                              {sense.definition}
                              {sense.usageNote ? ` — ${sense.usageNote}` : ''}
                            </li>
                          ))}
                        </ul>
                      </details>
                    ) : null}
                  </article>
                );
              })
            )}
          </section>

          <details className="contextual-analysis__details">
            <summary>Morfología y conjugación</summary>
            {state.data.morphology.length === 0 ? (
              <EmptyDetail>Sin análisis morfológico para este token.</EmptyDetail>
            ) : (
              <div className="contextual-analysis__grid">
                {state.data.morphology.map((item, index) => (
                  <dl className="contextual-analysis__facts" key={`${item.lemma}-${index}`}>
                    <div>
                      <dt>Lema</dt>
                      <dd lang="ja">{item.lemma}</dd>
                    </div>
                    <div>
                      <dt>Clase</dt>
                      <dd>{humanCode(item.partOfSpeechCode)}</dd>
                    </div>
                    <div>
                      <dt>Conjugación</dt>
                      <dd>{humanCode(item.conjugationCode)}</dd>
                    </div>
                  </dl>
                ))}
              </div>
            )}
          </details>

          <details className="contextual-analysis__details">
            <summary>Kanji</summary>
            {state.data.kanji.length === 0 ? (
              <EmptyDetail>Sin ficha de kanji asociada a este token.</EmptyDetail>
            ) : (
              <div className="contextual-analysis__kanji-grid">
                {state.data.kanji.map((item) => (
                  <article className="contextual-analysis__kanji" key={`${item.character}-${item.charOffset}`}>
                    <h3 lang="ja">{item.character}</h3>
                    {item.readings.length > 0 ? (
                      <ul>
                        {item.readings.map((reading) => (
                          <li key={`${reading.readingType}-${reading.reading}-${reading.meaning}`}>
                            <span lang="ja">{reading.reading}</span> · {reading.meaning} ·{' '}
                            {humanCode(reading.readingType)}
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <EmptyDetail>Sin lectura general localizada publicada.</EmptyDetail>
                    )}
                    <p>
                      {item.jlptCode
                        ? `JLPT ${item.jlptCode} · nivel orientativo, no certificación oficial.`
                        : 'JLPT no disponible.'}
                    </p>
                    {item.gradeCode ? <p>Grado escolar {item.gradeCode} · orientativo.</p> : null}
                  </article>
                ))}
              </div>
            )}
          </details>

          <details className="contextual-analysis__details">
            <summary>Gramática de esta línea</summary>
            {state.data.grammar.length === 0 ? (
              <EmptyDetail>Sin construcción gramatical asociada a este token.</EmptyDetail>
            ) : (
              state.data.grammar.map((item) => (
                <article className="contextual-analysis__card" key={item.grammarCode}>
                  <h4>{item.title}</h4>
                  <p>
                    <code>{item.grammarCode}</code>
                    {item.levelCode
                      ? ` · ${item.levelCode} orientativo, no certificación oficial.`
                      : ''}
                  </p>
                  {item.explanation ? <p>{item.explanation}</p> : null}
                  {item.note ? <p>{item.note}</p> : null}
                  {item.examples ? (
                    <details>
                      <summary>Ver ejemplos publicados</summary>
                      <p>{item.examples}</p>
                    </details>
                  ) : null}
                </article>
              ))
            )}
          </details>

          <details className="contextual-analysis__details">
            <summary>Procedencia</summary>
            {state.data.provenance.length === 0 ? (
              <EmptyDetail>Sin referencia pública adicional para mostrar.</EmptyDetail>
            ) : (
              <ul className="contextual-analysis__provenance">
                {state.data.provenance.map((item, index) => (
                  <li key={`${item.sourceType}-${item.citation}-${index}`}>
                    <strong>{humanCode(item.sourceType)}:</strong> {item.citation}
                    {item.locator ? ` · ${item.locator}` : ''}
                  </li>
                ))}
              </ul>
            )}
          </details>

          {showStandaloneLink ? (
            <AppLink
              href={`/aprender/${encodeURIComponent(slug)}/analisis/${encodeURIComponent(state.data.tokenKey)}`}
            >
              Abrir análisis en una vista independiente
            </AppLink>
          ) : null}
        </>
      ) : null}
    </aside>
  );
}
'@

$panelCss = @'
.contextual-analysis {
  display: grid;
  align-content: start;
  gap: var(--ma-space-4);
  min-inline-size: 0;
  padding: var(--ma-space-5);
  border: var(--ma-border-width-thin) solid var(--ma-color-border);
  border-radius: var(--ma-radius-panel);
  background: var(--ma-color-surface);
}

.contextual-analysis__header {
  display: flex;
  flex-wrap: wrap;
  gap: var(--ma-space-3);
  align-items: start;
  justify-content: space-between;
}

.contextual-analysis__header > div {
  display: grid;
  gap: var(--ma-space-2);
  min-inline-size: 0;
}

.contextual-analysis__header h2,
.contextual-analysis__header p,
.contextual-analysis__selection p,
.contextual-analysis__card p,
.contextual-analysis__kanji p {
  margin: 0;
}

.contextual-analysis__close {
  min-block-size: 2.75rem;
}

.contextual-analysis__prompt,
.contextual-analysis__empty,
.contextual-analysis__alternatives {
  display: grid;
  gap: var(--ma-space-2);
  padding: var(--ma-space-3);
  border: var(--ma-border-width-thin) dashed var(--ma-color-border);
  border-radius: var(--ma-radius-control);
}

.contextual-analysis__selection,
.contextual-analysis__section {
  display: grid;
  gap: var(--ma-space-3);
}

.contextual-analysis__selection h3 {
  margin: 0;
  overflow-wrap: anywhere;
  font-family: var(--ma-font-japanese);
  font-size: clamp(1.8rem, 1.4rem + 2vw, 2.8rem);
}

.contextual-analysis__facts {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: var(--ma-space-2);
  margin: 0;
}

.contextual-analysis__facts > div,
.contextual-analysis__card,
.contextual-analysis__kanji {
  min-inline-size: 0;
  padding: var(--ma-space-3);
  border: var(--ma-border-width-thin) solid var(--ma-color-border);
  border-radius: var(--ma-radius-control);
}

.contextual-analysis__facts dt {
  font-size: var(--ma-font-size-secondary);
  font-weight: 700;
}

.contextual-analysis__facts dd {
  margin: var(--ma-space-1) 0 0;
  overflow-wrap: anywhere;
}

.contextual-analysis__context-meaning {
  font-size: 1.05em;
}

.contextual-analysis__card {
  display: grid;
  gap: var(--ma-space-2);
}

.contextual-analysis__card h4,
.contextual-analysis__kanji h3 {
  margin: 0;
}

.contextual-analysis__grid,
.contextual-analysis__kanji-grid {
  display: grid;
  gap: var(--ma-space-3);
  margin-block-start: var(--ma-space-3);
}

.contextual-analysis__kanji-grid {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.contextual-analysis__kanji {
  display: grid;
  gap: var(--ma-space-2);
}

.contextual-analysis__kanji h3 {
  font-family: var(--ma-font-japanese);
  font-size: 2rem;
}

.contextual-analysis__details {
  min-inline-size: 0;
  padding-block: var(--ma-space-2);
  border-block-start: var(--ma-border-width-thin) solid var(--ma-color-border);
}

.contextual-analysis__details > summary {
  min-block-size: 2.75rem;
  cursor: pointer;
  font-weight: 700;
}

.contextual-analysis__provenance,
.contextual-analysis__alternatives ul,
.contextual-analysis__kanji ul {
  margin: 0;
  padding-inline-start: 1.4rem;
}

.contextual-analysis code {
  overflow-wrap: anywhere;
}

@media (max-width: 48rem) {
  .contextual-analysis {
    padding: var(--ma-space-3);
  }

  .contextual-analysis__facts,
  .contextual-analysis__kanji-grid {
    grid-template-columns: minmax(0, 1fr);
  }

  .contextual-analysis__header {
    display: grid;
  }

  .contextual-analysis__close {
    inline-size: 100%;
  }
}
'@

$page = @'
import { useEffect, useRef } from 'react';
import { AppLink } from '../../app/router/navigation';
import { ContextualAnalysisPanel } from './ContextualAnalysisPanel';

export type ContextualAnalysisPageProps = {
  slug: string;
  token: string;
};

export function ContextualAnalysisPage({ slug, token }: ContextualAnalysisPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    headingRef.current?.focus();
  }, [slug, token]);

  return (
    <article className="route-surface" data-route-id="UI-MVP-010">
      <header>
        <p className="eyebrow">COMPRENDER LA CANCIÓN</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Análisis contextual
        </h1>
        <p>
          Consulta el análisis publicado del token sin sustituir referencias rotas ni usar servicios
          lingüísticos externos.
        </p>
      </header>

      <AppLink href={`/aprender/${encodeURIComponent(slug)}`}>
        Volver al reproductor educativo
      </AppLink>

      <ContextualAnalysisPanel
        slug={slug}
        tokenKey={token}
        showStandaloneLink={false}
      />
    </article>
  );
}
'@

$e2e = @'
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const slug = 'kaiju-0123456789abcdefabcd';
const tokenKey = 'A1B2C3D4E5F60718293A';
const videoId = 'a8dgNdJVluc';

const detail = {
  slug,
  canonicalTitle: '怪獣',
  recordingTitle: 'Kaiju',
  recordingDurationMs: 10_000,
  artistName: 'サカナクション',
  providerCode: 'YOUTUBE',
  territoryCode: 'CR',
  languageTag: 'es',
  availableComponents: ['CATALOG', 'LYRICS', 'TIMING', 'TRANSLATION', 'ANALYSIS'],
  sourceExternalRef: videoId,
};

const timeline = {
  available: true,
  maximumPrecision: 'TOKEN',
  offsetMs: 0,
  lines: [
    {
      sectionOrder: 0,
      lineNo: 1,
      japaneseText: '怪獣になる',
      speakerLabel: null,
      precisionCode: 'TOKEN',
      startMs: 1000,
      endMs: 4000,
      tokens: [
        { tokenNo: 1, surface: '怪獣', startMs: 1000, endMs: 2300 },
        { tokenNo: 2, surface: 'になる', startMs: 2300, endMs: 4000 },
      ],
    },
  ],
};

const layers = {
  available: true,
  targetLanguage: 'es',
  hasFurigana: true,
  hasRomaji: true,
  hasSpanish: true,
  lines: [
    {
      sectionOrder: 0,
      sectionLabel: 'Verso',
      lineNo: 1,
      japaneseText: '怪獣になる',
      speakerLabel: null,
      tokens: [
        {
          tokenNo: 1,
          surface: '怪獣',
          startOffset: 0,
          endOffset: 2,
          analysisKey: tokenKey,
          readings: [
            {
              readingKana: 'かいじゅう',
              furigana: 'かいじゅう',
              romaji: 'kaijū',
              readingType: 'CONTEXTUAL',
            },
          ],
        },
        {
          tokenNo: 2,
          surface: 'になる',
          startOffset: 2,
          endOffset: 5,
          analysisKey: '00112233445566778899',
          readings: [
            {
              readingKana: 'になる',
              furigana: null,
              romaji: 'ni naru',
              readingType: 'CONTEXTUAL',
            },
          ],
        },
      ],
      translations: [
        {
          variantCode: 'NATURAL',
          translatedText: 'Me convierto en un monstruo.',
          displayOrder: 1,
        },
      ],
    },
  ],
};

const analysis = {
  available: true,
  tokenKey,
  surface: '怪獣',
  tokenNo: 1,
  targetLanguage: 'es',
  line: {
    sectionOrder: 0,
    sectionLabel: 'Verso',
    lineNo: 1,
    japaneseText: '怪獣になる',
    speakerLabel: null,
  },
  readings: [
    {
      readingKana: 'かいじゅう',
      furigana: 'かいじゅう',
      romaji: 'kaijū',
      readingType: 'CONTEXTUAL',
    },
  ],
  vocabulary: [
    {
      lemma: '怪獣',
      reading: 'かいじゅう',
      partOfSpeech: 'NOUN',
      senseKey: 'MONSTER',
      inflection: null,
      confidenceCode: 'CONFIRMED',
      senses: [
        {
          languageTag: 'es',
          definition: 'Monstruo o criatura gigantesca.',
          usageNote: 'En la canción funciona como imagen contextual.',
          displayOrder: 1,
        },
      ],
    },
  ],
  kanji: [
    {
      character: '怪',
      charOffset: 0,
      gradeCode: null,
      jlptCode: 'N1',
      readings: [
        {
          reading: 'かい',
          readingType: 'ON',
          languageTag: 'es',
          meaning: 'extraño; sospechoso',
          displayOrder: 1,
        },
      ],
    },
    {
      character: '獣',
      charOffset: 1,
      gradeCode: 'G6',
      jlptCode: 'N1',
      readings: [
        {
          reading: 'じゅう',
          readingType: 'ON',
          languageTag: 'es',
          meaning: 'bestia',
          displayOrder: 1,
        },
      ],
    },
  ],
  morphology: [
    {
      lemma: '怪獣',
      partOfSpeechCode: 'NOUN',
      conjugationCode: null,
    },
  ],
  grammar: [
    {
      grammarCode: 'N-NINARU',
      title: '〜になる',
      levelCode: 'N4',
      note: 'Cambio de estado.',
      explanation: 'Expresa convertirse o llegar a ser algo.',
      examples: null,
    },
  ],
  provenance: [
    {
      sourceType: 'EDITORIAL',
      citation: 'Curaduría interna contrastada',
      locator: 'Línea 1',
      contributionType: 'ANALYSIS',
    },
  ],
};

const iframeApi = `
(() => {
  let currentTime = 2;
  let currentEvents = null;
  window.__analysisPlayerInstances = 0;
  window.__analysisCurrentTime = () => currentTime;

  window.YT = {
    Player: function(element, options) {
      window.__analysisPlayerInstances += 1;
      currentEvents = options.events;
      this.destroy = () => {};
      this.playVideo = () => options.events.onStateChange({ data: 1 });
      this.pauseVideo = () => options.events.onStateChange({ data: 2 });
      this.seekTo = (seconds) => {
        currentTime = seconds;
        options.events.onStateChange({ data: 3 });
      };
      this.getCurrentTime = () => currentTime;
      queueMicrotask(() => options.events.onReady({ target: this }));
    }
  };

  window.onYouTubeIframeAPIReady?.();
})();
`;

async function mockStudent(page: Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 401,
      contentType: 'application/problem+json',
      body: JSON.stringify({ title: 'Sin sesión', status: 401 }),
    });
  });

  await page.route(`**/api/v1/public/catalog/songs/${slug}?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(detail),
    });
  });

  await page.route(`**/api/v1/public/catalog/songs/${slug}/synchronization?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(timeline),
    });
  });

  await page.route(`**/api/v1/public/catalog/songs/${slug}/layers?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(layers),
    });
  });

  await page.route(`**/api/v1/public/catalog/songs/${slug}/analysis/${tokenKey}?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(analysis),
    });
  });

  await page.route('https://www.youtube-nocookie.com/embed/**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'text/html; charset=utf-8',
      body: '<!doctype html><html><body><p>Fixture YouTube</p></body></html>',
    });
  });

  await page.route('https://www.youtube.com/iframe_api', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/javascript',
      body: iframeApi,
    });
  });
}

test.describe('BL-MVP-068 · panel de análisis contextual', () => {
  test('seleccionar token abre análisis autorizado sin remontar ni detener el player', async ({
    page,
  }) => {
    await mockStudent(page);
    await page.goto(`/aprender/${slug}`);

    await page.getByRole('button', { name: 'Cargar reproductor de YouTube' }).click();
    await expect(page.getByText('Reproductor listo', { exact: false })).toBeVisible();

    await expect
      .poll(() =>
        page.evaluate(
          () =>
            (window as typeof window & { __analysisPlayerInstances?: number })
              .__analysisPlayerInstances ?? 0,
        ),
      )
      .toBe(1);

    const before = await page.evaluate(
      () =>
        (window as typeof window & { __analysisCurrentTime?: () => number })
          .__analysisCurrentTime?.() ?? -1,
    );

    await page.getByRole('button', { name: 'Analizar 怪獣' }).click();

    await expect(page.getByText('Monstruo o criatura gigantesca.')).toBeVisible();
    await expect(page.getByText('かいじゅう', { exact: true })).toBeVisible();
    await expect(page.getByText('〜になる')).toBeVisible();
    await expect(page.getByText('bestia')).toBeVisible();

    expect(
      await page.evaluate(
        () =>
          (window as typeof window & { __analysisPlayerInstances?: number })
            .__analysisPlayerInstances ?? 0,
      ),
    ).toBe(1);

    expect(
      await page.evaluate(
        () =>
          (window as typeof window & { __analysisCurrentTime?: () => number })
            .__analysisCurrentTime?.() ?? -1,
      ),
    ).toBe(before);
  });

  test('prioriza contexto, conserva niveles orientativos y no llama servicios lingüísticos externos', async ({
    page,
  }) => {
    const external: string[] = [];
    page.on('request', (request) => {
      const url = new URL(request.url());
      if (
        !['127.0.0.1', 'localhost', 'www.youtube.com', 'www.youtube-nocookie.com'].includes(
          url.hostname,
        )
      ) {
        external.push(request.url());
      }
    });

    await mockStudent(page);
    await page.goto(`/aprender/${slug}`);
    await page.getByRole('button', { name: 'Analizar 怪獣' }).click();

    await expect(page.getByText('Significado en esta canción:', { exact: false })).toBeVisible();
    await page.getByText('Kanji', { exact: true }).click();
    await expect(page.getByText('nivel orientativo, no certificación oficial.', { exact: false }))
      .toBeVisible();
    await page.getByText('Gramática de esta línea', { exact: true }).click();
    await expect(page.getByText('Expresa convertirse o llegar a ser algo.')).toBeVisible();

    expect(external).toEqual([]);
  });

  test('UI-MVP-010 abre el mismo análisis por deep link y una referencia incompatible no se sustituye', async ({
    page,
  }) => {
    await mockStudent(page);
    await page.goto(`/aprender/${slug}/analisis/${tokenKey}`);

    await expect(page.locator('[data-route-id="UI-MVP-010"]')).toBeVisible();
    await expect(page.getByText('Monstruo o criatura gigantesca.')).toBeVisible();
    await expect(page.getByRole('link', { name: 'Volver al reproductor educativo' })).toHaveAttribute(
      'href',
      `/aprender/${slug}`,
    );

    await page.route(`**/api/v1/public/catalog/songs/${slug}/analysis/FFFFFFFFFFFFFFFFFFFF?**`, async (route) => {
      await route.fulfill({
        status: 409,
        contentType: 'application/problem+json',
        body: JSON.stringify({
          title: 'Análisis contextual incompatible',
          status: 409,
          detail: 'No se mezclará otra revisión.',
        }),
      });
    });

    await page.goto(`/aprender/${slug}/analisis/FFFFFFFFFFFFFFFFFFFF`);
    await expect(page.getByText('Análisis contextual incompatible')).toBeVisible();
    await expect(page.getByText('Monstruo o criatura gigantesca.')).toHaveCount(0);
  });

  test('a 320 px mantiene token, panel y deep link accesibles sin overflow', async ({ page }) => {
    await mockStudent(page);
    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto(`/aprender/${slug}`);
    await page.getByRole('button', { name: 'Analizar 怪獣' }).click();

    await expect(page.locator('[data-contextual-analysis-panel]')).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
'@

$verifier = @'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL068_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(docker compose exec -T postgres psql --username="$PGUSER" --dbname="$PGDATABASE" --no-password --set=ON_ERROR_STOP=1)
else
  psql_base=(psql --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$PGDATABASE" --no-password --set=ON_ERROR_STOP=1)
fi

fail_check() {
  echo "ERROR: BL-MVP-068: $1" >&2
  exit 1
}

service="src/Modules/Content/Infrastructure/PublicPlayback/PublicContextualAnalysisService.cs"
keys="src/Modules/Content/Infrastructure/PublicPlayback/PublicAnalysisTokenKey.cs"
endpoint="apps/api/Endpoints/PublicCatalog/PublicContextualAnalysisEndpoints.cs"
player="apps/web/src/routes/student/EducationalPlayerPage.tsx"
karaoke="apps/web/src/routes/student/EducationalKaraoke.tsx"
panel="apps/web/src/routes/student/ContextualAnalysisPanel.tsx"
area="apps/web/src/routes/student/StudentArea.tsx"
test_file="tests/E2ETests/contextual-analysis-panel.spec.ts"

grep -Fq "/api/v1/public/catalog/songs/{slug}/analysis/{token}" "$endpoint" \
  || fail_check "falta endpoint público contextual."

grep -Fq "published_package_projection" "$service" \
  || fail_check "el servicio no revalida publicación."

grep -Fq "component_kind = 'LYRICS'" "$service" \
  || fail_check "falta letra exacta del paquete."

grep -Fq "component_kind = 'ANALYSIS'" "$service" \
  || fail_check "falta análisis exacto del paquete."

grep -Fq "analysis.lyrics_revision_id = @lyrics_revision_id" "$service" \
  || fail_check "falta compatibilidad análisis/letra."

grep -Fq "content.vocabulary_occurrence" "$service" \
  || fail_check "falta vocabulario contextual."

grep -Fq "content.kanji_occurrence" "$service" \
  || fail_check "falta kanji contextual."

grep -Fq "content.morphology_annotation" "$service" \
  || fail_check "falta morfología contextual."

grep -Fq "content.grammar_occurrence" "$service" \
  || fail_check "falta gramática contextual."

grep -Fq "LINGUISTIC_ANALYSIS_REVISION" "$service" \
  || fail_check "falta procedencia del análisis."

grep -Fq ":public-analysis-token-v1" "$keys" \
  || fail_check "falta referencia pública opaca de token."

grep -Fq "onTokenAnalysis" "$karaoke" \
  || fail_check "los tokens no son accionables para análisis."

grep -Fq "<ContextualAnalysisPanel" "$player" \
  || fail_check "UI-MVP-009 no mantiene panel embebido."

grep -Fq "UI-MVP-010" "$area" \
  || fail_check "UI-MVP-010 no está materializada."

grep -Fq "Significado en esta canción" "$panel" \
  || fail_check "el sentido contextual no se prioriza."

grep -Fq "no certificación oficial" "$panel" \
  || fail_check "los niveles no están marcados como orientativos."

grep -Fq "__analysisPlayerInstances" "$test_file" \
  || fail_check "E2E no verifica que el player permanezca montado."

grep -Fq "expect(external).toEqual([])" "$test_file" \
  || fail_check "E2E no exige cero servicios lingüísticos externos."

if grep -Eiq 'https?://|fetch\(|XMLHttpRequest|axios|openai|anthropic|gemini|deepl|dictionaryapi|jisho|mecab.*api' "$service" "$panel"; then
  fail_check "dependencia lingüística externa detectada."
fi

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-068-contextual-analysis-panel.txt <<'SQL'
DO $$
DECLARE
    tables_ok boolean;
BEGIN
    SELECT count(*) = 12
      INTO tables_ok
      FROM information_schema.tables
     WHERE table_schema IN ('content', 'editorial', 'catalog')
       AND table_name IN (
         'linguistic_analysis_revision',
         'token_reading',
         'vocabulary_entry',
         'vocabulary_sense',
         'vocabulary_occurrence',
         'kanji_entry',
         'kanji_reading',
         'kanji_occurrence',
         'morphology_annotation',
         'grammar_point',
         'grammar_occurrence',
         'publication_component'
       );

    IF NOT tables_ok THEN
      RAISE EXCEPTION 'faltan tablas requeridas por BL068';
    END IF;
END
$$;

PREPARE bl068_token_context(uuid, uuid, uuid, integer, varchar) AS
SELECT
    reading.reading_kana,
    vocabulary.lemma,
    kanji.character,
    morphology.lemma,
    grammar.grammar_code
FROM content.lyric_token AS token
LEFT JOIN content.token_reading AS reading
  ON reading.token_id = token.token_id
 AND reading.analysis_revision_id = $1
LEFT JOIN content.vocabulary_occurrence AS vocabulary_occurrence
  ON vocabulary_occurrence.token_id = token.token_id
 AND vocabulary_occurrence.analysis_revision_id = $1
LEFT JOIN content.vocabulary_entry AS vocabulary
  ON vocabulary.vocabulary_id = vocabulary_occurrence.vocabulary_id
LEFT JOIN content.kanji_occurrence AS kanji_occurrence
  ON kanji_occurrence.token_id = token.token_id
 AND kanji_occurrence.analysis_revision_id = $1
LEFT JOIN content.kanji_entry AS kanji
  ON kanji.kanji_id = kanji_occurrence.kanji_id
LEFT JOIN content.morphology_annotation AS morphology
  ON morphology.token_id = token.token_id
 AND morphology.analysis_revision_id = $1
LEFT JOIN content.grammar_occurrence AS grammar_occurrence
  ON grammar_occurrence.line_id = $3
 AND grammar_occurrence.analysis_revision_id = $1
LEFT JOIN content.grammar_point AS grammar
  ON grammar.grammar_point_id = grammar_occurrence.grammar_point_id
JOIN content.lyric_line AS line
  ON line.line_id = token.line_id
JOIN content.lyric_section AS section
  ON section.section_id = line.section_id
WHERE token.token_id = $2
  AND token.line_id = $3
  AND token.token_no = $4
  AND section.lyrics_revision_id = $5::uuid;

DEALLOCATE bl068_token_context;
SQL

echo "bl=BL-MVP-068"
echo "ui=UI-MVP-010"
echo "embedded_panel=true"
echo "standalone_deep_link=true"
echo "player_forced_stop=false"
echo "opaque_public_token_key=true"
echo "exact_publication=true"
echo "exact_lyrics_revision=true"
echo "exact_analysis_revision=true"
echo "vocabulary_contextual=true"
echo "kanji_contextual=true"
echo "morphology_contextual=true"
echo "grammar_contextual=true"
echo "provenance_visible=true"
echo "jlpt_orientative=true"
echo "external_linguistic_api=false"
echo "writes=false"
echo "publishes=false"
echo "OK: BL-MVP-068 panel de análisis contextual verificado."
'@

$readme = @'
# BL-MVP-068 — Mostrar panel de análisis contextual

## Alcance

Implementa `UI-MVP-010` y un panel reutilizable dentro de `UI-MVP-009`.

Resultado aceptable normativo:

> Seleccionar token/línea presenta vocabulario, kanji, lectura y gramática autorizados sin detener obligatoriamente el player.

## Contrato público

`GET /api/v1/public/catalog/songs/{slug}/analysis/{token}?territory=CR&language=es`

`token` es una clave pública opaca derivada del token canónico. No expone UUID editorial.

El servicio:

- revalida publicación, territorio e idioma;
- usa los componentes `LYRICS` y `ANALYSIS` exactos del paquete publicado;
- rechaza revisiones incompatibles;
- no sustituye una referencia rota por otra revisión;
- devuelve lectura, vocabulario, morfología, kanji, gramática y procedencia;
- no llama servicios lingüísticos externos.

## Experiencia

En `/aprender/{slug}`, un token con análisis se vuelve accionable. El panel se actualiza sin desmontar el reproductor.

También existe deep link:

`/aprender/{slug}/analisis/{token}`

Los niveles JLPT/escolares se muestran como orientación, nunca como certificación oficial.
'@

$doc = @'
# Panel de análisis contextual

BL-MVP-068 materializa la etapa **Comprensión** de F3 sin adelantar BL-MVP-069.

## Decisiones

- `UI-MVP-009` mantiene el reproductor montado mientras el usuario consulta un token.
- `UI-MVP-010` reutiliza el mismo panel como deep link.
- La referencia de ruta del token es opaca y no publica UUID internos.
- La consulta pública vuelve a resolver la publicación elegible y los componentes exactos `LYRICS` + `ANALYSIS`.
- Una revisión incompatible termina en estado seguro; nunca se toma “el análisis más reciente”.
- La superficie japonesa siempre proviene de M03.
- El significado contextual se presenta antes que información adicional.
- Las lecturas ambiguas permanecen explícitas.
- JLPT y grado escolar son orientativos.
- No se invoca diccionario, traductor, segmentador ni modelo externo.

## Degradación

Un token válido puede no tener todos los apartados. Vocabulario, morfología, kanji y gramática se omiten o marcan como no disponibles de forma independiente.

YouTube puede continuar reproduciéndose porque abrir/cerrar el panel no cambia la identidad del componente `SynchronizedYouTubePreview`.

BL-MVP-069 podrá consolidar después estas consultas dentro del read model integral del paquete publicado.
'@

Write-Utf8Lf "src/Modules/Content/Infrastructure/PublicPlayback/PublicAnalysisTokenKey.cs" $tokenKey
Write-Utf8Lf "src/Modules/Content/Infrastructure/PublicPlayback/PublicContextualAnalysisService.cs" $service
Write-Utf8Lf "apps/api/Endpoints/PublicCatalog/PublicContextualAnalysisEndpoints.cs" $endpoint
Write-Utf8Lf "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" $panel
Write-Utf8Lf "apps/web/src/routes/student/contextual-analysis-panel.css" $panelCss
Write-Utf8Lf "apps/web/src/routes/student/ContextualAnalysisPage.tsx" $page
Write-Utf8Lf "tests/E2ETests/contextual-analysis-panel.spec.ts" $e2e
Write-Utf8Lf "scripts/ci/content/verify-contextual-analysis-panel.sh" $verifier
Write-Utf8Lf "README/BL-MVP-068_README.md" $readme
Write-Utf8Lf "docs/engineering/content/contextual-analysis-panel.md" $doc

Replace-Once `
    "apps/api/Program.cs" `
    "builder.Services.AddSingleton<PublicSongSynchronizationService>();`nbuilder.Services.AddSingleton<PublicSongLearningLayersService>();" `
    "builder.Services.AddSingleton<PublicSongSynchronizationService>();`nbuilder.Services.AddSingleton<PublicSongLearningLayersService>();`nbuilder.Services.AddSingleton<PublicContextualAnalysisService>();" `
    "registro del servicio público BL068"

Replace-Once `
    "apps/api/Program.cs" `
    "app.MapPublicSongSynchronization();`napp.MapPublicSongLearningLayers();" `
    "app.MapPublicSongSynchronization();`napp.MapPublicSongLearningLayers();`napp.MapPublicContextualAnalysis();" `
    "mapeo del endpoint público BL068"

Replace-Once `
    "src/Modules/Content/Infrastructure/PublicPlayback/PublicSongLearningLayersService.cs" `
    "    int StartOffset,`n    int EndOffset,`n    IReadOnlyList<PublicLearningReading> Readings);" `
    "    int StartOffset,`n    int EndOffset,`n    string? AnalysisKey,`n    IReadOnlyList<PublicLearningReading> Readings);" `
    "clave pública en token de capas"

Replace-Once `
    "src/Modules/Content/Infrastructure/PublicPlayback/PublicSongLearningLayersService.cs" `
    "                        token.StartOffset,`n                        token.EndOffset,`n                        readingsByToken.TryGetValue(token.TokenId, out var tokenReadings)" `
    "                        token.StartOffset,`n                        token.EndOffset,`n                        header.AnalysisRevisionId is null`n                            ? null`n                            : PublicAnalysisTokenKey.FromTokenId(token.TokenId),`n                        readingsByToken.TryGetValue(token.TokenId, out var tokenReadings)" `
    "emisión de clave pública de análisis"

Replace-Once `
    "apps/web/src/routes/student/EducationalKaraoke.tsx" `
    "  endOffset: number;`n  readings: EducationalReading[];" `
    "  endOffset: number;`n  analysisKey?: string | null;`n  readings: EducationalReading[];" `
    "analysisKey del token"

Replace-Once `
    "apps/web/src/routes/student/EducationalKaraoke.tsx" `
    "export type EducationalKaraokeProps = {`n  layers: EducationalLayers;`n  snapshot: LocalSynchronizationSnapshot;`n  visibleLayers: VisibleEducationalLayers;`n  onVisibleLayersChange: (next: VisibleEducationalLayers) => void;`n};" `
    @"
export type EducationalAnalysisSelection = {
  analysisKey: string;
  surface: string;
  sectionOrder: number;
  lineNo: number;
  tokenNo: number;
};

export type EducationalKaraokeProps = {
  layers: EducationalLayers;
  snapshot: LocalSynchronizationSnapshot;
  visibleLayers: VisibleEducationalLayers;
  onVisibleLayersChange: (next: VisibleEducationalLayers) => void;
  selectedAnalysisKey?: string | null;
  onTokenAnalysis?: (selection: EducationalAnalysisSelection) => void;
};
"@ `
    "props de selección BL068"

$karaokePath = Join-Path $script:Root "apps/web/src/routes/student/EducationalKaraoke.tsx"
$karaokeText = [System.IO.File]::ReadAllText($karaokePath)

$oldRenderStart = $karaokeText.IndexOf("function renderJapaneseLine(", [System.StringComparison]::Ordinal)
$oldRenderEnd = $karaokeText.IndexOf("function romajiForLine(", $oldRenderStart, [System.StringComparison]::Ordinal)
if ($oldRenderStart -lt 0 -or $oldRenderEnd -lt 0) {
    Fail "no se pudo localizar renderJapaneseLine en EducationalKaraoke.tsx"
}

$newRender = @'
function renderJapaneseLine(
  line: EducationalLine,
  showFurigana: boolean,
  activeTokenNo: number | null,
  selectedAnalysisKey: string | null,
  onTokenAnalysis: ((selection: EducationalAnalysisSelection) => void) | undefined,
) {
  if (line.tokens.length === 0) {
    return <span lang="ja">{line.japaneseText}</span>;
  }

  const characters = Array.from(line.japaneseText);
  const orderedTokens = [...line.tokens].sort(
    (left, right) => left.startOffset - right.startOffset || left.tokenNo - right.tokenNo,
  );
  const nodes: ReactNode[] = [];
  let cursor = 0;

  for (const token of orderedTokens) {
    const start = Math.max(cursor, Math.min(token.startOffset, characters.length));
    const end = Math.max(start, Math.min(token.endOffset, characters.length));

    if (start > cursor) {
      nodes.push(
        <span key={`gap-${cursor}-${start}`} lang="ja">
          {characters.slice(cursor, start).join('')}
        </span>,
      );
    }

    const surface = characters.slice(start, end).join('') || token.surface;
    const readings = orderedReadings(token.readings);
    const active = activeTokenNo === token.tokenNo;
    const selected = Boolean(token.analysisKey && token.analysisKey === selectedAnalysisKey);
    const content =
      readings.length === 1 && showFurigana
        ? renderRuby(resolveFurigana(surface, readings[0]!))
        : surface;
    const className = [
      'educational-karaoke__token',
      active ? 'is-active' : '',
      selected ? 'is-selected' : '',
      token.analysisKey && onTokenAnalysis ? 'is-analyzable' : '',
    ]
      .filter(Boolean)
      .join(' ');

    if (token.analysisKey && onTokenAnalysis) {
      nodes.push(
        <button
          type="button"
          key={`token-${token.tokenNo}`}
          className={className}
          data-karaoke-token={token.tokenNo}
          data-analysis-key={token.analysisKey}
          data-active={active ? 'true' : 'false'}
          aria-label={`Analizar ${surface}`}
          aria-pressed={selected}
          aria-controls="contextual-analysis-panel"
          title={readings.length > 1 ? 'Lectura contextual ambigua' : 'Abrir análisis contextual'}
          onClick={() =>
            onTokenAnalysis({
              analysisKey: token.analysisKey!,
              surface,
              sectionOrder: line.sectionOrder,
              lineNo: line.lineNo,
              tokenNo: token.tokenNo,
            })
          }
        >
          {content}
        </button>,
      );
    } else {
      nodes.push(
        <span
          key={`token-${token.tokenNo}`}
          className={className}
          data-karaoke-token={token.tokenNo}
          data-active={active ? 'true' : 'false'}
          title={readings.length > 1 ? 'Lectura contextual ambigua' : undefined}
          lang="ja"
        >
          {content}
        </span>,
      );
    }

    cursor = end;
  }

  if (cursor < characters.length) {
    nodes.push(
      <span key={`tail-${cursor}`} lang="ja">
        {characters.slice(cursor).join('')}
      </span>,
    );
  }

  return nodes;
}

'@

$karaokeText =
    $karaokeText.Substring(0, $oldRenderStart) +
    $newRender +
    $karaokeText.Substring($oldRenderEnd)

$oldDestructure = @'
export function EducationalKaraoke({
  layers,
  snapshot,
  visibleLayers,
  onVisibleLayersChange,
}: EducationalKaraokeProps) {
'@
$newDestructure = @'
export function EducationalKaraoke({
  layers,
  snapshot,
  visibleLayers,
  onVisibleLayersChange,
  selectedAnalysisKey = null,
  onTokenAnalysis,
}: EducationalKaraokeProps) {
'@
if (-not $karaokeText.Contains($oldDestructure)) {
    Fail "no se encontro destructuring de EducationalKaraoke"
}
$karaokeText = $karaokeText.Replace($oldDestructure, $newDestructure)

$oldCall = @'
                    {renderJapaneseLine(
                      line,
                      visibleLayers.furigana && layers.hasFurigana,
                      active ? activeTokenNo : null,
                    )}
'@
$newCall = @'
                    {renderJapaneseLine(
                      line,
                      visibleLayers.furigana && layers.hasFurigana,
                      active ? activeTokenNo : null,
                      selectedAnalysisKey,
                      onTokenAnalysis,
                    )}
'@
if (-not $karaokeText.Contains($oldCall)) {
    Fail "no se encontro llamada renderJapaneseLine"
}
$karaokeText = $karaokeText.Replace($oldCall, $newCall)
Write-Utf8Lf "apps/web/src/routes/student/EducationalKaraoke.tsx" $karaokeText

$karaokeCssPath = Join-Path $script:Root "apps/web/src/routes/student/educational-karaoke.css"
$karaokeCss = [System.IO.File]::ReadAllText($karaokeCssPath)
$karaokeCssAppend = @'

.educational-karaoke__token.is-analyzable {
  display: inline;
  padding: 0.08em 0.12em;
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  line-height: inherit;
  cursor: pointer;
}

.educational-karaoke__token.is-analyzable:hover {
  background: var(--ma-color-canvas);
}

.educational-karaoke__token.is-analyzable:focus-visible {
  outline: 0.15rem solid var(--ma-color-primary);
  outline-offset: 0.12rem;
}

.educational-karaoke__token.is-selected {
  box-shadow: inset 0 -0.16em 0 var(--ma-color-primary);
}
'@
Write-Utf8Lf "apps/web/src/routes/student/educational-karaoke.css" ($karaokeCss.TrimEnd() + $karaokeCssAppend)

Replace-Once `
    "apps/web/src/routes/student/EducationalPlayerPage.tsx" `
    "  type EducationalLayers,`n  type VisibleEducationalLayers,`n} from './EducationalKaraoke';" `
    "  type EducationalAnalysisSelection,`n  type EducationalLayers,`n  type VisibleEducationalLayers,`n} from './EducationalKaraoke';`nimport { ContextualAnalysisPanel } from './ContextualAnalysisPanel';" `
    "imports BL068 del player"

Replace-Once `
    "apps/web/src/routes/student/EducationalPlayerPage.tsx" `
    "  const [visibleLayers, setVisibleLayers] = useState<VisibleEducationalLayers>({`n    ...defaultVisibleEducationalLayers,`n  });" `
    "  const [visibleLayers, setVisibleLayers] = useState<VisibleEducationalLayers>({`n    ...defaultVisibleEducationalLayers,`n  });`n  const [analysisSelection, setAnalysisSelection] = useState<EducationalAnalysisSelection | null>(`n    null,`n  );" `
    "estado de selección BL068"

Replace-Once `
    "apps/web/src/routes/student/EducationalPlayerPage.tsx" `
    "    setSnapshot(emptySnapshot());`n    setVisibleLayers({ ...defaultVisibleEducationalLayers });" `
    "    setSnapshot(emptySnapshot());`n    setVisibleLayers({ ...defaultVisibleEducationalLayers });`n    setAnalysisSelection(null);" `
    "reinicio BL068 por slug"

$playerPath = Join-Path $script:Root "apps/web/src/routes/student/EducationalPlayerPage.tsx"
$playerText = [System.IO.File]::ReadAllText($playerPath)
$oldKaraoke = @'
          <EducationalKaraoke
            layers={learningLayers}
            snapshot={snapshot}
            visibleLayers={visibleLayers}
            onVisibleLayersChange={setVisibleLayers}
          />

'@
$newKaraoke = @'
          <div className="educational-player__learning-layout">
            <EducationalKaraoke
              layers={learningLayers}
              snapshot={snapshot}
              visibleLayers={visibleLayers}
              onVisibleLayersChange={setVisibleLayers}
              selectedAnalysisKey={analysisSelection?.analysisKey ?? null}
              onTokenAnalysis={setAnalysisSelection}
            />

            <ContextualAnalysisPanel
              slug={slug}
              tokenKey={analysisSelection?.analysisKey ?? null}
              surfaceHint={analysisSelection?.surface ?? null}
              onClose={() => setAnalysisSelection(null)}
            />
          </div>

'@
if (-not $playerText.Contains($oldKaraoke)) {
    Fail "no se encontro EducationalKaraoke en EducationalPlayerPage"
}
$playerText = $playerText.Replace($oldKaraoke, $newKaraoke)
Write-Utf8Lf "apps/web/src/routes/student/EducationalPlayerPage.tsx" $playerText

$playerCssPath = Join-Path $script:Root "apps/web/src/routes/student/educational-player.css"
$playerCss = [System.IO.File]::ReadAllText($playerCssPath)
$playerCssAppend = @'

.educational-player__learning-layout {
  display: grid;
  grid-template-columns: minmax(24rem, 1.15fr) minmax(19rem, 0.85fr);
  gap: var(--ma-space-4);
  align-items: start;
  min-inline-size: 0;
}

.educational-player__learning-layout > * {
  min-inline-size: 0;
}

@media (max-width: 64rem) {
  .educational-player__learning-layout {
    grid-template-columns: minmax(0, 1fr);
  }
}
'@
Write-Utf8Lf "apps/web/src/routes/student/educational-player.css" ($playerCss.TrimEnd() + $playerCssAppend)

Replace-Once `
    "apps/web/src/routes/student/StudentArea.tsx" `
    "import { EducationalPlayerPage } from './EducationalPlayerPage';" `
    "import { ContextualAnalysisPage } from './ContextualAnalysisPage';`nimport { EducationalPlayerPage } from './EducationalPlayerPage';" `
    "import UI-MVP-010"

Replace-Once `
    "apps/web/src/routes/student/StudentArea.tsx" `
    "  if (match.route.id === 'UI-MVP-009') {`n    return <EducationalPlayerPage slug={match.params.slug!} />;`n  }`n`n  return (" `
    "  if (match.route.id === 'UI-MVP-009') {`n    return <EducationalPlayerPage slug={match.params.slug!} />;`n  }`n`n  if (match.route.id === 'UI-MVP-010') {`n    return <ContextualAnalysisPage slug={match.params.slug!} token={match.params.token!} />;`n  }`n`n  return (" `
    "materialización UI-MVP-010"

$workflowPath = Join-Path $script:Root ".github/workflows/ci.yml"
$workflow = [System.IO.File]::ReadAllText($workflowPath)
$workflowMarker = @'
      - name: Verify linguistic analysis editorial workspace
'@
$workflowInsert = @'
      - name: Verify contextual analysis panel
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL068_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-contextual-analysis-panel.sh

      - name: Verify linguistic analysis editorial workspace
'@
if (-not $workflow.Contains($workflowMarker)) {
    Fail "no se encontro el marcador de CI para BL068"
}
$workflow = $workflow.Replace($workflowMarker, $workflowInsert)
Write-Utf8Lf ".github/workflows/ci.yml" $workflow

& git.exe diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check detecto problemas."
}

Write-Host ""
Write-Host "OK: BL-MVP-068 aplicado en working tree."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "El instalador sigue UNTRACKED y debe borrarse antes del staging."
Write-Host ""
Write-Host "Siguiente evidencia:"
Write-Host "  git status --short --untracked-files=all"
Write-Host "  git diff --check"
Write-Host "  git diff --stat"
Write-Host "  git diff --name-status"
