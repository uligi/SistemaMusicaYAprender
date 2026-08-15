param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedHead = "1c47e5055fff3ecd8d8dcfa44f93ce94eb055ac3"

function Fail([string]$Message) {
    throw "BL-MVP-068 editorial DRAFT analysis preview: $Message"
}

function Normalize-Lf([string]$Value) {
    return ($Value -replace "`r`n", "`n" -replace "`r", "`n")
}

function Write-Utf8Lf([string]$RelativePath, [string]$Content) {
    $full = Join-Path $script:Root $RelativePath
    $directory = Split-Path -Parent $full
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $normalized = Normalize-Lf $Content
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($full, $normalized, $utf8)
    Write-Host "OK: $RelativePath"
}

function Replace-Once(
    [string]$RelativePath,
    [string]$Old,
    [string]$New,
    [string]$Description
) {
    $full = Join-Path $script:Root $RelativePath
    if (-not (Test-Path $full -PathType Leaf)) {
        Fail "no existe $RelativePath"
    }

    $text = Normalize-Lf ([System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8))
    $oldNormalized = Normalize-Lf $Old
    $newNormalized = Normalize-Lf $New

    if ($text.Contains($newNormalized)) {
        Write-Host "OK: $Description ya aplicado."
        return
    }

    $count = ([regex]::Matches($text, [regex]::Escape($oldNormalized))).Count
    if ($count -ne 1) {
        Fail "se esperaba 1 bloque para $Description en $RelativePath y se encontraron $count."
    }

    Write-Utf8Lf $RelativePath ($text.Replace($oldNormalized, $newNormalized))
}

function Append-Once(
    [string]$RelativePath,
    [string]$Marker,
    [string]$Content
) {
    $full = Join-Path $script:Root $RelativePath
    if (-not (Test-Path $full -PathType Leaf)) {
        Fail "no existe $RelativePath"
    }

    $text = Normalize-Lf ([System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8))
    if ($text.Contains($Marker)) {
        Write-Host "OK: documentación $RelativePath ya actualizada."
        return
    }

    Write-Utf8Lf $RelativePath ($text.TrimEnd() + "`n`n" + (Normalize-Lf $Content).Trim() + "`n")
}

$script:Root = (Resolve-Path $RepoRoot).Path
Set-Location $script:Root

$branch = (& git.exe branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne "main") {
    Fail "se requiere branch main; actual='$branch'."
}

$head = (& git.exe rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $ExpectedHead) {
    Fail "HEAD esperado $ExpectedHead; actual $head."
}

$myRelative = $null
if ($PSCommandPath) {
    $resolvedScript = (Resolve-Path $PSCommandPath).Path
    if ($resolvedScript.StartsWith($script:Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $myRelative = $resolvedScript.Substring($script:Root.Length).TrimStart('\','/').Replace('\','/')
    }
}

$dirty = @(& git.exe status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    Fail "no se pudo leer git status."
}

$unexpected = @(
    $dirty | Where-Object {
        if (-not $myRelative) { return $true }
        $path = $_.Substring(3).Trim().Trim('"').Replace('\','/')
        return $path -ne $myRelative
    }
)

if ($unexpected.Count -gt 0) {
    Write-Host "Cambios inesperados:"
    $unexpected | ForEach-Object { Write-Host $_ }
    Fail "el working tree debe estar limpio salvo este instalador temporal."
}

Write-Host "Base verificada: main @ $ExpectedHead"
Write-Host "Aplicando previsualización editorial DRAFT del análisis contextual..."

# -----------------------------------------------------------------------------
# Backend: karaoke DRAFT expone la misma clave opaca de análisis por token.
# -----------------------------------------------------------------------------

Replace-Once `
    "src/Modules/Content/Infrastructure/Administration/EditorialKaraokePreviewService.cs" `
    @'
namespace MusicaAprender.Modules.Content.Infrastructure.Administration;
'@ `
    @'
using MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

namespace MusicaAprender.Modules.Content.Infrastructure.Administration;
'@ `
    "import del generador de clave opaca"

Replace-Once `
    "src/Modules/Content/Infrastructure/Administration/EditorialKaraokePreviewService.cs" `
    @'
public sealed record EditorialKaraokeToken(
    int TokenNo,
    string Surface,
    int StartOffset,
    int EndOffset,
    IReadOnlyList<EditorialKaraokeReading> Readings);
'@ `
    @'
public sealed record EditorialKaraokeToken(
    int TokenNo,
    string Surface,
    int StartOffset,
    int EndOffset,
    string? AnalysisKey,
    IReadOnlyList<EditorialKaraokeReading> Readings);
'@ `
    "AnalysisKey en tokens del karaoke editorial"

Replace-Once `
    "src/Modules/Content/Infrastructure/Administration/EditorialKaraokePreviewService.cs" `
    @'
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
'@ `
    @'
                            .Select(token => new EditorialKaraokeToken(
                                token.TokenNo,
                                token.Surface,
                                token.StartOffset,
                                token.EndOffset,
                                analysisRevision is null
                                    ? null
                                    : PublicAnalysisTokenKey.FromTokenId(token.TokenId),
                                readingsByToken.TryGetValue(
                                    token.TokenId,
                                    out var tokenReadings)
                                        ? tokenReadings
                                        : Array.Empty<EditorialKaraokeReading>()))
'@ `
    "clave de análisis opaca en cada token DRAFT compatible"

# -----------------------------------------------------------------------------
# Backend: endpoint editorial de análisis contextual DRAFT.
# -----------------------------------------------------------------------------

Write-Utf8Lf `
    "src/Modules/Content/Infrastructure/Administration/EditorialContextualAnalysisPreviewService.cs" `
@'
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
'@

Write-Utf8Lf `
    "apps/api/Endpoints/Editorial/EditorialContextualAnalysisPreviewEndpoints.cs" `
@'
using System.Security.Claims;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public static class EditorialContextualAnalysisPreviewEndpoints
{
    public static IEndpointRouteBuilder MapEditorialContextualAnalysisPreview(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/analysis-preview/{token}",
                ReadAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialContextualAnalysisPreview")
            .WithTags("Content");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        string token,
        string? language,
        HttpContext httpContext,
        EditorialContextualAnalysisPreviewService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        httpContext.Response.Headers["Cache-Control"] = "no-store";

        try
        {
            var preview = await service.ReadAsync(
                actorId,
                recordingId,
                token,
                string.IsNullOrWhiteSpace(language) ? "es" : language,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return preview is null
                ? Results.NotFound()
                : Results.Ok(preview);
        }
        catch (EditorialContextualAnalysisPreviewException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Análisis DRAFT no disponible de forma segura",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
        }
        catch (LinguisticAnalysisAdministrationException exception)
        {
            var status = exception.Code == "content.analysis.recording.not-found"
                ? StatusCodes.Status404NotFound
                : StatusCodes.Status409Conflict;

            return Results.Problem(
                statusCode: status,
                title: "Análisis editorial no disponible",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Referencia de análisis DRAFT inválida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.analysis-preview.invalid-route"
                });
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
        catch (InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var value = context.User.FindFirstValue("account_id");

        return Guid.TryParse(value, out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Análisis DRAFT temporalmente no disponible",
            detail:
                "El borrador editorial permanece intacto. Vuelve a intentarlo cuando el servicio esté disponible.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "content.analysis-preview.unavailable"
            });
}
'@

Replace-Once `
    "apps/api/Program.cs" `
    @'
builder.Services.AddSingleton<EditorialKaraokePreviewService>();
builder.Services.AddSingleton<TranslationRevisionAdministrationService>();
'@ `
    @'
builder.Services.AddSingleton<EditorialKaraokePreviewService>();
builder.Services.AddSingleton<EditorialContextualAnalysisPreviewService>();
builder.Services.AddSingleton<TranslationRevisionAdministrationService>();
'@ `
    "registro del servicio editorial de análisis contextual"

Replace-Once `
    "apps/api/Program.cs" `
    @'
app.MapTimingRevisionAdministration();
app.MapEditorialKaraokePreview();
app.MapTranslationRevisionAdministration();
'@ `
    @'
app.MapTimingRevisionAdministration();
app.MapEditorialKaraokePreview();
app.MapEditorialContextualAnalysisPreview();
app.MapTranslationRevisionAdministration();
'@ `
    "mapeo del endpoint editorial de análisis contextual"

# -----------------------------------------------------------------------------
# Frontend: ContextualAnalysisPanel acepta fuente pública o editorial DRAFT.
# -----------------------------------------------------------------------------

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
export type ContextualAnalysisPanelProps = {
  slug: string;
  tokenKey: string | null;
  surfaceHint?: string | null;
  onClose?: () => void;
  showStandaloneLink?: boolean;
};
'@ `
    @'
export type ContextualAnalysisPanelProps = {
  slug?: string;
  editorialRecordingId?: string | null;
  tokenKey: string | null;
  surfaceHint?: string | null;
  onClose?: () => void;
  showStandaloneLink?: boolean;
};
'@ `
    "props para fuente editorial DRAFT"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
export function ContextualAnalysisPanel({
  slug,
  tokenKey,
  surfaceHint,
  onClose,
  showStandaloneLink = true,
}: ContextualAnalysisPanelProps) {
'@ `
    @'
export function ContextualAnalysisPanel({
  slug,
  editorialRecordingId = null,
  tokenKey,
  surfaceHint,
  onClose,
  showStandaloneLink = true,
}: ContextualAnalysisPanelProps) {
'@ `
    "desestructuración del modo editorial"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
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
'@ `
    @'
    const controller = new AbortController();
    const draftPreview = Boolean(editorialRecordingId);

    if (!draftPreview && !slug) {
      setState({ phase: 'unavailable' });
      return () => controller.abort();
    }

    setState({ phase: 'loading' });

    const load = async () => {
      const params = new URLSearchParams(
        draftPreview ? { language } : { territory, language },
      );
      const requestPath = draftPreview
        ? `/editorial/song-drafts/${encodeURIComponent(editorialRecordingId!)}/analysis-preview/${encodeURIComponent(tokenKey)}?${params.toString()}`
        : `/public/catalog/songs/${encodeURIComponent(slug!)}/analysis/${encodeURIComponent(tokenKey)}?${params.toString()}`;
      const result = await client.get<PublicContextualAnalysis>(requestPath, {
        cacheMode: 'no-store',
        retry: 'safe',
        signal: controller.signal,
      });
'@ `
    "resolución del endpoint según fuente"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
  }, [slug, tokenKey]);

  const readings = useMemo(
'@ `
    @'
  }, [editorialRecordingId, slug, tokenKey]);

  const readings = useMemo(
'@ `
    "dependencias de carga editorial"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
  const readings = useMemo(
    () => (state.phase === 'ready' ? orderedReadings(state.data.readings) : []),
    [state],
  );

  return (
'@ `
    @'
  const readings = useMemo(
    () => (state.phase === 'ready' ? orderedReadings(state.data.readings) : []),
    [state],
  );
  const draftPreview = Boolean(editorialRecordingId);

  return (
'@ `
    "bandera visual de DRAFT"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
          <p className="eyebrow">BL-MVP-068 · ANÁLISIS CONTEXTUAL</p>
          <h2 id="contextual-analysis-title">Comprende esta parte</h2>
          <p>
            Lectura, significado, forma, kanji y gramática proceden del análisis publicado
            compatible con esta letra.
          </p>
'@ `
    @'
          <p className="eyebrow">
            {draftPreview
              ? 'VISTA PREVIA DRAFT · ANÁLISIS CONTEXTUAL'
              : 'BL-MVP-068 · ANÁLISIS CONTEXTUAL'}
          </p>
          <h2 id="contextual-analysis-title">Comprende esta parte</h2>
          <p>
            {draftPreview
              ? 'Lectura, significado, forma, kanji y gramática proceden del análisis DRAFT compatible con esta misma revisión de letra. Nada se publica desde aquí.'
              : 'Lectura, significado, forma, kanji y gramática proceden del análisis publicado compatible con esta letra.'}
          </p>
'@ `
    "copy explícito de preview DRAFT"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
          description="Resolviendo el token dentro de la misma revisión publicada."
'@ `
    @'
          description={
            draftPreview
              ? 'Resolviendo el token dentro de la misma revisión editorial DRAFT.'
              : 'Resolviendo el token dentro de la misma revisión publicada.'
          }
'@ `
    "estado loading contextual"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
          description="Este token ya no pertenece a la publicación activa o no tiene análisis compatible. No se sustituye por otro."
'@ `
    @'
          description={
            draftPreview
              ? 'Este token ya no pertenece al borrador actual o no tiene análisis DRAFT compatible. No se sustituye por otra revisión.'
              : 'Este token ya no pertenece a la publicación activa o no tiene análisis compatible. No se sustituye por otro.'
          }
'@ `
    "estado unavailable contextual"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    '<EmptyDetail>Sin lectura contextual publicada para este token.</EmptyDetail>' `
    '<EmptyDetail>Sin lectura contextual registrada para este token.</EmptyDetail>' `
    "copy neutral de lectura"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
              description="El token es válido y pertenece a la publicación, pero todavía no tiene vocabulario, kanji, morfología o gramática autorizados."
'@ `
    @'
              description={
                draftPreview
                  ? 'El token pertenece al borrador actual, pero todavía no tiene vocabulario, kanji, morfología o gramática registrados en el análisis compatible.'
                  : 'El token es válido y pertenece a la publicación, pero todavía no tiene vocabulario, kanji, morfología o gramática autorizados.'
              }
'@ `
    "estado de detalle vacío según fuente"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    '<EmptyDetail>Sin glosa localizada publicada.</EmptyDetail>' `
    '<EmptyDetail>Sin glosa localizada registrada.</EmptyDetail>' `
    "copy neutral de glosa"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    '<summary>Ver definiciones adicionales publicadas</summary>' `
    '<summary>Ver definiciones adicionales</summary>' `
    "copy neutral de definiciones"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    '<EmptyDetail>Sin lectura general localizada publicada.</EmptyDetail>' `
    '<EmptyDetail>Sin lectura general localizada registrada.</EmptyDetail>' `
    "copy neutral de kanji"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    '<summary>Ver ejemplos publicados</summary>' `
    '<summary>Ver ejemplos registrados</summary>' `
    "copy neutral de ejemplos"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    '<EmptyDetail>Sin referencia pública adicional para mostrar.</EmptyDetail>' `
    '<EmptyDetail>Sin referencia adicional para mostrar.</EmptyDetail>' `
    "copy neutral de procedencia"

Replace-Once `
    "apps/web/src/routes/student/ContextualAnalysisPanel.tsx" `
    @'
          {showStandaloneLink ? (
            <AppLink
              href={`/aprender/${encodeURIComponent(slug)}/analisis/${encodeURIComponent(state.data.tokenKey)}`}
            >
              Abrir análisis en una vista independiente
            </AppLink>
          ) : null}
'@ `
    @'
          {showStandaloneLink && slug && !draftPreview ? (
            <AppLink
              href={`/aprender/${encodeURIComponent(slug)}/analisis/${encodeURIComponent(state.data.tokenKey)}`}
            >
              Abrir análisis en una vista independiente
            </AppLink>
          ) : null}
'@ `
    "deep link solo para contexto público"

# -----------------------------------------------------------------------------
# Frontend: preview editorial conecta tokens con el panel DRAFT.
# -----------------------------------------------------------------------------

Replace-Once `
    "apps/web/src/routes/editorial/EditorialKaraokePreview.tsx" `
    @'
import { SynchronizedYouTubePreview } from '../../features/player/synchronization/SynchronizedYouTubePreview';
import {
'@ `
    @'
import { SynchronizedYouTubePreview } from '../../features/player/synchronization/SynchronizedYouTubePreview';
import { ContextualAnalysisPanel } from '../student/ContextualAnalysisPanel';
import {
'@ `
    "import del panel contextual"

Replace-Once `
    "apps/web/src/routes/editorial/EditorialKaraokePreview.tsx" `
    @'
  EducationalKaraoke,
  defaultVisibleEducationalLayers,
  type EducationalLayers,
  type VisibleEducationalLayers,
'@ `
    @'
  EducationalKaraoke,
  defaultVisibleEducationalLayers,
  type EducationalAnalysisSelection,
  type EducationalLayers,
  type VisibleEducationalLayers,
'@ `
    "tipo de selección contextual"

Replace-Once `
    "apps/web/src/routes/editorial/EditorialKaraokePreview.tsx" `
    @'
  const [snapshot, setSnapshot] = useState<LocalSynchronizationSnapshot>(emptySnapshot);
  const [visibleLayers, setVisibleLayers] = useState<VisibleEducationalLayers>({
'@ `
    @'
  const [snapshot, setSnapshot] = useState<LocalSynchronizationSnapshot>(emptySnapshot);
  const [analysisSelection, setAnalysisSelection] = useState<EducationalAnalysisSelection | null>(
    null,
  );
  const [visibleLayers, setVisibleLayers] = useState<VisibleEducationalLayers>({
'@ `
    "estado de selección del panel DRAFT"

Replace-Once `
    "apps/web/src/routes/editorial/EditorialKaraokePreview.tsx" `
    @'
      setState({ phase: 'loading' });
      setSnapshot(emptySnapshot);
      setVisibleLayers({ ...defaultVisibleEducationalLayers });
'@ `
    @'
      setState({ phase: 'loading' });
      setSnapshot(emptySnapshot);
      setAnalysisSelection(null);
      setVisibleLayers({ ...defaultVisibleEducationalLayers });
'@ `
    "reset de selección al cambiar revisión/fuente"

Replace-Once `
    "apps/web/src/routes/editorial/EditorialKaraokePreview.tsx" `
    @'
            <div className="editorial-karaoke-preview__lyrics">
              <EducationalKaraoke
                layers={state.data.layers}
                snapshot={snapshot}
                visibleLayers={visibleLayers}
                onVisibleLayersChange={setVisibleLayers}
              />
            </div>
'@ `
    @'
            <div className="editorial-karaoke-preview__learning">
              <div className="editorial-karaoke-preview__lyrics">
                <EducationalKaraoke
                  layers={state.data.layers}
                  snapshot={snapshot}
                  visibleLayers={visibleLayers}
                  onVisibleLayersChange={setVisibleLayers}
                  selectedAnalysisKey={analysisSelection?.analysisKey ?? null}
                  onTokenAnalysis={setAnalysisSelection}
                />
              </div>

              <ContextualAnalysisPanel
                editorialRecordingId={recordingId}
                tokenKey={analysisSelection?.analysisKey ?? null}
                surfaceHint={analysisSelection?.surface ?? null}
                onClose={() => setAnalysisSelection(null)}
                showStandaloneLink={false}
              />
            </div>
'@ `
    "panel contextual dentro del preview editorial"

Append-Once `
    "apps/web/src/routes/editorial/editorial-karaoke-preview.css" `
    ".editorial-karaoke-preview__learning" `
@'
.editorial-karaoke-preview__learning {
  display: grid;
  gap: var(--ma-space-4);
  min-width: 0;
}

.editorial-karaoke-preview__learning > * {
  min-width: 0;
}
'@

# -----------------------------------------------------------------------------
# E2E editorial: selección real DRAFT, cero publicación y player estable.
# -----------------------------------------------------------------------------

Replace-Once `
    "tests/E2ETests/editorial-karaoke-preview.spec.ts" `
    @'
const sourceId = '16000000-0000-7000-8000-000000000003';
const videoId = 'a8dgNdJVluc';
'@ `
    @'
const sourceId = '16000000-0000-7000-8000-000000000003';
const videoId = 'a8dgNdJVluc';
const analysisKey = 'A1B2C3D4E5F60718293A';
'@ `
    "clave opaca del fixture editorial"

Replace-Once `
    "tests/E2ETests/editorial-karaoke-preview.spec.ts" `
    @'
            surface: '怪獣',
            startOffset: 0,
            endOffset: 2,
            readings: [
'@ `
    @'
            surface: '怪獣',
            startOffset: 0,
            endOffset: 2,
            analysisKey,
            readings: [
'@ `
    "token DRAFT analizable en fixture"

Replace-Once `
    "tests/E2ETests/editorial-karaoke-preview.spec.ts" `
    @'
const iframeApi = `
'@ `
    @'
const contextualAnalysis = {
  available: true,
  tokenKey: analysisKey,
  surface: '怪獣',
  tokenNo: 1,
  targetLanguage: 'es',
  line: {
    sectionOrder: 0,
    sectionLabel: 'Verso 1',
    lineNo: 1,
    japaneseText: '怪獣です',
    speakerLabel: null,
  },
  readings: [
    {
      readingKana: 'かいじゅう',
      furigana: 'かいじゅう',
      romaji: 'kaijū',
      readingType: 'PRIMARY',
    },
  ],
  vocabulary: [
    {
      lemma: '怪獣',
      reading: 'かいじゅう',
      partOfSpeech: 'NOUN',
      senseKey: 'monster',
      inflection: null,
      confidenceCode: 'CONFIRMED',
      senses: [
        {
          languageTag: 'es',
          definition: 'Monstruo o criatura gigantesca.',
          usageNote: 'Sentido usado en este borrador de la canción.',
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
          meaning: 'misterioso',
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
      grammarCode: 'N-です',
      title: '〜です',
      levelCode: 'N5',
      note: null,
      explanation: 'Marca una afirmación cortés.',
      examples: null,
    },
  ],
  provenance: [
    {
      sourceType: 'EDITORIAL',
      citation: 'Revisión lingüística interna',
      locator: 'token 1',
      contributionType: 'ANALYSIS',
    },
  ],
};

const iframeApi = `
'@ `
    "fixture de análisis contextual DRAFT"

Replace-Once `
    "tests/E2ETests/editorial-karaoke-preview.spec.ts" `
    @'
(() => {
  let currentTime = 0;
  let currentEvents = null;

  window.__karaokePreviewSeek = (seconds) => {
'@ `
    @'
(() => {
  let currentTime = 0;
  let currentEvents = null;

  window.__editorialKaraokePlayerConstructed = 0;
  window.__karaokePreviewSeek = (seconds) => {
'@ `
    "contador de construcción del player"

Replace-Once `
    "tests/E2ETests/editorial-karaoke-preview.spec.ts" `
    @'
    Player: function(element, options) {
      currentEvents = options.events;
'@ `
    @'
    Player: function(element, options) {
      window.__editorialKaraokePlayerConstructed += 1;
      currentEvents = options.events;
'@ `
    "incremento del contador del player"

Replace-Once `
    "tests/E2ETests/editorial-karaoke-preview.spec.ts" `
    @'
  await page.route('**/api/v1/editorial/song-drafts/*/karaoke-preview?**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(karaokePreview),
    });
  });

  await page.route('https://www.youtube-nocookie.com/embed/**', async (route) => {
'@ `
    @'
  await page.route('**/api/v1/editorial/song-drafts/*/karaoke-preview?**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(karaokePreview),
    });
  });

  await page.route('**/api/v1/editorial/song-drafts/*/analysis-preview/*?**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(contextualAnalysis),
    });
  });

  await page.route('https://www.youtube-nocookie.com/embed/**', async (route) => {
'@ `
    "mock del endpoint editorial de análisis"

Replace-Once `
    "tests/E2ETests/editorial-karaoke-preview.spec.ts" `
    @'
    await expect(page.locator('[data-karaoke-token="1"]')).toHaveAttribute('data-active', 'true');

    await page.getByRole('button', { name: 'Español' }).click();
'@ `
    @'
    await expect(page.locator('[data-karaoke-token="1"]')).toHaveAttribute('data-active', 'true');

    await page.getByRole('button', { name: 'Analizar 怪獣' }).click();
    const analysisPanel = page.locator('[data-contextual-analysis-panel]');
    await expect(analysisPanel).toBeVisible();
    await expect(analysisPanel.getByText('VISTA PREVIA DRAFT · ANÁLISIS CONTEXTUAL')).toBeVisible();
    await expect(analysisPanel.getByText('Monstruo o criatura gigantesca.')).toBeVisible();
    await expect(analysisPanel.getByText('かいじゅう', { exact: true }).first()).toBeVisible();

    await analysisPanel.getByText('Gramática de esta línea', { exact: true }).click();
    await expect(analysisPanel.getByText('〜です')).toBeVisible();

    const constructedPlayers = await page.evaluate(() => {
      const target = window as typeof window & {
        __editorialKaraokePlayerConstructed?: number;
      };
      return target.__editorialKaraokePlayerConstructed ?? 0;
    });
    expect(constructedPlayers).toBe(1);
    await expect(page.locator('[data-karaoke-token="1"]')).toHaveAttribute('data-active', 'true');

    await page.getByRole('button', { name: 'Español' }).click();
'@ `
    "smoke E2E de panel DRAFT sin remontar player"

Replace-Once `
    "tests/E2ETests/editorial-karaoke-preview.spec.ts" `
    @'
    await page.getByRole('button', { name: 'Previsualización de Karaoke' }).click();
    await expect(page.locator('[data-editorial-karaoke-preview]')).toBeVisible();

    const overflow = await page.evaluate(
'@ `
    @'
    await page.getByRole('button', { name: 'Previsualización de Karaoke' }).click();
    await expect(page.locator('[data-editorial-karaoke-preview]')).toBeVisible();
    await page.getByRole('button', { name: 'Analizar 怪獣' }).click();
    await expect(page.locator('[data-contextual-analysis-panel]')).toBeVisible();

    const overflow = await page.evaluate(
'@ `
    "panel DRAFT incluido en prueba 320px"

# -----------------------------------------------------------------------------
# CI/verifier y documentación.
# -----------------------------------------------------------------------------

Write-Utf8Lf `
    "scripts/ci/content/verify-editorial-contextual-analysis-preview.sh" `
@'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'ERROR BL-MVP-068 DRAFT PREVIEW: %s\n' "$1" >&2
  exit 1
}

endpoint="apps/api/Endpoints/Editorial/EditorialContextualAnalysisPreviewEndpoints.cs"
service="src/Modules/Content/Infrastructure/Administration/EditorialContextualAnalysisPreviewService.cs"
karaoke_service="src/Modules/Content/Infrastructure/Administration/EditorialKaraokePreviewService.cs"
panel="apps/web/src/routes/student/ContextualAnalysisPanel.tsx"
preview="apps/web/src/routes/editorial/EditorialKaraokePreview.tsx"
test_file="tests/E2ETests/editorial-karaoke-preview.spec.ts"

grep -Fq '/api/v1/editorial/song-drafts/{recordingId:guid}/analysis-preview/{token}' "$endpoint" \
  || fail "falta endpoint editorial de análisis preview"

grep -Fq 'RequireEffectivePermission(' "$endpoint" \
  || fail "endpoint editorial sin autorización efectiva"

grep -Fq '"EDITORIAL.DRAFT"' "$endpoint" \
  || fail "endpoint no queda limitado al permiso editorial"

grep -Fq 'LinguisticAnalysisRevisionAdministrationService' "$service" \
  || fail "preview no reutiliza el contexto lingüístico editorial"

grep -Fq 'PublicAnalysisTokenKey.Normalize' "$service" \
  || fail "preview no valida la referencia opaca"

grep -Fq 'revision.LyricsRevisionId != context.LyricsRevisionId' "$service" \
  || fail "preview no bloquea análisis incompatible"

grep -Fq 'HasStaleRevision' "$service" \
  || fail "preview no bloquea revisión stale"

if grep -Eq 'publication_component|published_package_projection|public/catalog' "$service"; then
  fail "el servicio DRAFT depende de publicación"
fi

grep -Fq 'string? AnalysisKey' "$karaoke_service" \
  || fail "karaoke DRAFT no expone clave opaca por token"

grep -Fq 'PublicAnalysisTokenKey.FromTokenId' "$karaoke_service" \
  || fail "karaoke DRAFT no deriva clave desde token canónico"

grep -Fq 'editorialRecordingId' "$panel" \
  || fail "panel contextual no admite fuente editorial"

grep -Fq '/editorial/song-drafts/' "$panel" \
  || fail "panel no llama endpoint editorial"

grep -Fq 'analysis-preview' "$panel" \
  || fail "panel no usa contrato DRAFT"

grep -Fq 'onTokenAnalysis={setAnalysisSelection}' "$preview" \
  || fail "preview no conecta selección de token"

grep -Fq '<ContextualAnalysisPanel' "$preview" \
  || fail "preview no reutiliza panel contextual"

grep -Fq 'showStandaloneLink={false}' "$preview" \
  || fail "preview DRAFT intenta abrir deep link público"

grep -Fq "name: 'Analizar 怪獣'" "$test_file" \
  || fail "E2E no selecciona token real"

grep -Fq '__editorialKaraokePlayerConstructed' "$test_file" \
  || fail "E2E no audita remontaje del player"

grep -Fq 'expect(constructedPlayers).toBe(1)' "$test_file" \
  || fail "E2E no exige un único montaje del player"

grep -Fq 'expect(publicRequests).toEqual([])' "$test_file" \
  || fail "E2E no exige cero llamadas públicas"

printf '%s\n' \
  "bl=BL-MVP-068" \
  "surface=editorial-draft-contextual-analysis-preview" \
  "draft_only=true" \
  "publication_required=false" \
  "public_slug_required=false" \
  "exact_lyrics_revision=true" \
  "exact_analysis_revision=true" \
  "opaque_token_key=true" \
  "reuses_contextual_panel=true" \
  "player_remount=false" \
  "public_catalog_requests=false" \
  "writes=false" \
  "publishes=false"

echo "OK: BL-MVP-068 análisis contextual DRAFT previsualizable sin publicar."
'@

Replace-Once `
    ".github/workflows/ci.yml" `
    @'
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
'@ `
    @'
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

      - name: Verify editorial DRAFT contextual analysis preview
        shell: bash
        run: bash scripts/ci/content/verify-editorial-contextual-analysis-preview.sh

      - name: Verify linguistic analysis editorial workspace
'@ `
    "puerta CI del preview contextual DRAFT"

Append-Once `
    "README/BL-MVP-068_README.md" `
    "## Previsualización editorial antes de publicar" `
@'
## Previsualización editorial antes de publicar

La lógica de publicación real todavía no es requisito para probar el panel manualmente.

El dossier editorial reutiliza `ContextualAnalysisPanel` dentro de **Previsualización de Karaoke** y consulta:

`GET /api/v1/editorial/song-drafts/{recordingId}/analysis-preview/{token}?language=es`

Este contrato:

- exige `EDITORIAL.DRAFT`;
- trabaja sobre la revisión de letra editorial más reciente y el análisis compatible exacto;
- rechaza análisis `stale` o de otra revisión;
- usa la misma referencia opaca de token que el reproductor educativo;
- no crea publicación;
- no necesita slug público;
- no consulta el catálogo público;
- no escribe datos;
- permite validar manualmente vocabulario, lectura, morfología, kanji, gramática y procedencia antes de implementar publicación.
'@

Append-Once `
    "docs/engineering/content/editorial-karaoke-preview.md" `
    "## Análisis contextual DRAFT" `
@'
## Análisis contextual DRAFT

La previsualización editorial también permite seleccionar tokens analizables. El karaoke recibe una referencia opaca derivada del token canónico y abre el mismo panel visual usado por el estudiante, pero con una fuente de datos editorial autenticada.

El panel editorial:

- consulta `/api/v1/editorial/song-drafts/{recordingId}/analysis-preview/{token}`;
- mantiene el reproductor de YouTube montado;
- no busca una publicación equivalente;
- nunca sustituye una revisión incompatible por la más reciente;
- no expone UUID de tokens a la interfaz;
- no habilita deep links públicos;
- conserva explícitamente la etiqueta `VISTA PREVIA DRAFT`.

Esto permite hacer el smoke manual de BL-MVP-068 antes de que exista el flujo de publicación.
'@

# El instalador original BL068 fue accidentalmente incluido en el commit base.
# Según la disciplina del proyecto, los apply-*.ps1 temporales no deben quedar versionados.
$trackedOldInstaller = Join-Path $script:Root "scripts/apply-bl-mvp-068-contextual-analysis-panel.ps1"
if (Test-Path $trackedOldInstaller -PathType Leaf) {
    Remove-Item -Force $trackedOldInstaller
    Write-Host "OK: se elimina del working tree el instalador temporal BL068 que quedó trackeado."
}

& git.exe diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check detectó problemas."
}

Write-Host ""
Write-Host "OK: preview editorial DRAFT de análisis contextual aplicado."
Write-Host "No se ejecutó git add, commit ni push."
Write-Host "Este instalador también es temporal: debe borrarse antes del staging."
