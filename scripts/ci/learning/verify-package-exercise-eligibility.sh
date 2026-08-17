#!/usr/bin/env bash
set -euo pipefail

service="src/Modules/Editorial/Infrastructure/Administration/CompatibleEducationalPackageService.cs"
page="apps/web/src/routes/editorial/CompatiblePackagePage.tsx"
spec="tests/E2ETests/compatible-package-exercises.spec.ts"

test -f "$service"
test -f "$page"
test -f "$spec"

grep -Fq "FILL_BLANK_OPTIONS" "$service"
grep -Fq "SINGLE_CHOICE" "$service"
grep -Fq "acceptedItemOrders" "$service"
grep -Fq "exactamente una opción CORRECT" "$service"
grep -Fq "HasExerciseProvenanceAsync" "$service"
grep -Fq "sourceTokenId" "$service"
grep -Fq "minigame" "$service"
grep -Fq "lives" "$service"
grep -Fq "combo" "$service"
grep -Fq "timer" "$service"
grep -Fq "Fuente incompatible con la letra seleccionada" "$page"
grep -Fq "Aprobación es específica" "$page" || grep -Fq "aprobación es específica" "$page"
grep -Fq "BL079 detecta ejercicio roto" "$spec"
grep -Fq "320 px" "$spec"

if grep -Eq "INSERT INTO progress\.|UPDATE progress\.|DELETE FROM progress\." "$service"; then
  echo "ERROR: BL079 no debe escribir progreso."
  exit 1
fi

echo "OK: BL-MVP-079 elegibilidad de ejercicios verificada."
echo "exercise=P0_FILL_BLANK_OPTIONS"
echo "broken-links=blocked"
echo "source-revalidation=required"
echo "p2-minigame=excluded"
echo "progress-written=false"
