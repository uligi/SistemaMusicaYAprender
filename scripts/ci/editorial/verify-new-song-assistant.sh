#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

fail_check() {
  echo "ERROR: BL-MVP-045: $1" >&2
  exit 1
}

grep -Fq 'data-route-id="UI-MVP-018"' \
  apps/web/src/routes/editorial/NewSongAssistantPage.tsx \
  || fail_check "UI-MVP-018 no está marcada como asistente real."

grep -Fq "NewSongAssistantPage" \
  apps/web/src/routes/editorial/EditorialArea.tsx \
  || fail_check "EditorialArea no carga el asistente."

grep -Fq "path: '/editorial/canciones/nueva'" \
  apps/web/src/app/router/route-manifest.ts \
  || fail_check "La ruta aprobada UI-MVP-018 cambió."

for step in \
  "1. Artista canónico" \
  "2. Obra, grabación y fuente" \
  "3. Borrador guardado"; do
  grep -Fq "$step" \
    apps/web/src/routes/editorial/NewSongAssistantPage.tsx \
    apps/web/src/routes/editorial/ArtistAdministrationPage.tsx \
    apps/web/src/routes/editorial/SongDraftComposer.tsx \
    || fail_check "Falta el paso '$step'."
done

grep -Fq "'/editorial/artists" \
  apps/web/src/routes/editorial/ArtistAdministrationPage.tsx \
  || fail_check "El paso de artista no usa el servicio publicado."

grep -Fq "'/editorial/song-drafts" \
  apps/web/src/routes/editorial/SongDraftComposer.tsx \
  || fail_check "El paso de borrador no usa el servicio publicado."

grep -Fq "/derechos" \
  apps/web/src/routes/editorial/SongDraftComposer.tsx \
  || fail_check "El borrador no ofrece continuidad hacia derechos y procedencia."

if grep -Eq 'Npgsql|SELECT[[:space:]]|INSERT[[:space:]]|UPDATE[[:space:]]|DELETE[[:space:]]' \
  apps/web/src/routes/editorial/NewSongAssistantPage.tsx \
  apps/web/src/routes/editorial/ArtistAdministrationPage.tsx \
  apps/web/src/routes/editorial/SongDraftComposer.tsx; then
  fail_check "El frontend contiene acceso directo a datos."
fi

if grep -Eq '>Publicar<|aria-label="Publicar"|name: .Publicar.' \
  apps/web/src/routes/editorial/NewSongAssistantPage.tsx \
  apps/web/src/routes/editorial/SongDraftComposer.tsx; then
  fail_check "BL045 no debe adelantar una acción de publicación."
fi

echo "route=/editorial/canciones/nueva"
echo "ui=UI-MVP-018"
echo "steps=artist,work-recording-source,draft-confirmed"
echo "direct_database_edit=false"
echo "publishes=false"
echo "OK: BL-MVP-045 asistente, mínimos canónicos, borrador y continuidad editorial verificados."
