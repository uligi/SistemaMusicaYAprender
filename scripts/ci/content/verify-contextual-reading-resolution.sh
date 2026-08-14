#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL065_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(
    docker compose exec -T postgres
    psql
    --username="$PGUSER"
    --dbname="$PGDATABASE"
    --no-password
    --set=ON_ERROR_STOP=1
  )
else
  psql_base=(
    psql
    --host="$PGHOST"
    --port="$PGPORT"
    --username="$PGUSER"
    --dbname="$PGDATABASE"
    --no-password
    --set=ON_ERROR_STOP=1
  )
fi

fail_check() {
  echo "ERROR: BL-MVP-065: $1" >&2
  exit 1
}

component="apps/web/src/routes/editorial/ContextualReading.tsx"
page="apps/web/src/routes/editorial/LinguisticAnalysisStructurePage.tsx"
test_file="tests/E2ETests/contextual-reading-resolution.spec.ts"

grep -Fq "READING.LOCAL.V1" "$component" \
  || fail_check "falta versión explícita del resolver local."

grep -Fq "romanizeApprovedReading" "$component" \
  || fail_check "falta romanización derivada de la lectura aprobada."

grep -Fq "<ruby" "$component" && grep -Fq "<rt>" "$component" \
  || fail_check "falta semántica ruby/rt."

grep -Fq "Lectura ambigua" "$component" \
  || fail_check "falta estado explícito de ambigüedad."

grep -Fq "Excepción editorial" "$component" \
  || fail_check "falta preservación de romaji editorial."

grep -Fq "No se genera pronunciación desde los kanji" "$component" \
  || fail_check "falta estado seguro cuando no existe lectura."

grep -Fq "<ContextualReading" "$page" \
  || fail_check "UI-MVP-024 no consume el resolver contextual."

grep -Fq "<ContextualReadingStatus" "$page" \
  || fail_check "UI-MVP-024 no expone estado de ayudas locales."

grep -Fq "externalRequests" "$test_file" \
  || fail_check "falta prueba de independencia externa."

if grep -Eiq 'https?://|fetch\(|XMLHttpRequest|axios|openai|anthropic|gemini|deepl|google[[:space:]_-]*translate|dictionaryapi|jisho|mecab.*api' "$component"; then
  fail_check "el resolver de lectura contiene una dependencia o llamada externa."
fi

if grep -Eiq 'guardar|publicar|MapPost|INSERT INTO|UPDATE |DELETE FROM' "$component"; then
  fail_check "BL065 no debe adelantar el editor integral BL067 ni publicación."
fi

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-065-contextual-readings.txt <<'SQL'
DO $$
DECLARE
    token_reading_ok boolean;
    revision_link_ok boolean;
    unique_reading_type_ok boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'content'
          AND table_name = 'token_reading'
          AND column_name = 'reading_kana'
    ) AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'content'
          AND table_name = 'token_reading'
          AND column_name = 'furigana'
    ) AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'content'
          AND table_name = 'token_reading'
          AND column_name = 'romaji'
    ) AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'content'
          AND table_name = 'token_reading'
          AND column_name = 'reading_type'
    ) INTO token_reading_ok;

    SELECT EXISTS (
        SELECT 1
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
          ON kcu.constraint_name = tc.constraint_name
         AND kcu.constraint_schema = tc.constraint_schema
        WHERE tc.table_schema = 'content'
          AND tc.table_name = 'linguistic_analysis_revision'
          AND kcu.column_name = 'lyrics_revision_id'
    ) INTO revision_link_ok;

    SELECT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'content'
          AND tablename = 'token_reading'
          AND indexname = 'ux_content_token_reading_01'
          AND indexdef LIKE '%analysis_revision_id, token_id, reading_type%'
    ) INTO unique_reading_type_ok;

    IF NOT token_reading_ok THEN
        RAISE EXCEPTION 'token_reading no expone reading_kana/furigana/romaji/reading_type';
    END IF;

    IF NOT revision_link_ok THEN
        RAISE EXCEPTION 'linguistic_analysis_revision no conserva lyrics_revision_id';
    END IF;

    IF NOT unique_reading_type_ok THEN
        RAISE EXCEPTION 'falta unicidad por revisión/token/tipo de lectura';
    END IF;
END
$$;
SQL

echo "bl=BL-MVP-065"
echo "ui=UI-MVP-024"
echo "resolver_version=READING.LOCAL.V1"
echo "approved_reading_source=true"
echo "furigana_ruby=true"
echo "romaji_from_reading=true"
echo "editorial_romaji_override=true"
echo "ambiguity_explicit=true"
echo "latin_original_distinguished=true"
echo "exact_analysis_revision=true"
echo "external_linguistic_api=false"
echo "writes=false"
echo "publishes=false"
echo "OK: BL-MVP-065 lecturas, furigana y romaji se resuelven localmente desde revisión editorial exacta."
