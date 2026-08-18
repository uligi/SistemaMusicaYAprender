#!/usr/bin/env bash
set -euo pipefail

grep -q "SongCrudGuide" apps/web/src/routes/editorial/EditorialArea.tsx
grep -q "Gestión CRUD editorial segura" apps/web/src/routes/editorial/SongCrudGuide.tsx

for route in UI-MVP-019 UI-MVP-020 UI-MVP-021 UI-MVP-022 UI-MVP-023 UI-MVP-024 UI-MVP-025 UI-MVP-026; do
  grep -q "'$route'" apps/web/src/routes/editorial/SongCrudGuide.tsx
done

grep -q "backoffice-layout .route-surface" apps/web/src/app/shell/shell.css
grep -q "max-width: none" apps/web/src/app/shell/shell.css
grep -q "repeat(auto-fit, minmax(9.5rem, 1fr))" apps/web/src/routes/editorial/song-context-navigation.css

grep -q "FillBlankExerciseEditSeed" apps/web/src/routes/editorial/FillBlankExerciseAuthoringWizard.tsx
grep -q "Editar borrador" apps/web/src/routes/editorial/ExerciseBankPage.tsx
grep -q "Corregir como nueva revisión" apps/web/src/routes/editorial/ExerciseBankPage.tsx
grep -q "initialDraft" apps/web/src/routes/editorial/FillBlankExerciseAuthoringWizard.tsx

grep -q "EDITORIAL_AUTHORING" database/postgresql/security/02_database_access.sql
grep -q "object_type = 'EXERCISE_REVISION'" database/postgresql/security/02_database_access.sql
grep -q "'EXERCISE_AUTHOR'" database/postgresql/security/02_database_access.sql

if grep -REqi --include='*.cs' --include='*.sql' 'DELETE[[:space:]]+FROM[[:space:]]+(content\.(lyrics_revision|timing_revision|translation_revision|linguistic_analysis_revision)|learning\.(exercise_definition|exercise_revision)|editorial\.editorial_package)' \
  database/postgresql/security/02_database_access.sql \
  apps/api src/Modules; then
  echo "ERROR: se detectó hard delete de una entidad versionada/canónica."
  exit 1
fi

echo "safe_crud_tabs=true"
echo "exercise_edit=true"
echo "exercise_provenance=true"
echo "desktop_workspace=true"
echo "no_hard_delete_versioned=true"
echo "FIX-MVP-EDITORIAL-CRUD-DESKTOP-001 static verifier: GREEN"
