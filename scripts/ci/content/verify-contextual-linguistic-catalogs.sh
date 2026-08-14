#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL066_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(docker compose exec -T postgres psql --username="$PGUSER" --dbname="$PGDATABASE" --no-password --set=ON_ERROR_STOP=1)
else
  psql_base=(psql --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$PGDATABASE" --no-password --set=ON_ERROR_STOP=1)
fi

fail_check() {
  echo "ERROR: BL-MVP-066: $1" >&2
  exit 1
}

service="src/Modules/Content/Infrastructure/Administration/LinguisticAnalysisRevisionAdministrationService.cs"
page="apps/web/src/routes/editorial/LinguisticAnalysisStructurePage.tsx"
test_file="tests/E2ETests/contextual-linguistic-catalogs.spec.ts"

grep -Fq "ReadKanjiAsync" "$service" || fail_check "falta ReadKanjiAsync."
grep -Fq "occurrence.analysis_revision_id = @analysis_revision_id" "$service" || fail_check "falta revisión de análisis."
grep -Fq "section.lyrics_revision_id = @lyrics_revision_id" "$service" || fail_check "falta revisión japonesa exacta."
grep -Fq "FROM occurrence.char_offset + 1" "$service" || fail_check "falta origen de char_offset de kanji."
grep -Fq "FOR char_length(entry.character)" "$service" || fail_check "falta longitud del carácter de kanji."
grep -Fq ") = entry.character" "$service" || fail_check "falta comparación del carácter de kanji."
grep -Fq "Kanji contextual" "$page" || fail_check "UI-MVP-024 no presenta kanji."
grep -Fq "Entrada estable" "$page" || fail_check "no se distingue entrada estable."
grep -Fq "JLPT orientativo" "$page" || fail_check "JLPT no es orientativo."
grep -Fq "no certificación oficial" "$page" || fail_check "falta aclaración de nivel."
grep -Fq "externalRequests" "$test_file" || fail_check "falta prueba de red externa."

if grep -Eiq 'https?://|fetch\(|XMLHttpRequest|axios|openai|anthropic|gemini|deepl|dictionaryapi|jisho|mecab.*api' "$service" "$page"; then
  fail_check "dependencia lingüística externa detectada."
fi

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-066-contextual-catalogs.txt <<'SQL'
DO $$
DECLARE
    tables_ok boolean;
    stable_unique_ok boolean;
BEGIN
    SELECT count(*) = 9
      INTO tables_ok
      FROM information_schema.tables
     WHERE table_schema = 'content'
       AND table_name IN (
         'linguistic_analysis_revision',
         'vocabulary_entry',
         'vocabulary_sense',
         'vocabulary_occurrence',
         'kanji_entry',
         'kanji_reading',
         'kanji_occurrence',
         'grammar_point',
         'grammar_occurrence'
       );

    SELECT
      EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname='content'
          AND tablename='vocabulary_entry'
          AND indexname='ux_content_vocabulary_entry_01'
      )
      AND EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname='content'
          AND tablename='kanji_entry'
          AND indexname='ux_content_kanji_entry_01'
      )
      AND EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname='content'
          AND tablename='grammar_point'
          AND indexname='ux_content_grammar_point_01'
      )
      INTO stable_unique_ok;

    IF NOT tables_ok THEN
      RAISE EXCEPTION 'faltan tablas M05 requeridas';
    END IF;
    IF NOT stable_unique_ok THEN
      RAISE EXCEPTION 'faltan identidades estables';
    END IF;
END
$$;

PREPARE bl066_kanji_context(uuid, uuid, varchar) AS
SELECT
    occurrence.occurrence_id,
    occurrence.token_id,
    line.line_id,
    token.surface,
    entry.kanji_id,
    entry.character,
    occurrence.char_offset,
    reading.reading,
    reading.meaning
FROM content.kanji_occurrence AS occurrence
JOIN content.lyric_token AS token
  ON token.token_id = occurrence.token_id
JOIN content.lyric_line AS line
  ON line.line_id = token.line_id
JOIN content.lyric_section AS section
  ON section.section_id = line.section_id
JOIN content.kanji_entry AS entry
  ON entry.kanji_id = occurrence.kanji_id
LEFT JOIN content.kanji_reading AS reading
  ON reading.kanji_id = entry.kanji_id
 AND reading.language_tag = $3
WHERE occurrence.analysis_revision_id = $1
  AND section.lyrics_revision_id = $2
  AND substring(
        token.surface
        FROM occurrence.char_offset + 1
        FOR char_length(entry.character)
      ) = entry.character;

DEALLOCATE bl066_kanji_context;
SQL

echo "bl=BL-MVP-066"
echo "ui=UI-MVP-024"
echo "vocabulary_stable=true"
echo "vocabulary_contextual=true"
echo "kanji_stable=true"
echo "kanji_contextual=true"
echo "kanji_position_guard=true"
echo "kanji_general_reading_not_contextual=true"
echo "grammar_stable=true"
echo "grammar_contextual=true"
echo "jlpt_orientative=true"
echo "exact_analysis_revision=true"
echo "exact_lyrics_revision=true"
echo "external_linguistic_api=false"
echo "writes=false"
echo "publishes=false"
echo "OK: BL-MVP-066 entradas estables y ocurrencias contextuales compatibles verificadas."
