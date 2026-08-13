[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "c5ec099d1c4632e9503bc48305246062e6cb6cd9"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-055.md",
    "README/BL-MVP-055_README.md",
    "apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs",
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx",
    "apps/web/src/routes/editorial/LyricsTokenSegmentationEditor.tsx",
    "apps/web/src/routes/editorial/lyrics-token-segmentation.css",
    "docs/engineering/content/lyrics-token-segmentation.md",
    "scripts/apply-bl-mvp-055.ps1",
    "scripts/ci/content/verify-lyrics-token-segmentation.sh",
    "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs",
    "tests/E2ETests/lyrics-token-segmentation.spec.ts"
)

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Resolve-GitBash {
    foreach ($candidate in @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe"
    )) {
        if (Test-Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "No se encontro Git Bash real."
}

function Read-Normalized([string]$RelativePath) {
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Falta $RelativePath."
    }

    return ([System.IO.File]::ReadAllText(
        $path,
        [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8NoBomLf([string]$RelativePath, [string]$Content) {
    [System.IO.File]::WriteAllText(
        (Join-Path $RepoRoot $RelativePath),
        $Content.Replace("`r`n", "`n").Replace("`r", "`n"),
        [System.Text.UTF8Encoding]::new($false))
}

function Replace-ExactOnce(
    [string]$RelativePath,
    [string]$OldText,
    [string]$NewText,
    [string]$AlreadyMarker,
    [string]$Description) {

    $content = Read-Normalized $RelativePath

    if ($content.Contains($AlreadyMarker)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $first = $content.IndexOf($OldText, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "No se encontro el bloque esperado para $Description en $RelativePath."
    }

    $second = $content.IndexOf(
        $OldText,
        $first + $OldText.Length,
        [System.StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "El bloque de $Description aparece mas de una vez en $RelativePath."
    }

    $updated = $content.Remove($first, $OldText.Length).Insert($first, $NewText)
    Write-Utf8NoBomLf $RelativePath $updated
    Write-Host "OK: $Description aplicado."
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"

    git ls-files --error-unmatch -- $relativePath *> $null
    if ($LASTEXITCODE -ne 0) {
        $global:LASTEXITCODE = 0
        return
    }

    $status = git status --porcelain=v1 -- $relativePath
    if ($status) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restaurar tsbuildinfo"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
}

function Get-ChangedPaths {
    $tracked = @(git diff --name-only)
    Assert-LastExitCode "Leer cambios tracked"
    $untracked = @(git ls-files --others --exclude-standard)
    Assert-LastExitCode "Leer cambios untracked"

    return @(
        $tracked + $untracked |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Assert-InventorySubset {
    $allowed = @{}
    foreach ($path in $PermanentPaths) {
        $allowed[$path] = $true
    }

    foreach ($path in Get-ChangedPaths) {
        if (-not $allowed.ContainsKey($path)) {
            throw "Ruta fuera del inventario BL-MVP-055: $path"
        }
    }
}

Write-Host "BL-MVP-055: segmentacion y correccion manual de tokens..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"

if ($head -cne $ExpectedBase) {
    throw "BL-MVP-055 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"

if ($branch -cne "main") {
    throw "BL-MVP-055 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"

if ($staged.Count -gt 0) {
    throw "BL-MVP-055 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object {
    $_ -notin @(
        ".github/workflows/ci.yml",
        "apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs",
        "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx",
        "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs"
    )
}) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}

# -----------------------------------------------------------------------
# Backend: impact snapshot + query.
# -----------------------------------------------------------------------
Replace-ExactOnce `
    "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs" `
    @'
public sealed record LyricsRevisionSnapshot(
    Guid LyricsRevisionId,
    Guid RecordingId,
    int RevisionNo,
    Guid? ParentRevisionId,
    string StatusCode,
    Guid CreatedBy,
    DateTime CreatedAt,
    string ChecksumSha256,
    long Version,
    List<LyricsSectionSnapshot> Sections);

'@ `
    @'
public sealed record LyricsRevisionSnapshot(
    Guid LyricsRevisionId,
    Guid RecordingId,
    int RevisionNo,
    Guid? ParentRevisionId,
    string StatusCode,
    Guid CreatedBy,
    DateTime CreatedAt,
    string ChecksumSha256,
    long Version,
    List<LyricsSectionSnapshot> Sections);

public sealed record LyricsSegmentationImpactSnapshot(
    Guid LyricsRevisionId,
    long TimingRevisionCount,
    long TranslationRevisionCount,
    long AnalysisRevisionCount)
{
    public bool HasImpact =>
        TimingRevisionCount > 0
        || TranslationRevisionCount > 0
        || AnalysisRevisionCount > 0;
}

'@ `
    "LyricsSegmentationImpactSnapshot" `
    "contrato de impacto de segmentacion"

$impactMethod = @'
    public Task<LyricsSegmentationImpactSnapshot> ReadSegmentationImpactAsync(
        Guid actorAccountId,
        Guid recordingId,
        Guid lyricsRevisionId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(
            actorAccountId,
            recordingId,
            correlationId);

        if (lyricsRevisionId == Guid.Empty)
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.revision.invalid",
                "La revisión indicada no es válida.");
        }

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                const string sql = """
                    SELECT
                        EXISTS (
                            SELECT 1
                            FROM content.lyrics_revision AS revision
                            WHERE revision.lyrics_revision_id = @lyrics_revision_id
                              AND revision.recording_id = @recording_id
                        ),
                        (
                            SELECT count(*)
                            FROM content.timing_revision AS timing
                            WHERE timing.lyrics_revision_id = @lyrics_revision_id
                        ),
                        (
                            SELECT count(*)
                            FROM content.translation_revision AS translation
                            WHERE translation.lyrics_revision_id = @lyrics_revision_id
                        ),
                        (
                            SELECT count(*)
                            FROM content.linguistic_analysis_revision AS analysis
                            WHERE analysis.lyrics_revision_id = @lyrics_revision_id
                        );
                    """;

                await using var command =
                    new NpgsqlCommand(
                        sql,
                        connection,
                        transaction);

                command.Parameters.AddWithValue(
                    "lyrics_revision_id",
                    NpgsqlDbType.Uuid,
                    lyricsRevisionId);
                command.Parameters.AddWithValue(
                    "recording_id",
                    NpgsqlDbType.Uuid,
                    recordingId);

                await using var reader =
                    await command.ExecuteReaderAsync(token);

                if (!await reader.ReadAsync(token)
                    || !reader.GetBoolean(0))
                {
                    throw new LyricsStructureAdministrationException(
                        "content.lyrics.revision.not-found",
                        "La revisión de letra no pertenece a la grabación indicada.");
                }

                return new LyricsSegmentationImpactSnapshot(
                    lyricsRevisionId,
                    reader.GetInt64(1),
                    reader.GetInt64(2),
                    reader.GetInt64(3));
            },
            cancellationToken);
    }

'@

Replace-ExactOnce `
    "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs" `
    @'
    public Task<LyricsRevisionSnapshot> CreateRevisionAsync(
'@ `
    ($impactMethod + @'
    public Task<LyricsRevisionSnapshot> CreateRevisionAsync(
'@) `
    "ReadSegmentationImpactAsync(" `
    "consulta de impacto de segmentacion"

# Protect Unicode surrogate boundaries server-side.
Replace-ExactOnce `
    "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs" `
    @'
            if (sourceToken.StartOffset < 0
                || sourceToken.EndOffset <= sourceToken.StartOffset
                || sourceToken.EndOffset > original.Length)
'@ `
    @'
            if (sourceToken.StartOffset < 0
                || sourceToken.EndOffset <= sourceToken.StartOffset
                || sourceToken.EndOffset > original.Length
                || !IsUtf16Boundary(original, sourceToken.StartOffset)
                || !IsUtf16Boundary(original, sourceToken.EndOffset))
'@ `
    "IsUtf16Boundary(original, sourceToken.StartOffset)" `
    "limites UTF-16 de token"

$utf16Helper = @'
    private static bool IsUtf16Boundary(
        string text,
        int index)
    {
        if (index <= 0 || index >= text.Length)
        {
            return true;
        }

        return !(char.IsHighSurrogate(text[index - 1])
                 && char.IsLowSurrogate(text[index]));
    }

'@

Replace-ExactOnce `
    "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs" `
    @'
    private static string? NormalizeOptional(
'@ `
    ($utf16Helper + @'
    private static string? NormalizeOptional(
'@) `
    "private static bool IsUtf16Boundary(" `
    "helper UTF-16"

# -----------------------------------------------------------------------
# API: impact route.
# -----------------------------------------------------------------------
$impactRoute = @'
        endpoints.MapGet(
                "/api/v1/editorial/song-drafts/{recordingId:guid}/lyrics-revisions/{lyricsRevisionId:guid}/segmentation-impact",
                ReadSegmentationImpactAsync)
            .RequireEffectivePermission(
                "EDITORIAL.DRAFT",
                moduleCode: "M03",
                routeObjectKey: "recordingId")
            .WithName("ReadEditorialLyricsSegmentationImpact")
            .WithTags("Content");

'@

Replace-ExactOnce `
    "apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs" `
    @'
        endpoints.MapPost(
'@ `
    ($impactRoute + @'
        endpoints.MapPost(
'@) `
    "ReadEditorialLyricsSegmentationImpact" `
    "ruta impacto de segmentacion"

$impactEndpoint = @'
    private static async Task<IResult> ReadSegmentationImpactAsync(
        Guid recordingId,
        Guid lyricsRevisionId,
        HttpContext httpContext,
        LyricsStructureAdministrationService service)
    {
        if (!TryActor(
                httpContext,
                out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var impact =
                await service.ReadSegmentationImpactAsync(
                    actorId,
                    recordingId,
                    lyricsRevisionId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            return Results.Ok(impact);
        }
        catch (LyricsStructureAdministrationException exception)
        {
            return Problem(exception);
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

'@

Replace-ExactOnce `
    "apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs" `
    @'
    private static async Task<IResult> CreateAsync(
'@ `
    ($impactEndpoint + @'
    private static async Task<IResult> CreateAsync(
'@) `
    "Guid lyricsRevisionId," `
    "endpoint impacto de segmentacion"

Replace-ExactOnce `
    "apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs" `
    @'
                "content.lyrics.recording.not-found" =>
                    StatusCodes.Status404NotFound,
'@ `
    @'
                "content.lyrics.recording.not-found" =>
                    StatusCodes.Status404NotFound,
                "content.lyrics.revision.not-found" =>
                    StatusCodes.Status404NotFound,
'@ `
    '"content.lyrics.revision.not-found"' `
    "404 revision fuera de grabacion"

# -----------------------------------------------------------------------
# UI: token state, serialization and impact warning.
# -----------------------------------------------------------------------
Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
import type { LyricsRevision, LyricsStructureResponse } from './LyricsStructurePage';
import './lyrics-structured-editor.css';
'@ `
    @'
import type { LyricsRevision, LyricsStructureResponse } from './LyricsStructurePage';
import {
  editableTokensFromRevision,
  LyricsTokenSegmentationEditor,
  serializeTokenRanges,
  validateTokenRanges,
  type EditableTokenRange,
} from './LyricsTokenSegmentationEditor';
import './lyrics-structured-editor.css';
'@ `
    "LyricsTokenSegmentationEditor" `
    "import segmentador manual"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
type EditorLine = {
  clientId: string;
  japaneseText: string;
  speakerLabel: string;
  unknownContentCode: UnknownContentCode;
};
'@ `
    @'
type EditorLine = {
  clientId: string;
  japaneseText: string;
  speakerLabel: string;
  unknownContentCode: UnknownContentCode;
  tokens: EditableTokenRange[];
};
'@ `
    "tokens: EditableTokenRange[]" `
    "tokens editables por linea"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
    speakerLabel: '',
    unknownContentCode: '',
  };
'@ `
    @'
    speakerLabel: '',
    unknownContentCode: '',
    tokens: [],
  };
'@ `
    "unknownContentCode: '',`n    tokens: []" `
    "tokens en nueva linea"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
          speakerLabel: line.speakerLabel ?? '',
          unknownContentCode,
        };
'@ `
    @'
          speakerLabel: line.speakerLabel ?? '',
          unknownContentCode,
          tokens: editableTokensFromRevision(line.tokens),
        };
'@ `
    "editableTokensFromRevision(line.tokens)" `
    "tokens desde revision vigente"

$tokenValidation = @'
      if (!line.unknownContentCode)
      {
        validateTokenRanges(line.japaneseText, line.tokens).forEach((message, tokenIndex) =>
          errors.push({
            key: `section-${sectionIndex}-line-${lineIndex}-token-${tokenIndex}`,
            message,
          }),
        );
      }

      if (line.unknownContentCode && line.tokens.length > 0)
      {
        errors.push({
          key: `section-${sectionIndex}-line-${lineIndex}-unknown-tokens`,
          message: `La línea ${lineIndex + 1} no puede conservar tokens si el contenido es desconocido.`,
        });
      }
'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
      if (line.unknownContentCode && line.japaneseText) {
        errors.push({
          key: `section-${sectionIndex}-line-${lineIndex}-unknown`,
          message: `La línea ${lineIndex + 1} no puede mezclar texto inventado con una marca de contenido desconocido.`,
        });
      }
'@ `
    (@'
      if (line.unknownContentCode && line.japaneseText) {
        errors.push({
          key: `section-${sectionIndex}-line-${lineIndex}-unknown`,
          message: `La línea ${lineIndex + 1} no puede mezclar texto inventado con una marca de contenido desconocido.`,
        });
      }

'@ + $tokenValidation) `
    "unknown-tokens" `
    "validacion de rangos de tokens"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
        speakerLabel: line.speakerLabel.trim() || null,
        tokens: [],
'@ `
    @'
        speakerLabel: line.speakerLabel.trim() || null,
        tokens: line.unknownContentCode
          ? []
          : serializeTokenRanges(line.japaneseText, line.tokens),
'@ `
    "serializeTokenRanges(line.japaneseText, line.tokens)" `
    "serializacion de tokens exactos"

$impactType = @'
type SegmentationImpact = {
  lyricsRevisionId: string;
  timingRevisionCount: number;
  translationRevisionCount: number;
  analysisRevisionCount: number;
  hasImpact: boolean;
};

'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
type Csrf = {
'@ `
    ($impactType + @'
type Csrf = {
'@) `
    "type SegmentationImpact =" `
    "tipo impacto frontend"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
  const [comparisonError, setComparisonError] = useState('');
'@ `
    @'
  const [comparisonError, setComparisonError] = useState('');
  const [segmentationChanged, setSegmentationChanged] = useState(false);
  const [segmentationImpact, setSegmentationImpact] =
    useState<SegmentationImpact | null>(null);
  const [segmentationImpactError, setSegmentationImpactError] = useState('');
'@ `
    "segmentationChanged" `
    "estado impacto frontend"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
    setComparisonError('');
    setMutation((current) => (current?.phase === 'confirmed' ? current : null));
  }, [etag, revision]);
'@ `
    @'
    setComparisonError('');
    setSegmentationChanged(false);
    setSegmentationImpact(null);
    setSegmentationImpactError('');
    setMutation((current) => (current?.phase === 'confirmed' ? current : null));
  }, [etag, revision]);
'@ `
    "setSegmentationChanged(false);" `
    "reset impacto al cambiar revision"

$impactEffect = @'
  useEffect(() => {
    if (!revision)
    {
      return;
    }

    const controller = new AbortController();

    const loadImpact = async () =>
    {
      const result = await client.get<SegmentationImpact>(
        `/editorial/song-drafts/${encodeURIComponent(
          recordingId,
        )}/lyrics-revisions/${encodeURIComponent(
          revision.lyricsRevisionId,
        )}/segmentation-impact`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled')
      {
        return;
      }

      if (result.ok)
      {
        setSegmentationImpact(result.data);
        setSegmentationImpactError('');
        return;
      }

      setSegmentationImpact(null);
      setSegmentationImpactError(result.problem.correction);
    };

    void loadImpact();
    return () => controller.abort();
  }, [recordingId, revision]);

'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
  const errors = useMemo(() => validate(draft), [draft]);
'@ `
    ($impactEffect + @'
  const errors = useMemo(() => validate(draft), [draft]);
'@) `
    "/segmentation-impact" `
    "carga impacto de revision"

$updateTokens = @'
  function updateLineTokens(
    sectionIndex: number,
    lineIndex: number,
    tokens: EditableTokenRange[],
  )
  {
    setDraft((current) => ({
      sections: current.sections.map((section, position) =>
      {
        if (position !== sectionIndex) return section;

        return {
          ...section,
          lines: section.lines.map((line, linePosition) =>
            linePosition === lineIndex ? { ...line, tokens } : line,
          ),
        };
      }),
    }));
    setSegmentationChanged(true);
    markChanged();
  }

'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
  function addSection() {
'@ `
    ($updateTokens + @'
  function addSection() {
'@) `
    "function updateLineTokens(" `
    "mutacion de tokens"

$updateJapaneseText = @'
  function updateJapaneseText(
    sectionIndex: number,
    lineIndex: number,
    value: string,
  ) {
    const normalizedValue = value.replace(/\r\n?/g, '\n');
    const logicalLines = normalizedValue.split('\n');

    if (
      logicalLines.length > 1 &&
      logicalLines[logicalLines.length - 1] === ''
    ) {
      logicalLines.pop();
    }

    setDraft((current) => ({
      sections: current.sections.map((section, position) => {
        if (position !== sectionIndex) return section;

        const sourceLine = section.lines[lineIndex];
        if (!sourceLine) return section;

        if (logicalLines.length <= 1) {
          return {
            ...section,
            lines: section.lines.map((line, linePosition) =>
              linePosition === lineIndex
                ? {
                    ...line,
                    japaneseText: normalizedValue,
                    tokens: [],
                  }
                : line,
            ),
          };
        }

        const replacementLines = logicalLines.map((japaneseText, logicalIndex) =>
          logicalIndex === 0
            ? {
                ...sourceLine,
                japaneseText,
                unknownContentCode: '' as UnknownContentCode,
                tokens: [],
              }
            : {
                ...newLine(),
                japaneseText,
              },
        );

        return {
          ...section,
          lines: [
            ...section.lines.slice(0, lineIndex),
            ...replacementLines,
            ...section.lines.slice(lineIndex + 1),
          ],
        };
      }),
    }));

    setSegmentationChanged(true);
    markChanged();
  }

'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
  function addSection() {
'@ `
    ($updateJapaneseText + @'
  function addSection() {
'@) `
    "function updateJapaneseText(" `
    "una linea editorial por salto de linea"

# Clearing a line as unknown must also clear token anchors.
Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
                          Se conserva exactamente como lo escribes. No introduzcas una suposición si
                          el audio no se entiende.
'@ `
    @'
                          Cada salto de línea crea una línea editorial independiente. El texto se
                          conserva exactamente; no introduzcas una suposición si el audio no se entiende.
'@ `
    "Cada salto de línea crea una línea editorial independiente." `
    "ayuda de pegado multilínea"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
                          onChange={(event) =>
                            updateLine(sectionIndex, lineIndex, {
                              japaneseText: event.target.value,
                            })
                          }
'@ `
    @'
                          onChange={(event) =>
                            updateJapaneseText(
                              sectionIndex,
                              lineIndex,
                              event.target.value,
                            )
                          }
'@ `
    "updateJapaneseText(`n                              sectionIndex," `
    "distribucion de saltos de linea"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
                              ...(unknownContentCode ? { japaneseText: '' } : {}),
'@ `
    @'
                              ...(unknownContentCode
                                ? { japaneseText: '', tokens: [] }
                                : {}),
'@ `
    "japaneseText: '', tokens: []" `
    "contenido desconocido sin tokens"

$tokenComponent = @'
                      <LyricsTokenSegmentationEditor
                        japaneseText={line.japaneseText}
                        tokens={line.tokens}
                        disabled={Boolean(line.unknownContentCode)}
                        onChange={(tokens) =>
                          updateLineTokens(sectionIndex, lineIndex, tokens)
                        }
                      />
'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
                      </div>
                    </article>
'@ `
    (@'
                      </div>

'@ + $tokenComponent + @'
                    </article>
'@) `
    "<LyricsTokenSegmentationEditor" `
    "segmentador por linea"

$impactUi = @'
      {segmentationChanged && revision ? (
        <section
          className="lyrics-editor__segmentation-impact"
          aria-labelledby="lyrics-segmentation-impact-title"
          role="status"
        >
          <h3 id="lyrics-segmentation-impact-title">Impacto de la segmentación</h3>
          <p>
            Esta corrección creará una nueva revisión. Las relaciones de la revisión
            actual no se migran ni se consideran compatibles automáticamente.
          </p>

          {segmentationImpact ? (
            <ul>
              <li>
                Sincronización: {segmentationImpact.timingRevisionCount}{' '}
                {segmentationImpact.timingRevisionCount === 1
                  ? 'revisión relacionada'
                  : 'revisiones relacionadas'}
              </li>
              <li>
                Traducciones: {segmentationImpact.translationRevisionCount}{' '}
                {segmentationImpact.translationRevisionCount === 1
                  ? 'revisión relacionada'
                  : 'revisiones relacionadas'}
              </li>
              <li>
                Análisis: {segmentationImpact.analysisRevisionCount}{' '}
                {segmentationImpact.analysisRevisionCount === 1
                  ? 'revisión relacionada'
                  : 'revisiones relacionadas'}
              </li>
            </ul>
          ) : segmentationImpactError ? (
            <p>
              No fue posible resolver el impacto completo. No asumas que los vínculos
              actuales siguen siendo válidos: {segmentationImpactError}
            </p>
          ) : (
            <p>Revisando relaciones temporales, traducciones y análisis…</p>
          )}
        </section>
      ) : null}

'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
      <ol className="lyrics-editor__sections">
'@ `
    ($impactUi + @'
      <ol className="lyrics-editor__sections">
'@) `
    "lyrics-segmentation-impact-title" `
    "advertencia de impacto"

# When explicitly adopting the server, local segmentation is no longer dirty.
Replace-ExactOnce `
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx" `
    @'
    setMutation(null);
    setProblem(null);
    setComparison(null);
  }

  function rebaseLocalVersion()
'@ `
    @'
    setMutation(null);
    setProblem(null);
    setComparison(null);
    setSegmentationChanged(false);
  }

  function rebaseLocalVersion()
'@ `
    "setSegmentationChanged(false);`n  }`n`n  function rebaseLocalVersion" `
    "reset segmentacion al adoptar servidor"

# -----------------------------------------------------------------------
# CI.
# -----------------------------------------------------------------------
$ciOld = @'
      - name: Verify structured Japanese lyrics editor
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL054_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-lyrics-structured-editor.sh
'@

$ciNew = @'
      - name: Verify structured Japanese lyrics editor
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL054_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-lyrics-structured-editor.sh

      - name: Verify manual lyrics token segmentation
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL055_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-lyrics-token-segmentation.sh
'@

Replace-ExactOnce `
    ".github/workflows/ci.yml" `
    $ciOld `
    $ciNew `
    "Verify manual lyrics token segmentation" `
    "puerta CI BL-MVP-055"

$formatTargets = @(
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx",
    "apps/web/src/routes/editorial/LyricsTokenSegmentationEditor.tsx",
    "apps/web/src/routes/editorial/lyrics-token-segmentation.css",
    "tests/E2ETests/lyrics-token-segmentation.spec.ts",
    "README/BL-MVP-055_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-055.md",
    "docs/engineering/content/lyrics-token-segmentation.md"
)

npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL055"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/content/verify-lyrics-token-segmentation.sh"
Assert-LastExitCode "bash -n BL055"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes del Playwright focal..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Build frontend focal BL055"

Write-Host "Ejecutando Playwright focal BL053/054/055..."
npm.cmd run test:e2e -- tests/E2ETests/lyrics-structure.spec.ts tests/E2ETests/lyrics-structured-editor.spec.ts tests/E2ETests/lyrics-token-segmentation.spec.ts
Assert-LastExitCode "Playwright focal BL055"

Restore-GeneratedTypeScriptState

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para BL-MVP-055..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL055"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-055..."
    & "$RepoRoot/scripts/local/ensure-local-secrets.ps1"
    & "$RepoRoot/scripts/local/sync-postgres-secret.ps1"
    & "$RepoRoot/scripts/database/apply-bootstrap.ps1"
    & "$RepoRoot/scripts/database/apply-login-identities.ps1"
    & "$RepoRoot/scripts/database/apply-initial-migration.ps1"

    $database = "musica_aprender"
    $databaseUser = "musica_local"

    if (Test-Path ".env") {
        foreach ($line in Get-Content ".env") {
            if ($line -match '^POSTGRES_DB=(.+)$') {
                $database = $Matches[1].Trim()
            }
            if ($line -match '^POSTGRES_USER=(.+)$') {
                $databaseUser = $Matches[1].Trim()
            }
        }
    }

    $previousEnv = @{
        PGHOST = $env:PGHOST
        PGPORT = $env:PGPORT
        PGUSER = $env:PGUSER
        PGPASSWORD = $env:PGPASSWORD
        PGDATABASE = $env:PGDATABASE
        BL055_USE_DOCKER_PSQL = $env:BL055_USE_DOCKER_PSQL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL055_USE_DOCKER_PSQL = "true"

        & $bash "scripts/ci/content/verify-lyrics-token-segmentation.sh"
        Assert-LastExitCode "Smoke BL-MVP-055"
    }
    finally {
        foreach ($name in $previousEnv.Keys) {
            $value = $previousEnv[$name]
            if ($null -eq $value) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$name" $value
            }
        }
    }
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

git diff --check
Assert-LastExitCode "git diff --check BL055"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-055 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-055 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 12 rutas BL-MVP-055."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-055 instalado y validado localmente."
Write-Host "Incluye offsets UTF-16, superficie exacta, union de tokens e impacto de relaciones."
Write-Host "No crea tablas nuevas, no migra relaciones automaticamente y no publica."
Write-Host "PENDIENTE: reinicio normal y revision visual real de UI-MVP-021 antes de staging."
Write-Host "No se ejecuto git add, commit ni push."
