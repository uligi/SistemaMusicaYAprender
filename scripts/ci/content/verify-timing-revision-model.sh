#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL056_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-056: $1" >&2
  exit 1
}

for marker in \
  'ValidateInterval(' \
  'ValidateOverlaps(' \
  'content.timing.segment.overlap-unjustified' \
  'content.timing.source-duration.required' \
  'content.timing.token.order-invalid' \
  'AcquireTimingLockAsync(' \
  'SHA256.HashData'; do
  grep -Fq "$marker" \
    src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs \
    || fail_check "falta regla de servicio: $marker"
done

grep -Fq 'tokens.Count > 1' \
  src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs \
  || fail_check "no se reconstruye precisión por token desde segmentos ordenados."

grep -Fq '/synchronization-context' \
  apps/api/Endpoints/Editorial/TimingRevisionAdministrationEndpoints.cs \
  || fail_check "falta contexto de sincronización por grabación."

grep -Fq 'data-route-id="UI-MVP-022"' \
  apps/web/src/routes/editorial/SynchronizationStructurePage.tsx \
  || fail_check "UI-MVP-022 no está materializada."

grep -Fq 'BL-MVP-057' \
  apps/web/src/routes/editorial/SynchronizationStructurePage.tsx \
  || fail_check "BL056 adelanta o no delimita el editor BL057."

grep -Fq "getByRole('button', { name: 'Publicar' })" \
  tests/E2ETests/timing-revision-model.spec.ts \
  || fail_check "falta regresión que impide publicación temprana."

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-056-timing-revision.txt <<'SQL'
BEGIN;

INSERT INTO catalog.musical_work (
    work_id,
    canonical_title,
    language_tag,
    release_date,
    status_code,
    version
)
VALUES (
    '05600000-0000-4000-8000-000000000001',
    'BL056 synthetic work',
    'ja',
    NULL,
    'DRAFT',
    1
);

INSERT INTO catalog.recording (
    recording_id,
    work_id,
    recording_title,
    duration_ms,
    release_date,
    status_code,
    version
)
VALUES (
    '05600000-0000-4000-8000-000000000002',
    '05600000-0000-4000-8000-000000000001',
    'BL056 synthetic recording',
    180000,
    NULL,
    'DRAFT',
    1
);

INSERT INTO catalog.recording_source (
    source_id,
    recording_id,
    provider_code,
    external_ref,
    duration_ms,
    offset_ms,
    status_code,
    version
)
VALUES
(
    '05600000-0000-4000-8000-000000000003',
    '05600000-0000-4000-8000-000000000002',
    'YOUTUBE',
    'BL056sourceA',
    180000,
    0,
    'DRAFT',
    1
),
(
    '05600000-0000-4000-8000-000000000004',
    '05600000-0000-4000-8000-000000000002',
    'YOUTUBE',
    'BL056sourceB',
    181000,
    250,
    'DRAFT',
    1
);

INSERT INTO content.lyrics_revision (
    lyrics_revision_id,
    recording_id,
    revision_no,
    parent_revision_id,
    status_code,
    created_by,
    checksum,
    version
)
VALUES (
    '05600000-0000-4000-8000-000000000010',
    '05600000-0000-4000-8000-000000000002',
    1,
    NULL,
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('56', 32), 'hex'),
    1
);

INSERT INTO content.lyric_section (
    section_id,
    lyrics_revision_id,
    section_type,
    label,
    display_order
)
VALUES (
    '05600000-0000-4000-8000-000000000020',
    '05600000-0000-4000-8000-000000000010',
    'VERSE',
    'Verso 1',
    0
);

INSERT INTO content.lyric_line (
    line_id,
    section_id,
    line_no,
    japanese_text,
    normalized_text,
    speaker_label
)
VALUES
(
    '05600000-0000-4000-8000-000000000030',
    '05600000-0000-4000-8000-000000000020',
    1,
    convert_from(decode('e680aae78da3e381a7e38199', 'hex'), 'UTF8'),
    convert_from(decode('e680aae78da3e381a7e38199', 'hex'), 'UTF8'),
    'Voz principal'
),
(
    '05600000-0000-4000-8000-000000000031',
    '05600000-0000-4000-8000-000000000020',
    2,
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    NULL
);

INSERT INTO content.lyric_token (
    token_id,
    line_id,
    token_no,
    surface,
    normalized_surface,
    start_offset,
    end_offset
)
VALUES
(
    '05600000-0000-4000-8000-000000000040',
    '05600000-0000-4000-8000-000000000030',
    1,
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    0,
    2
),
(
    '05600000-0000-4000-8000-000000000041',
    '05600000-0000-4000-8000-000000000030',
    2,
    convert_from(decode('e381a7e38199', 'hex'), 'UTF8'),
    convert_from(decode('e381a7e38199', 'hex'), 'UTF8'),
    2,
    4
);

INSERT INTO content.timing_revision (
    timing_revision_id,
    lyrics_revision_id,
    source_id,
    revision_no,
    offset_ms,
    status_code,
    checksum
)
VALUES
(
    '05600000-0000-4000-8000-000000000050',
    '05600000-0000-4000-8000-000000000010',
    '05600000-0000-4000-8000-000000000003',
    1,
    0,
    'DRAFT',
    decode(repeat('50', 32), 'hex')
),
(
    '05600000-0000-4000-8000-000000000051',
    '05600000-0000-4000-8000-000000000010',
    '05600000-0000-4000-8000-000000000004',
    1,
    0,
    'DRAFT',
    decode(repeat('51', 32), 'hex')
);

-- Source A: token-level timing for line 1, line-level timing for line 2.
INSERT INTO content.timing_segment (
    segment_id,
    timing_revision_id,
    line_id,
    start_ms,
    end_ms,
    display_order
)
VALUES
(
    '05600000-0000-4000-8000-000000000060',
    '05600000-0000-4000-8000-000000000050',
    '05600000-0000-4000-8000-000000000030',
    1000,
    1700,
    0
),
(
    '05600000-0000-4000-8000-000000000061',
    '05600000-0000-4000-8000-000000000050',
    '05600000-0000-4000-8000-000000000030',
    1700,
    2200,
    1
),
(
    '05600000-0000-4000-8000-000000000062',
    '05600000-0000-4000-8000-000000000050',
    '05600000-0000-4000-8000-000000000031',
    2500,
    4200,
    2
);

-- Source B: same lyrics, independent source-specific revision.
INSERT INTO content.timing_segment (
    segment_id,
    timing_revision_id,
    line_id,
    start_ms,
    end_ms,
    display_order
)
VALUES
(
    '05600000-0000-4000-8000-000000000063',
    '05600000-0000-4000-8000-000000000051',
    '05600000-0000-4000-8000-000000000030',
    1200,
    2400,
    0
);

DO $$
DECLARE
    source_count integer;
    source_a_segments integer;
    line_1_segments integer;
    max_end bigint;
    source_a_duration bigint;
BEGIN
    SELECT count(DISTINCT source_id)
    INTO source_count
    FROM content.timing_revision
    WHERE lyrics_revision_id = '05600000-0000-4000-8000-000000000010';

    IF source_count <> 2 THEN
        RAISE EXCEPTION 'BL056 esperaba revisiones independientes para dos fuentes.';
    END IF;

    SELECT count(*)
    INTO source_a_segments
    FROM content.timing_segment
    WHERE timing_revision_id = '05600000-0000-4000-8000-000000000050';

    IF source_a_segments <> 3 THEN
        RAISE EXCEPTION 'BL056 esperaba tres segmentos en la fuente A.';
    END IF;

    SELECT count(*)
    INTO line_1_segments
    FROM content.timing_segment
    WHERE timing_revision_id = '05600000-0000-4000-8000-000000000050'
      AND line_id = '05600000-0000-4000-8000-000000000030';

    IF line_1_segments <> 2 THEN
        RAISE EXCEPTION 'BL056 no conservó granularidad detallada por token ordenado.';
    END IF;

    SELECT max(segment.end_ms)
    INTO max_end
    FROM content.timing_segment AS segment
    WHERE segment.timing_revision_id = '05600000-0000-4000-8000-000000000050';

    SELECT duration_ms
    INTO source_a_duration
    FROM catalog.recording_source
    WHERE source_id = '05600000-0000-4000-8000-000000000003';

    IF max_end > source_a_duration THEN
        RAISE EXCEPTION 'BL056 creó un segmento fuera de la duración de fuente.';
    END IF;
END
$$;

SELECT
    revision.source_id,
    revision.revision_no,
    segment.line_id,
    segment.start_ms,
    segment.end_ms,
    segment.display_order
FROM content.timing_revision AS revision
INNER JOIN content.timing_segment AS segment
    ON segment.timing_revision_id = revision.timing_revision_id
WHERE revision.lyrics_revision_id = '05600000-0000-4000-8000-000000000010'
ORDER BY
    revision.source_id,
    segment.display_order;

ROLLBACK;
SQL

echo "bl=BL-MVP-056"
echo "ui=UI-MVP-022"
echo "model=timing_revision,timing_segment"
echo "source_specific_revision=true"
echo "milliseconds=true"
echo "line_timing=true"
echo "token_timing=ordered_segments_per_line"
echo "duration_validation=true"
echo "overlap_requires_distinct_voice=true"
echo "publishes=false"
echo "OK: BL-MVP-056 revisiones por fuente, tiempos por línea/token, duración, orden y solapamientos justificados verificados."
