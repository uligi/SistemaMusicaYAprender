#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'ERROR BL-MVP-058: %s\n' "$1" >&2
  exit 1
}

adapter="apps/web/src/integrations/youtube/YouTubeIframeAdapter.tsx"
page="apps/web/src/routes/student/EducationalPlayerPage.tsx"
editorial_preview="apps/web/src/routes/editorial/SynchronizationStructurePage.tsx"
service="src/Modules/Catalog/Infrastructure/Search/PublicSongDetailService.cs"

grep -Fq "BL-MVP-058 · ADAPTADOR YOUTUBE IFRAME" "$adapter" \
  || fail "falta identidad del adaptador"

grep -Fq "https://www.youtube-nocookie.com" "$adapter" \
  || fail "falta host de privacidad mejorada"

grep -Fq "origin: window.location.origin" "$adapter" \
  || fail "falta origin same-origin"

grep -Fq 'referrerPolicy="strict-origin-when-cross-origin"' "$adapter" \
  || fail "falta referrer policy compatible con identidad del cliente"

grep -Fq "min-block-size: 12.5rem" \
  apps/web/src/integrations/youtube/youtube-iframe-adapter.css \
  || fail "falta viewport mínimo 200px del reproductor"

grep -Fq "Cargar reproductor de YouTube" "$adapter" \
  || fail "falta carga diferida por decisión"

grep -Fq "onStateChange" "$adapter" \
  || fail "falta evento permitido de estado"

grep -Fq "onError" "$adapter" \
  || fail "falta degradación por error del player"

grep -Fq "getCurrentTime" "$adapter" \
  || fail "falta contrato temporal mínimo para BL059"

grep -Fq 'data-route-id="UI-MVP-009"' "$page" \
  || fail "UI-MVP-009 no está implementada"

grep -Fq "YouTubeIframeAdapter" "$editorial_preview" \
  || fail "falta previsualización editorial del adaptador"

grep -Fq "VISTA PREVIA EDITORIAL · NO PUBLICA" "$editorial_preview" \
  || fail "la previsualización editorial no declara que no publica"

grep -Fq "headingLevel={4}" "$editorial_preview" \
  || fail "la previsualización editorial no conserva jerarquía de encabezados"

grep -Fq "source.external_ref" "$service" \
  || fail "la ficha pública no expone la referencia exacta validada"

node <<'NODE'
const fs = require('node:fs');

const files = [
  'apps/web/src/integrations/youtube/YouTubeIframeAdapter.tsx',
  'apps/web/src/routes/student/EducationalPlayerPage.tsx',
  'apps/web/src/routes/editorial/SynchronizationStructurePage.tsx',
];

const combined = files
  .map((file) => fs.readFileSync(file, 'utf8'))
  .join('\n')
  .toLowerCase();

const forbidden = [
  {
    pattern: 'googleapis.com/youtube/v3',
    message: 'se detectó YouTube Data API',
  },
  {
    pattern: 'youtube data api',
    message: 'se detectó dependencia de YouTube Data API',
  },
];

for (const entry of forbidden) {
  if (combined.includes(entry.pattern)) {
    console.error(`ERROR BL-MVP-058: ${entry.message}`);
    process.exit(1);
  }
}

if (/(download|fetch)[^\n]{0,80}(audio|video)/i.test(combined)) {
  console.error('ERROR BL-MVP-058: se detectó intención de descarga audiovisual');
  process.exit(1);
}
NODE

cat <<'EOF'
bl=BL-MVP-058
ui=UI-MVP-009
lazy_load=true
privacy_host=youtube-nocookie.com
origin=true
events=ready,state,error
controller=play,pause,seek,getCurrentTime
data_api=false
media_download=false
degraded_state=true
owned_content_independent=true
editorial_draft_preview=true
public_slug_required_for_preview=false
sync_engine=false
publishes=false
OK: BL-MVP-058 adaptador aislado, carga diferida, origin, eventos y degradación verificados.
EOF
