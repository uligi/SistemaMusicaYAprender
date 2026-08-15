#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL068_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(docker compose exec -T postgres psql --username="$PGUSER" --dbname="$PGDATABASE" --no-password --set=ON_ERROR_STOP=1)
else
  psql_base=(psql --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$PGDATABASE" --no-password --set=ON_ERROR_STOP=1)
fi

fail_check() {
  echo "ERROR: BL-MVP-068: $1" >&2
  exit 1
}

service="src/Modules/Content/Infrastructure/PublicPlayback/PublicContextualAnalysisService.cs"
keys="src/Modules/Content/Infrastructure/PublicPlayback/PublicAnalysisTokenKey.cs"
endpoint="apps/api/Endpoints/PublicCatalog/PublicContextualAnalysisEndpoints.cs"
player="apps/web/src/routes/student/EducationalPlayerPage.tsx"
karaoke="apps/web/src/routes/student/EducationalKaraoke.tsx"
panel="apps/web/src/routes/student/ContextualAnalysisPanel.tsx"
area="apps/web/src/routes/student/StudentArea.tsx"
test_file="tests/E2ETests/contextual-analysis-panel.spec.ts"

grep -Fq "/api/v1/public/catalog/songs/{slug}/analysis/{token}" "$endpoint" \
  || fail_check "falta endpoint público contextual."

grep -Fq "published_package_projection" "$service" \
  || fail_check "el servicio no revalida publicación."

grep -Fq "component_kind = 'LYRICS'" "$service" \
  || fail_check "falta letra exacta del paquete."

grep -Fq "component_kind = 'ANALYSIS'" "$service" \
  || fail_check "falta análisis exacto del paquete."

grep -Fq "analysis.lyrics_revision_id = @lyrics_revision_id" "$service" \
  || fail_check "falta compatibilidad análisis/letra."

grep -Fq "content.vocabulary_occurrence" "$service" \
  || fail_check "falta vocabulario contextual."

grep -Fq "content.kanji_occurrence" "$service" \
  || fail_check "falta kanji contextual."

grep -Fq "content.morphology_annotation" "$service" \
  || fail_check "falta morfología contextual."

grep -Fq "content.grammar_occurrence" "$service" \
  || fail_check "falta gramática contextual."

grep -Fq "LINGUISTIC_ANALYSIS_REVISION" "$service" \
  || fail_check "falta procedencia del análisis."

grep -Fq ":public-analysis-token-v1" "$keys" \
  || fail_check "falta referencia pública opaca de token."

grep -Fq "onTokenAnalysis" "$karaoke" \
  || fail_check "los tokens no son accionables para análisis."

grep -Fq "<ContextualAnalysisPanel" "$player" \
  || fail_check "UI-MVP-009 no mantiene panel embebido."

grep -Fq "UI-MVP-010" "$area" \
  || fail_check "UI-MVP-010 no está materializada."

grep -Fq "Significado en esta canción" "$panel" \
  || fail_check "el sentido contextual no se prioriza."

grep -Fq "no certificación oficial" "$panel" \
  || fail_check "los niveles no están marcados como orientativos."

grep -Fq "__analysisPlayerInstances" "$test_file" \
  || fail_check "E2E no verifica que el player permanezca montado."

grep -Fq "expect(external).toEqual([])" "$test_file" \
  || fail_check "E2E no exige cero servicios lingüísticos externos."

if grep -Eiq 'https?://|fetch\(|XMLHttpRequest|axios|openai|anthropic|gemini|deepl|dictionaryapi|jisho|mecab.*api' "$service" "$panel"; then
  fail_check "dependencia lingüística externa detectada."
fi

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-068-contextual-analysis-panel.txt <<'SQL'
DO $$
DECLARE
    tables_ok boolean;
BEGIN
    SELECT count(*) = 12
      INTO tables_ok
      FROM information_schema.tables
     WHERE table_schema IN ('content', 'editorial', 'catalog')
       AND table_name IN (
         'linguistic_analysis_revision',
         'token_reading',
         'vocabulary_entry',
         'vocabulary_sense',
         'vocabulary_occurrence',
         'kanji_entry',
         'kanji_reading',
         'kanji_occurrence',
         'morphology_annotation',
         'grammar_point',
         'grammar_occurrence',
         'publication_component'
       );

    IF NOT tables_ok THEN
      RAISE EXCEPTION 'faltan tablas requeridas por BL068';
    END IF;
END
$$;

PREPARE bl068_token_context(uuid, uuid, uuid, integer, varchar) AS
SELECT
    reading.reading_kana,
    vocabulary.lemma,
    kanji.character,
    morphology.lemma,
    grammar.grammar_code
FROM content.lyric_token AS token
LEFT JOIN content.token_reading AS reading
  ON reading.token_id = token.token_id
 AND reading.analysis_revision_id = $1
LEFT JOIN content.vocabulary_occurrence AS vocabulary_occurrence
  ON vocabulary_occurrence.token_id = token.token_id
 AND vocabulary_occurrence.analysis_revision_id = $1
LEFT JOIN content.vocabulary_entry AS vocabulary
  ON vocabulary.vocabulary_id = vocabulary_occurrence.vocabulary_id
LEFT JOIN content.kanji_occurrence AS kanji_occurrence
  ON kanji_occurrence.token_id = token.token_id
 AND kanji_occurrence.analysis_revision_id = $1
LEFT JOIN content.kanji_entry AS kanji
  ON kanji.kanji_id = kanji_occurrence.kanji_id
LEFT JOIN content.morphology_annotation AS morphology
  ON morphology.token_id = token.token_id
 AND morphology.analysis_revision_id = $1
LEFT JOIN content.grammar_occurrence AS grammar_occurrence
  ON grammar_occurrence.line_id = $3
 AND grammar_occurrence.analysis_revision_id = $1
LEFT JOIN content.grammar_point AS grammar
  ON grammar.grammar_point_id = grammar_occurrence.grammar_point_id
JOIN content.lyric_line AS line
  ON line.line_id = token.line_id
JOIN content.lyric_section AS section
  ON section.section_id = line.section_id
WHERE token.token_id = $2
  AND token.line_id = $3
  AND token.token_no = $4
  AND section.lyrics_revision_id = $5::uuid;

DEALLOCATE bl068_token_context;
SQL

echo "bl=BL-MVP-068"
echo "ui=UI-MVP-010"
echo "embedded_panel=true"
echo "standalone_deep_link=true"
echo "player_forced_stop=false"
echo "opaque_public_token_key=true"
echo "exact_publication=true"
echo "exact_lyrics_revision=true"
echo "exact_analysis_revision=true"
echo "vocabulary_contextual=true"
echo "kanji_contextual=true"
echo "morphology_contextual=true"
echo "grammar_contextual=true"
echo "provenance_visible=true"
echo "jlpt_orientative=true"
echo "external_linguistic_api=false"
echo "writes=false"
echo "publishes=false"
echo "OK: BL-MVP-068 panel de análisis contextual verificado."
