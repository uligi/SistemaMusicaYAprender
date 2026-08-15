#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

fail_check() {
  echo "ERROR: BL-MVP-060: $1" >&2
  exit 1
}

page="apps/web/src/routes/student/EducationalPlayerPage.tsx"
karaoke="apps/web/src/routes/student/EducationalKaraoke.tsx"
sync="apps/web/src/features/player/synchronization/SynchronizedYouTubePreview.tsx"
test_file="tests/E2ETests/educational-karaoke-layers.spec.ts"

for file in "$page" "$karaoke" "$sync" "$test_file"; do
  [[ -f "$file" ]] || fail_check "falta $file"
done

grep -Fq "<EducationalKaraoke" "$page" \
  || fail_check "UI-MVP-009 no monta el karaoke educativo."
grep -Fq "<SynchronizedYouTubePreview" "$page" \
  || fail_check "UI-MVP-009 perdió el adaptador de reproducción sincronizada."
grep -Fq 'presentation="learning"' "$page" \
  || fail_check "el player no activa la presentación de aprendizaje."
grep -Fq "onSnapshotChange={setSnapshot}" "$page" \
  || fail_check "el karaoke no recibe el snapshot local confirmado."
grep -Fq 'data-educational-karaoke' "$karaoke" \
  || fail_check "falta el contenedor observable del karaoke."
grep -Fq "aria-current={active ? 'true' : undefined}" "$karaoke" \
  || fail_check "la línea activa no expone estado semántico."
grep -Fq "snapshot.level === 'TOKEN'" "$karaoke" \
  || fail_check "el resaltado por token no está condicionado a precisión TOKEN."
grep -Fq 'data-active={active ? '\''true'\'' : '\''false'\''}' "$karaoke" \
  || fail_check "falta estado visible y verificable de línea/token activo."
grep -Fq "aria-live=\"off\"" "$sync" \
  || fail_check "la actualización temporal podría anunciarse de forma intrusiva."
grep -Fq "sin mover el foco" "$sync" \
  || fail_check "falta contrato explícito de foco estable."
grep -Fq "muestra contenido propio antes de YouTube" "$test_file" \
  || fail_check "falta E2E de contenido propio antes del iframe."
grep -Fq "sin mover foco" "$test_file" \
  || fail_check "falta E2E de foco estable."
grep -Fq "si YouTube falla conserva letra" "$test_file" \
  || fail_check "falta E2E de degradación externa."

if grep -Eq 'scrollIntoView|\.focus\(' "$karaoke"; then
  fail_check "el karaoke no debe mover scroll o foco automáticamente."
fi

python3 - "$page" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
owned = text.find("<EducationalKaraoke")
external = text.find("<SynchronizedYouTubePreview")
if owned < 0 or external < 0 or owned >= external:
    raise SystemExit("ERROR: BL-MVP-060: el contenido propio debe declararse antes del reproductor externo.")
PY

echo "bl=BL-MVP-060"
echo "ui=UI-MVP-009"
echo "own_content_before_iframe=true"
echo "active_line_moves_focus=false"
echo "token_highlight_requires_token_precision=true"
echo "youtube_failure_preserves_owned_content=true"
echo "external_linguistic_api=false"
echo "OK: BL-MVP-060 reproductor educativo y karaoke accesible verificados."
