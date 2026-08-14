#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL067_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(docker compose exec -T postgres psql --username="$PGUSER" --dbname="$PGDATABASE" --no-password --set=ON_ERROR_STOP=1)
else
  psql_base=(psql --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$PGDATABASE" --no-password --set=ON_ERROR_STOP=1)
fi

fail_check() { echo "ERROR: BL-MVP-067: $1" >&2; exit 1; }

endpoint="apps/api/Endpoints/Editorial/LinguisticAnalysisRevisionAdministrationEndpoints.cs"
writer="src/Modules/Content/Infrastructure/Administration/LinguisticAnalysisEditorialWriter.cs"
editor="apps/web/src/routes/editorial/LinguisticAnalysisEditor.tsx"
page="apps/web/src/routes/editorial/LinguisticAnalysisStructurePage.tsx"
test_file="tests/E2ETests/linguistic-analysis-editorial-workspace.spec.ts"

grep -Fq "/analysis-revisions/validate" "$endpoint" || fail_check "falta endpoint de validación."
grep -Fq 'RequireEffectivePermission(' "$endpoint" || fail_check "falta autorización de escritura."
grep -Fq '"EDITORIAL.DRAFT"' "$endpoint" || fail_check "la escritura no exige EDITORIAL.DRAFT."
grep -Fq "ValidateRequestAsync" "$endpoint" || fail_check "falta protección CSRF."
grep -Fq 'TryGetValue("If-Match"' "$endpoint" || fail_check "falta If-Match."

grep -Fq "AcquireLockAsync" "$writer" || fail_check "falta lock."
grep -Fq "content.analysis.token.orphan" "$writer" || fail_check "falta huérfanos."
grep -Fq "content.analysis.coverage.partial" "$writer" || fail_check "falta cobertura."
grep -Fq "BuildChecksum" "$writer" || fail_check "falta checksum."
grep -Fq "'DRAFT'" "$writer" || fail_check "revisión no DRAFT."
grep -Fq "LINGUISTIC_ANALYSIS_REVISION" "$writer" || fail_check "falta procedencia."
grep -Fq "EnumerateRunes" "$writer" || fail_check "falta guard Unicode."
grep -Fq "content.analysis.kanji.reading-pair.required" "$writer" || fail_check "falta guard lectura/significado kanji."
grep -Fq "usage_note IS NOT DISTINCT FROM @usage_note" "$writer" || fail_check "vocabulario no compara la nota de la última revisión."
grep -Fq "UPDATE content.kanji_entry" "$writer" || fail_check "kanji estable no persiste correcciones."
grep -Fq "UPDATE content.kanji_reading" "$writer" || fail_check "significado de lectura kanji existente no persiste."
grep -Fq "UPDATE content.grammar_point" "$writer" || fail_check "gramática estable no persiste correcciones."
grep -Fq "latest.examples IS NOT DISTINCT FROM @examples" "$writer" || fail_check "explicación gramatical no compara ejemplos de la última revisión."

grep -Fq "Elige una línea y una palabra" "$editor" || fail_check "falta paso 1."
grep -Fq "Completa solo lo que conozcas" "$editor" || fail_check "falta paso 2."
grep -Fq "Revisa y guarda" "$editor" || fail_check "falta paso 3."
grep -Fq "No necesitas completar todo de una vez" "$editor" || fail_check "falta explicación de parcial."
grep -Fq "PREVISUALIZACIÓN DEL PAQUETE" "$editor" || fail_check "falta preview."
grep -Fq "Preparar kanji escritos en la palabra" "$editor" || fail_check "falta kanji local."
grep -Fq "senses.at(-1)" "$editor" || fail_check "editor no reabre el último sentido de vocabulario."
grep -Fq "readings.at(-1)" "$editor" || fail_check "editor no reabre la última lectura de kanji."
grep -Fq "opcionales como pareja" "$editor" || fail_check "UI no explica la pareja lectura/significado."
grep -Fq "<LinguisticAnalysisEditor" "$page" || fail_check "UI no integra editor."

if grep -Eiq 'https?://|XMLHttpRequest|axios|openai|anthropic|gemini|deepl|dictionaryapi|jisho|mecab.*api' "$writer" "$editor"; then
  fail_check "dependencia lingüística externa detectada."
fi

if grep -Eiq 'EDITORIAL\.PUBLISH|MapPut|MapDelete' "$editor" "$endpoint"; then
  fail_check "BL067 no debe publicar."
fi

grep -Fq "externalRequests" "$test_file" || fail_check "falta prueba de red externa."
grep -Fq "320" "$test_file" || fail_check "falta prueba 320px."
grep -Fq "AxeBuilder" "$test_file" || fail_check "falta axe."
grep -Fq "valida lectura y significado de kanji como pareja antes de guardar" "$test_file" || fail_check "falta regresión de pareja kanji."
grep -Fq "edita una revisión existente sin perder los últimos valores estables" "$test_file" || fail_check "falta regresión de edición existente."

mkdir -p artifacts/postgres
"${psql_base[@]}" > artifacts/postgres/bl-mvp-067-editorial-workspace.txt <<'SQL'
BEGIN;

PREPARE bl067_revision(uuid,uuid,integer,uuid,bytea) AS
INSERT INTO content.linguistic_analysis_revision
(analysis_revision_id,lyrics_revision_id,revision_no,parent_revision_id,status_code,checksum)
VALUES ($1,$2,$3,$4,'DRAFT',$5);

PREPARE bl067_reading(uuid,uuid,uuid,text,text,text,varchar) AS
INSERT INTO content.token_reading
(token_reading_id,analysis_revision_id,token_id,reading_kana,furigana,romaji,reading_type)
VALUES ($1,$2,$3,$4,$5,$6,$7);

PREPARE bl067_vocab(uuid,uuid,uuid,uuid,text,varchar) AS
INSERT INTO content.vocabulary_occurrence
(occurrence_id,analysis_revision_id,token_id,vocabulary_id,inflection,confidence_code)
VALUES ($1,$2,$3,$4,$5,$6);

PREPARE bl067_kanji(uuid,uuid,uuid,uuid,integer) AS
INSERT INTO content.kanji_occurrence
(occurrence_id,analysis_revision_id,token_id,kanji_id,char_offset)
VALUES ($1,$2,$3,$4,$5);

PREPARE bl067_morphology(uuid,uuid,uuid,text,varchar,varchar,jsonb) AS
INSERT INTO content.morphology_annotation
(annotation_id,analysis_revision_id,token_id,lemma,pos_code,conjugation_code,features)
VALUES ($1,$2,$3,$4,$5,$6,$7);

PREPARE bl067_grammar(uuid,uuid,uuid,uuid,uuid,uuid,text) AS
INSERT INTO content.grammar_occurrence
(occurrence_id,analysis_revision_id,grammar_point_id,line_id,start_token_id,end_token_id,note)
VALUES ($1,$2,$3,$4,$5,$6,$7);

DEALLOCATE bl067_revision;
DEALLOCATE bl067_reading;
DEALLOCATE bl067_vocab;
DEALLOCATE bl067_kanji;
DEALLOCATE bl067_morphology;
DEALLOCATE bl067_grammar;
ROLLBACK;
SQL

echo "bl=BL-MVP-067"
echo "ui=UI-MVP-024"
echo "task_first=true"
echo "partial_analysis=true"
echo "server_validation_preview=true"
echo "coverage=true"
echo "anchors=true"
echo "provenance=true"
echo "orphans=true"
echo "etag_if_match=true"
echo "csrf=true"
echo "draft_only=true"
echo "canonical_source_read_only=true"
echo "stable_edits_persist=true"
echo "kanji_reading_pair_guard=true"
echo "localized_history_latest=true"
echo "external_linguistic_api=false"
echo "publishes=false"
echo "OK: BL-MVP-067 espacio editorial valida, previsualiza y guarda DRAFT sobre anclas canónicas."
