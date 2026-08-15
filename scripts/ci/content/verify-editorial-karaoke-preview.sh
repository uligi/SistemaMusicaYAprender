#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'ERROR BL-MVP-060/063 PREVIEW: %s\n' "$1" >&2
  exit 1
}

endpoint="apps/api/Endpoints/Editorial/EditorialKaraokePreviewEndpoints.cs"
service="src/Modules/Content/Infrastructure/Administration/EditorialKaraokePreviewService.cs"
page="apps/web/src/routes/editorial/SynchronizationStructurePage.tsx"
component="apps/web/src/routes/editorial/EditorialKaraokePreview.tsx"
test_file="tests/E2ETests/editorial-karaoke-preview.spec.ts"

grep -Fq '/api/v1/editorial/song-drafts/{recordingId:guid}/karaoke-preview' "$endpoint" \
  || fail "falta endpoint editorial de preview"

grep -Fq 'RequireEffectivePermission(' "$endpoint" \
  || fail "preview editorial sin permiso efectivo"

grep -Fq '"EDITORIAL.DRAFT"' "$endpoint" \
  || fail "preview no queda limitado al espacio editorial"

grep -Fq 'LyricsStructureAdministrationService' "$service" \
  || fail "no reutiliza revision exacta de letra"

grep -Fq 'TimingRevisionAdministrationService' "$service" \
  || fail "no reutiliza sincronizacion DRAFT"

grep -Fq 'TranslationRevisionAdministrationService' "$service" \
  || fail "no reutiliza traduccion compatible"

grep -Fq 'LinguisticAnalysisRevisionAdministrationService' "$service" \
  || fail "no reutiliza analisis compatible"

if grep -Eq 'publication|published_package_projection|public/catalog|PublicSongLearningLayersService' "$service"; then
  fail "el servicio editorial depende de publicacion"
fi

grep -Fq 'Revisión de sincronización' "$page" \
  || fail "falta primer panel"

grep -Fq 'Previsualización de Karaoke' "$page" \
  || fail "falta segundo panel"

grep -Fq 'VISTA PREVIA EDITORIAL · NO PUBLICA' "$component" \
  || fail "falta advertencia visible de no publicacion"

grep -Fq '<EducationalKaraoke' "$component" \
  || fail "preview no reutiliza el karaoke del estudiante"

grep -Fq 'presentation="learning"' "$component" \
  || fail "preview no reutiliza presentacion educativa del player"

grep -Fq "/api/v1/public/" "$test_file" \
  || fail "E2E no audita ausencia de llamadas publicas"

grep -Fq "expect(publicRequests).toEqual([])" "$test_file" \
  || fail "E2E no exige cero llamadas publicas"

printf '%s\n' \
  "bl=BL-MVP-060/063" \
  "surface=UI-MVP-022" \
  "panels=synchronization-review,karaoke-preview" \
  "draft_only=true" \
  "publication_required=false" \
  "public_slug_required=false" \
  "reuses_student_karaoke=true" \
  "reuses_local_sync=true" \
  "external_linguistic_api=false"

echo "OK: previsualizacion editorial de karaoke DRAFT sin publicar verificada."