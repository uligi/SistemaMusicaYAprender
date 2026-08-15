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
