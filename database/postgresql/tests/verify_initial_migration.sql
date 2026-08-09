\set ON_ERROR_STOP on

CREATE TEMP TABLE expected_physical_table (
    schema_name text NOT NULL,
    table_name text NOT NULL,
    column_count integer NOT NULL,
    not_null_count integer NOT NULL,
    jsonb_count integer NOT NULL,
    pk_count integer NOT NULL,
    fk_count integer NOT NULL,
    check_count integer NOT NULL,
    exclusion_count integer NOT NULL,
    unique_index_count integer NOT NULL,
    nonunique_index_count integer NOT NULL,
    trigger_count integer NOT NULL,
    policy_count integer NOT NULL,
    rls_enabled boolean NOT NULL,
    rls_forced boolean NOT NULL,
    PRIMARY KEY (schema_name, table_name)
);

INSERT INTO expected_physical_table (
    schema_name,
    table_name,
    column_count,
    not_null_count,
    jsonb_count,
    pk_count,
    fk_count,
    check_count,
    exclusion_count,
    unique_index_count,
    nonunique_index_count,
    trigger_count,
    policy_count,
    rls_enabled,
    rls_forced
)
VALUES
    ('identity', 'consent_record', 6, 6, 0, 1, 1, 2, 0, 0, 1, 1, 3, true, true),
    ('identity', 'preference_revision', 6, 6, 1, 1, 1, 1, 0, 1, 1, 0, 3, true, true),
    ('identity', 'preference_set', 4, 4, 0, 1, 2, 1, 0, 1, 2, 1, 3, true, true),
    ('identity', 'privacy_request', 7, 5, 0, 1, 1, 2, 0, 0, 1, 0, 3, true, true),
    ('identity', 'user_profile', 6, 5, 0, 1, 1, 3, 0, 0, 0, 1, 3, true, true),
    ('security', 'access_scope', 5, 3, 1, 1, 0, 2, 0, 0, 0, 0, 0, false, false),
    ('security', 'account', 7, 6, 0, 1, 0, 4, 0, 1, 1, 1, 3, true, true),
    ('security', 'account_verification', 6, 5, 0, 1, 1, 3, 0, 1, 1, 0, 3, true, true),
    ('security', 'audit_event', 11, 7, 0, 1, 1, 5, 0, 0, 3, 1, 0, false, false),
    ('security', 'audit_seal', 7, 6, 0, 1, 1, 5, 1, 0, 1, 1, 0, false, false),
    ('security', 'credential', 7, 7, 0, 1, 1, 2, 0, 1, 1, 0, 3, true, true),
    ('security', 'mfa_method', 6, 5, 0, 1, 1, 2, 0, 0, 1, 0, 3, true, true),
    ('security', 'permission', 5, 5, 0, 1, 0, 4, 0, 1, 0, 0, 0, false, false),
    ('security', 'recovery_token', 6, 4, 0, 1, 1, 3, 0, 1, 1, 0, 3, true, true),
    ('security', 'role', 5, 5, 0, 1, 0, 4, 0, 1, 0, 1, 0, false, false),
    ('security', 'role_assignment', 7, 5, 0, 1, 3, 2, 1, 0, 4, 0, 3, true, true),
    ('security', 'role_permission', 5, 4, 0, 1, 3, 1, 1, 0, 3, 0, 0, false, false),
    ('security', 'security_event', 7, 5, 0, 1, 1, 2, 0, 0, 2, 1, 3, true, true),
    ('security', 'session', 8, 7, 0, 1, 1, 5, 0, 1, 2, 0, 3, true, true),
    ('catalog', 'artist', 6, 6, 0, 1, 0, 5, 0, 0, 0, 1, 0, false, false),
    ('catalog', 'artist_alias', 7, 7, 0, 1, 1, 4, 0, 1, 2, 0, 0, false, false),
    ('catalog', 'musical_work', 6, 5, 0, 1, 0, 4, 0, 0, 0, 1, 0, false, false),
    ('catalog', 'recording', 7, 4, 0, 1, 1, 4, 0, 0, 1, 1, 0, false, false),
    ('catalog', 'recording_credit', 6, 5, 0, 1, 2, 3, 0, 1, 2, 0, 0, false, false),
    ('catalog', 'recording_source', 8, 7, 0, 1, 1, 7, 0, 0, 1, 1, 0, false, false),
    ('catalog', 'recording_status_history', 7, 6, 0, 1, 2, 3, 0, 0, 2, 1, 0, false, false),
    ('catalog', 'song_search_document', 6, 5, 0, 1, 2, 2, 0, 0, 3, 0, 0, false, false),
    ('catalog', 'source_reference', 6, 3, 0, 1, 0, 3, 0, 0, 0, 0, 0, false, false),
    ('catalog', 'work_artist', 4, 4, 0, 1, 2, 2, 0, 0, 2, 0, 0, false, false),
    ('catalog', 'work_title', 7, 7, 0, 1, 1, 4, 0, 1, 2, 0, 0, false, false),
    ('content', 'grammar_explanation', 6, 5, 0, 1, 1, 3, 0, 1, 1, 0, 0, false, false),
    ('content', 'grammar_occurrence', 7, 4, 0, 1, 3, 1, 0, 0, 3, 0, 0, false, false),
    ('content', 'grammar_point', 6, 5, 0, 1, 0, 5, 0, 1, 0, 1, 0, false, false),
    ('content', 'kanji_entry', 6, 4, 0, 1, 0, 5, 0, 1, 0, 1, 0, false, false),
    ('content', 'kanji_occurrence', 5, 5, 0, 1, 3, 1, 0, 1, 3, 0, 0, false, false),
    ('content', 'kanji_reading', 7, 7, 0, 1, 1, 5, 0, 1, 1, 0, 0, false, false),
    ('content', 'linguistic_analysis_revision', 6, 5, 0, 1, 2, 3, 0, 1, 2, 1, 0, false, false),
    ('content', 'lyric_line', 6, 5, 0, 1, 1, 3, 0, 1, 2, 0, 0, false, false),
    ('content', 'lyric_section', 5, 4, 0, 1, 1, 2, 0, 1, 1, 0, 0, false, false),
    ('content', 'lyric_token', 7, 7, 0, 1, 1, 6, 0, 1, 1, 0, 0, false, false),
    ('content', 'lyrics_revision', 9, 8, 0, 1, 3, 4, 0, 1, 3, 2, 0, false, false),
    ('content', 'morphology_annotation', 7, 6, 1, 1, 2, 3, 0, 1, 2, 0, 0, false, false),
    ('content', 'timing_revision', 7, 7, 0, 1, 2, 3, 0, 1, 2, 1, 0, false, false),
    ('content', 'timing_segment', 6, 6, 0, 1, 2, 4, 0, 1, 3, 0, 0, false, false),
    ('content', 'token_alignment', 6, 4, 0, 1, 2, 4, 0, 0, 2, 0, 0, false, false),
    ('content', 'token_reading', 7, 5, 0, 1, 2, 2, 0, 1, 2, 0, 0, false, false),
    ('content', 'translation_line', 6, 6, 0, 1, 2, 3, 0, 1, 3, 0, 0, false, false),
    ('content', 'translation_note', 7, 4, 0, 1, 4, 2, 0, 0, 4, 0, 0, false, false),
    ('content', 'translation_revision', 8, 7, 0, 1, 2, 5, 0, 1, 2, 1, 0, false, false),
    ('content', 'vocabulary_entry', 7, 7, 0, 1, 0, 6, 0, 1, 0, 1, 0, false, false),
    ('content', 'vocabulary_occurrence', 6, 5, 0, 1, 3, 1, 0, 1, 4, 0, 0, false, false),
    ('content', 'vocabulary_sense', 6, 5, 0, 1, 1, 3, 0, 1, 1, 0, 0, false, false),
    ('learning', 'answer_submission', 7, 7, 0, 1, 1, 4, 0, 2, 2, 1, 3, true, true),
    ('learning', 'answer_value', 7, 4, 0, 1, 3, 2, 0, 1, 3, 1, 3, true, true),
    ('learning', 'competency', 6, 6, 0, 1, 0, 5, 0, 1, 0, 1, 0, false, false),
    ('learning', 'evaluation_result', 7, 7, 0, 1, 1, 3, 0, 1, 1, 1, 3, true, true),
    ('learning', 'evidence_correction', 7, 6, 0, 1, 3, 2, 0, 0, 3, 1, 3, true, true),
    ('learning', 'exercise_definition', 7, 6, 0, 1, 3, 3, 0, 1, 3, 1, 0, false, false),
    ('learning', 'exercise_instance', 9, 7, 0, 1, 2, 4, 0, 1, 3, 1, 3, true, true),
    ('learning', 'exercise_instance_item', 5, 5, 1, 1, 2, 1, 0, 1, 2, 0, 3, true, true),
    ('learning', 'exercise_item', 7, 5, 2, 1, 1, 2, 0, 1, 1, 0, 0, false, false),
    ('learning', 'exercise_revision', 8, 8, 1, 1, 1, 5, 0, 1, 1, 2, 0, false, false),
    ('learning', 'feedback_item', 7, 6, 0, 1, 2, 4, 0, 1, 2, 1, 3, true, true),
    ('learning', 'learner_profile', 5, 4, 0, 1, 1, 2, 0, 1, 1, 1, 3, true, true),
    ('learning', 'learning_evidence', 9, 8, 0, 1, 5, 2, 0, 1, 6, 1, 3, true, true),
    ('learning', 'study_activity', 7, 6, 0, 1, 1, 3, 0, 1, 1, 0, 3, true, true),
    ('learning', 'study_session', 8, 7, 0, 1, 3, 3, 0, 0, 4, 1, 3, true, true),
    ('learning', 'study_session_snapshot', 5, 4, 0, 1, 3, 1, 0, 0, 2, 0, 3, true, true),
    ('progress', 'competency_progress', 6, 6, 0, 1, 3, 2, 0, 1, 3, 1, 3, true, true),
    ('progress', 'learner_progress_projection', 5, 4, 1, 1, 1, 1, 0, 0, 0, 0, 3, true, true),
    ('progress', 'progress_contribution', 4, 4, 0, 1, 2, 2, 0, 0, 2, 1, 3, true, true),
    ('progress', 'progress_derivation', 7, 6, 0, 1, 2, 3, 0, 0, 2, 1, 3, true, true),
    ('progress', 'progress_history', 7, 6, 0, 1, 2, 3, 0, 0, 3, 1, 3, true, true),
    ('progress', 'resume_point', 8, 5, 0, 1, 5, 1, 0, 1, 5, 1, 3, true, true),
    ('progress', 'song_progress', 7, 6, 0, 1, 3, 2, 0, 1, 4, 1, 3, true, true),
    ('editorial', 'correction_case', 8, 7, 0, 1, 2, 3, 0, 1, 2, 0, 0, false, false),
    ('editorial', 'editorial_lock', 6, 6, 0, 1, 1, 2, 0, 1, 1, 0, 0, false, false),
    ('editorial', 'editorial_package', 9, 8, 0, 1, 2, 4, 0, 1, 2, 1, 0, false, false),
    ('editorial', 'package_component', 9, 4, 0, 1, 6, 3, 0, 1, 6, 1, 0, false, false),
    ('editorial', 'provenance_record', 7, 7, 0, 1, 2, 2, 0, 1, 2, 1, 0, false, false),
    ('editorial', 'publication', 10, 9, 0, 1, 3, 5, 1, 1, 4, 0, 0, false, false),
    ('editorial', 'publication_action', 10, 9, 0, 1, 3, 4, 0, 1, 3, 1, 0, false, false),
    ('editorial', 'publication_availability', 8, 6, 0, 1, 1, 5, 1, 0, 1, 0, 0, false, false),
    ('editorial', 'publication_component', 6, 6, 0, 1, 2, 3, 0, 1, 2, 1, 0, false, false),
    ('editorial', 'published_package_projection', 6, 5, 1, 1, 3, 1, 0, 0, 2, 0, 0, false, false),
    ('editorial', 'review_assignment', 7, 6, 0, 1, 2, 2, 0, 1, 2, 0, 0, false, false),
    ('editorial', 'review_decision', 7, 7, 1, 1, 2, 2, 0, 1, 2, 1, 0, false, false),
    ('editorial', 'review_submission', 6, 6, 0, 1, 2, 2, 0, 1, 3, 0, 0, false, false),
    ('editorial', 'rights_holder', 5, 4, 0, 1, 0, 4, 0, 0, 0, 0, 0, false, false),
    ('editorial', 'rights_record', 9, 6, 0, 1, 2, 4, 0, 0, 2, 0, 0, false, false),
    ('editorial', 'rights_scope', 6, 5, 0, 1, 1, 4, 0, 1, 1, 0, 0, false, false),
    ('configuration', 'business_calendar', 7, 6, 1, 1, 0, 4, 1, 0, 0, 1, 0, false, false),
    ('configuration', 'catalog_definition', 6, 6, 1, 1, 0, 4, 0, 1, 0, 1, 0, false, false),
    ('configuration', 'catalog_entry', 9, 8, 2, 1, 1, 4, 1, 0, 1, 1, 0, false, false),
    ('configuration', 'configuration_activation', 7, 7, 0, 1, 2, 2, 0, 1, 2, 1, 0, false, false),
    ('configuration', 'configuration_change_item', 7, 5, 0, 1, 3, 4, 0, 0, 3, 0, 0, false, false),
    ('configuration', 'configuration_change_set', 8, 6, 0, 1, 2, 3, 0, 0, 2, 1, 0, false, false),
    ('configuration', 'effective_parameter', 7, 6, 1, 1, 1, 3, 0, 1, 0, 0, 0, false, false),
    ('configuration', 'parameter_definition', 7, 6, 2, 1, 0, 4, 0, 1, 0, 0, 0, false, false),
    ('configuration', 'parameter_version', 10, 8, 1, 1, 1, 4, 1, 1, 2, 0, 0, false, false),
    ('configuration', 'retention_policy', 8, 8, 1, 1, 0, 5, 0, 1, 0, 1, 0, false, false),
    ('ops', 'background_job', 9, 8, 1, 1, 0, 5, 0, 0, 1, 0, 0, false, false),
    ('ops', 'data_quality_issue', 9, 8, 0, 1, 0, 6, 0, 1, 1, 0, 0, false, false),
    ('ops', 'idempotency_record', 9, 8, 1, 1, 1, 6, 0, 1, 2, 0, 3, true, true),
    ('ops', 'inbox_message', 5, 4, 0, 1, 1, 2, 0, 0, 1, 0, 0, false, false),
    ('ops', 'job_attempt', 8, 5, 0, 1, 1, 5, 0, 1, 1, 1, 0, false, false),
    ('ops', 'outbox_message', 11, 9, 1, 1, 0, 4, 0, 0, 1, 0, 0, false, false),
    ('ops', 'read_model_checkpoint', 6, 4, 0, 1, 0, 3, 0, 0, 0, 0, 0, false, false),
    ('ops', 'stored_object', 11, 10, 0, 1, 0, 10, 0, 1, 0, 0, 0, false, false);

DO $verify$
DECLARE
    expected record;
    relation_oid oid;
    actual_integer integer;
    actual_boolean boolean;
    actual_owner text;
    problem_list text;
BEGIN
    IF (SELECT count(*) FROM expected_physical_table) <> 109 THEN
        RAISE EXCEPTION 'Inventario de prueba invalido: no contiene 109 tablas.';
    END IF;

    SELECT string_agg(format('%I.%I', e.schema_name, e.table_name), ', ' ORDER BY e.schema_name, e.table_name)
    INTO problem_list
    FROM expected_physical_table e
    LEFT JOIN pg_catalog.pg_namespace n
      ON n.nspname = e.schema_name
    LEFT JOIN pg_catalog.pg_class c
      ON c.relnamespace = n.oid
     AND c.relname = e.table_name
     AND c.relkind IN ('r', 'p')
    WHERE c.oid IS NULL;

    IF problem_list IS NOT NULL THEN
        RAISE EXCEPTION 'Faltan tablas fisicas: %.', problem_list;
    END IF;

    SELECT string_agg(format('%I.%I', n.nspname, c.relname), ', ' ORDER BY n.nspname, c.relname)
    INTO problem_list
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n
      ON n.oid = c.relnamespace
    LEFT JOIN expected_physical_table e
      ON e.schema_name = n.nspname
     AND e.table_name = c.relname
    WHERE n.nspname = ANY (
        ARRAY['identity','security','catalog','content','learning','progress','editorial','configuration','ops']
    )
      AND c.relkind IN ('r', 'p')
      AND e.table_name IS NULL;

    IF problem_list IS NOT NULL THEN
        RAISE EXCEPTION 'Existen tablas fisicas no esperadas: %.', problem_list;
    END IF;

    FOR expected IN
        SELECT *
        FROM expected_physical_table
        ORDER BY schema_name, table_name
    LOOP
        SELECT c.oid, pg_catalog.pg_get_userbyid(c.relowner)
        INTO relation_oid, actual_owner
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n
          ON n.oid = c.relnamespace
        WHERE n.nspname = expected.schema_name
          AND c.relname = expected.table_name
          AND c.relkind IN ('r', 'p');

        IF actual_owner <> 'jp_owner' THEN
            RAISE EXCEPTION '%.%: propietario esperado jp_owner, encontrado %.',
                expected.schema_name, expected.table_name, actual_owner;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_attribute
        WHERE attrelid = relation_oid
          AND attnum > 0
          AND NOT attisdropped;

        IF actual_integer <> expected.column_count THEN
            RAISE EXCEPTION '%.%: columnas esperadas %, encontradas %.',
                expected.schema_name, expected.table_name, expected.column_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_attribute
        WHERE attrelid = relation_oid
          AND attnum > 0
          AND NOT attisdropped
          AND attnotnull;

        IF actual_integer <> expected.not_null_count THEN
            RAISE EXCEPTION '%.%: NOT NULL esperados %, encontrados %.',
                expected.schema_name, expected.table_name, expected.not_null_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_attribute
        WHERE attrelid = relation_oid
          AND attnum > 0
          AND NOT attisdropped
          AND atttypid = 'jsonb'::pg_catalog.regtype;

        IF actual_integer <> expected.jsonb_count THEN
            RAISE EXCEPTION '%.%: columnas jsonb esperadas %, encontradas %.',
                expected.schema_name, expected.table_name, expected.jsonb_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_constraint
        WHERE conrelid = relation_oid
          AND contype = 'p';

        IF actual_integer <> expected.pk_count THEN
            RAISE EXCEPTION '%.%: PK esperadas %, encontradas %.',
                expected.schema_name, expected.table_name, expected.pk_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_constraint
        WHERE conrelid = relation_oid
          AND contype = 'f';

        IF actual_integer <> expected.fk_count THEN
            RAISE EXCEPTION '%.%: FK esperadas %, encontradas %.',
                expected.schema_name, expected.table_name, expected.fk_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_constraint
        WHERE conrelid = relation_oid
          AND contype = 'c';

        IF actual_integer <> expected.check_count THEN
            RAISE EXCEPTION '%.%: CHECK de tabla esperados %, encontrados %.',
                expected.schema_name, expected.table_name, expected.check_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_constraint
        WHERE conrelid = relation_oid
          AND contype = 'x';

        IF actual_integer <> expected.exclusion_count THEN
            RAISE EXCEPTION '%.%: EXCLUDE esperados %, encontrados %.',
                expected.schema_name, expected.table_name, expected.exclusion_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class idx
          ON idx.oid = i.indexrelid
        WHERE i.indrelid = relation_oid
          AND i.indisunique
          AND NOT i.indisprimary
          AND left(idx.relname, 3) = 'ux_';

        IF actual_integer <> expected.unique_index_count THEN
            RAISE EXCEPTION '%.%: indices UX esperados %, encontrados %.',
                expected.schema_name, expected.table_name, expected.unique_index_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class idx
          ON idx.oid = i.indexrelid
        WHERE i.indrelid = relation_oid
          AND NOT i.indisunique
          AND left(idx.relname, 3) = 'ix_';

        IF actual_integer <> expected.nonunique_index_count THEN
            RAISE EXCEPTION '%.%: indices IX esperados %, encontrados %.',
                expected.schema_name, expected.table_name, expected.nonunique_index_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_trigger
        WHERE tgrelid = relation_oid
          AND NOT tgisinternal;

        IF actual_integer <> expected.trigger_count THEN
            RAISE EXCEPTION '%.%: triggers esperados %, encontrados %.',
                expected.schema_name, expected.table_name, expected.trigger_count, actual_integer;
        END IF;

        SELECT count(*)
        INTO actual_integer
        FROM pg_catalog.pg_policy
        WHERE polrelid = relation_oid;

        IF actual_integer <> expected.policy_count THEN
            RAISE EXCEPTION '%.%: politicas RLS esperadas %, encontradas %.',
                expected.schema_name, expected.table_name, expected.policy_count, actual_integer;
        END IF;

        SELECT c.relrowsecurity
        INTO actual_boolean
        FROM pg_catalog.pg_class c
        WHERE c.oid = relation_oid;

        IF actual_boolean IS DISTINCT FROM expected.rls_enabled THEN
            RAISE EXCEPTION '%.%: ENABLE RLS esperado %, encontrado %.',
                expected.schema_name, expected.table_name, expected.rls_enabled, actual_boolean;
        END IF;

        SELECT c.relforcerowsecurity
        INTO actual_boolean
        FROM pg_catalog.pg_class c
        WHERE c.oid = relation_oid;

        IF actual_boolean IS DISTINCT FROM expected.rls_forced THEN
            RAISE EXCEPTION '%.%: FORCE RLS esperado %, encontrado %.',
                expected.schema_name, expected.table_name, expected.rls_forced, actual_boolean;
        END IF;
    END LOOP;

    SELECT string_agg(n.nspname, ', ' ORDER BY n.nspname)
    INTO problem_list
    FROM pg_catalog.pg_namespace n
    WHERE n.nspname = ANY (
        ARRAY['identity','security','catalog','content','learning','progress','editorial','configuration','ops']
    )
      AND pg_catalog.pg_get_userbyid(n.nspowner) <> 'jp_owner';

    IF problem_list IS NOT NULL THEN
        RAISE EXCEPTION 'Esquemas cuyo propietario no es jp_owner: %.', problem_list;
    END IF;

    SELECT count(*)
    INTO actual_integer
    FROM pg_catalog.pg_namespace
    WHERE nspname = ANY (
        ARRAY['identity','security','catalog','content','learning','progress','editorial','configuration','ops']
    );

    IF actual_integer <> 9 THEN
        RAISE EXCEPTION 'Se esperaban 9 esquemas de aplicacion y existen %.', actual_integer;
    END IF;

    SELECT count(*)
    INTO actual_integer
    FROM pg_catalog.pg_views
    WHERE schemaname = ANY (
        ARRAY['identity','security','catalog','content','learning','progress','editorial','configuration','ops']
    );

    IF actual_integer <> 2 THEN
        RAISE EXCEPTION 'Se esperaban exactamente 2 vistas en los esquemas de aplicacion y existen %.', actual_integer;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_views
        WHERE schemaname = ANY (
            ARRAY['identity','security','catalog','content','learning','progress','editorial','configuration','ops']
        )
          AND (schemaname, viewname) NOT IN (
              ('catalog', 'v_public_song'),
              ('catalog', 'v_public_song_search')
          )
    ) THEN
        RAISE EXCEPTION 'Existen vistas de aplicacion no incluidas en la linea base.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_views
        WHERE (schemaname, viewname) IN (
            ('catalog', 'v_public_song'),
            ('catalog', 'v_public_song_search')
        )
          AND viewowner <> 'jp_owner'
    ) THEN
        RAISE EXCEPTION 'Las vistas publicas del catalogo no pertenecen a jp_owner.';
    END IF;

    SELECT count(*)
    INTO actual_integer
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n
      ON n.oid = p.pronamespace
    WHERE (n.nspname, p.proname) IN (
        ('ops', 'bump_version'),
        ('ops', 'prevent_mutation'),
        ('ops', 'guard_terminal_status'),
        ('ops', 'guard_evidence_mutation'),
        ('editorial', 'guard_package_component_mutable'),
        ('security', 'current_account_id')
    );

    IF actual_integer <> 6 THEN
        RAISE EXCEPTION 'Se esperaban 6 funciones auxiliares y existen %.', actual_integer;
    END IF;

    SELECT count(*)
    INTO actual_integer
    FROM pg_catalog.pg_policy p
    JOIN pg_catalog.pg_class c
      ON c.oid = p.polrelid
    JOIN pg_catalog.pg_namespace n
      ON n.oid = c.relnamespace
    WHERE n.nspname = ANY (
        ARRAY['identity','security','catalog','content','learning','progress','editorial','configuration','ops']
    )
      AND p.polwithcheck IS NOT NULL;

    IF actual_integer <> 99 THEN
        RAISE EXCEPTION 'Se esperaban 99 clausulas RLS WITH CHECK y existen %.', actual_integer;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE schemaname = 'security'
          AND tablename = 'account'
          AND policyname = 'p_account_bootstrap_owner'
    ) THEN
        RAISE EXCEPTION 'La politica temporal p_account_bootstrap_owner quedo persistida.';
    END IF;

    IF (SELECT count(*) FROM security.account) <> 1 THEN
        RAISE EXCEPTION 'Semilla invalida: security.account debe contener solo la cuenta SYSTEM.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM security.account
        WHERE account_id = '3a35b4fd-5e67-5686-9669-d5e78e20feaa'
          AND status_code = 'SYSTEM'
    ) THEN
        RAISE EXCEPTION 'Semilla invalida: falta la cuenta tecnica SYSTEM.';
    END IF;

    IF (
        SELECT coalesce(array_agg(role_code::text ORDER BY role_code::text), ARRAY[]::text[])
        FROM security.role
    ) <> ARRAY['ADMIN', 'EDITOR', 'REVIEWER', 'STUDENT']::text[] THEN
        RAISE EXCEPTION 'Semilla invalida: roles de producto distintos de STUDENT/EDITOR/REVIEWER/ADMIN.';
    END IF;

    IF (
        SELECT coalesce(array_agg(permission_code::text ORDER BY permission_code::text), ARRAY[]::text[])
        FROM security.permission
    ) <> ARRAY['CATALOG.SEARCH', 'CONFIG.APPROVE', 'CONFIG.MANAGE', 'CONTENT.READ', 'EDITORIAL.CORRECT', 'EDITORIAL.DRAFT', 'EDITORIAL.PUBLISH', 'EDITORIAL.REVIEW', 'EDITORIAL.SUBMIT', 'LEARNING.START', 'LEARNING.SUBMIT', 'OPS.REPROCESS', 'PRIVACY.PROCESS', 'PROFILE.READ', 'PROFILE.WRITE', 'PROGRESS.READ', 'SECURITY.MANAGE_ROLES', 'SECURITY.READ_AUDIT']::text[] THEN
        RAISE EXCEPTION 'Semilla invalida: conjunto de 18 permisos diferente al SQL maestro.';
    END IF;

    IF (SELECT count(*) FROM security.role_permission) <> 33 THEN
        RAISE EXCEPTION 'Semilla invalida: security.role_permission debe contener 33 filas.';
    END IF;

    IF (
        SELECT coalesce(array_agg(catalog_code::text ORDER BY catalog_code::text), ARRAY[]::text[])
        FROM configuration.catalog_definition
    ) <> ARRAY['ACCOUNT_STATUS', 'DATA_CLASS', 'INSTANCE_STATUS', 'JLPT_LEVEL', 'JOB_STATUS', 'LANGUAGE', 'PACKAGE_STATUS', 'PRIVACY_STATUS', 'PROVIDER', 'PUBLICATION_STATUS', 'REVISION_STATUS', 'SESSION_STATUS']::text[] THEN
        RAISE EXCEPTION 'Semilla invalida: conjunto de 12 catalogos distinto al SQL maestro.';
    END IF;

    IF (SELECT count(*) FROM configuration.catalog_entry) <> 59 THEN
        RAISE EXCEPTION 'Semilla invalida: configuration.catalog_entry debe contener 59 filas.';
    END IF;

    IF (
        SELECT coalesce(array_agg(parameter_key::text ORDER BY parameter_key::text), ARRAY[]::text[])
        FROM configuration.parameter_definition
    ) <> ARRAY['EDITORIAL_LOCK_SECONDS', 'IDEMPOTENCY_RETENTION_HOURS', 'JOB_ATTEMPT_RETENTION_DAYS', 'MAX_JOB_ATTEMPTS', 'MFA_REQUIRED_PRIVILEGED', 'PLAYER_SYNC_TOLERANCE_MS', 'PUBLICATION_DEFAULT_LANGUAGE', 'SEARCH_MIN_QUERY_LENGTH', 'SESSION_ABSOLUTE_HOURS', 'SESSION_IDLE_MINUTES']::text[] THEN
        RAISE EXCEPTION 'Semilla invalida: conjunto de 10 parametros distinto al SQL maestro.';
    END IF;

    IF (SELECT count(*) FROM configuration.parameter_version) <> 10
       OR (SELECT count(*) FROM configuration.effective_parameter) <> 10 THEN
        RAISE EXCEPTION 'Semilla invalida: versiones o parametros efectivos incompletos.';
    END IF;

    IF (SELECT count(*) FROM configuration.business_calendar) <> 1
       OR NOT EXISTS (
           SELECT 1
           FROM configuration.business_calendar
           WHERE calendar_code = 'DEFAULT_CR'
             AND time_zone = 'America/Costa_Rica'
       ) THEN
        RAISE EXCEPTION 'Semilla invalida: calendario DEFAULT_CR ausente o distinto.';
    END IF;

    IF (SELECT count(*) FROM configuration.retention_policy) <> 3 THEN
        RAISE EXCEPTION 'Semilla invalida: configuration.retention_policy debe contener 3 filas.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public."__EFMigrationsHistory"
        WHERE "MigrationId" = '202608080001_InitialPhysicalSchema'
    ) THEN
        RAISE EXCEPTION 'EF Core no registro InitialPhysicalSchema.';
    END IF;
END;
$verify$;

SELECT
    109 AS tables,
    752 AS columns,
    109 AS primary_keys,
    167 AS foreign_keys,
    70 AS unique_indexes,
    188 AS nonunique_indexes,
    356 AS table_check_constraints,
    99 AS rls_with_check_clauses,
    455 AS documented_check_predicates,
    8 AS exclusion_constraints,
    53 AS triggers,
    99 AS rls_policies,
    33 AS rls_enabled_tables,
    33 AS rls_forced_tables,
    'OK: las 109 tablas y la linea base fisica completa de BL-MVP-011 fueron verificadas.' AS result;
