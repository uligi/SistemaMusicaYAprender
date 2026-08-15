-- BL-MVP-012
-- Ejecutar conectado a la base objetivo con -v database_name=<identificador>.
-- No contiene secretos.

REVOKE CONNECT, TEMPORARY ON DATABASE :"database_name" FROM PUBLIC;

GRANT CONNECT ON DATABASE :"database_name"
    TO jp_migrator, jp_app, jp_backoffice, jp_worker, jp_readonly;

REVOKE CREATE, TEMPORARY ON DATABASE :"database_name"
    FROM jp_migrator, jp_app, jp_backoffice, jp_worker, jp_readonly;

-- El DDL embebido hace SET LOCAL ROLE jp_owner para crear los nueve esquemas.
GRANT CREATE ON DATABASE :"database_name" TO jp_owner;

-- BL-MVP-025. La búsqueda de reenvío es la única excepción pública al RLS
-- por propietario: devuelve solo el UUID opaco de una cuenta PENDING cuyo
-- hash de correo coincide. La función queda con search_path fijo y sin
-- privilegio PUBLIC; la API nunca devuelve este resultado al cliente.
DO $account_verification_lookup$
BEGIN
    IF to_regclass('security.account') IS NOT NULL THEN
        EXECUTE $function$
            CREATE OR REPLACE FUNCTION security.resolve_pending_account_for_verification(
                p_email_lookup_hash bytea
            )
            RETURNS uuid
            LANGUAGE sql
            STABLE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
                SELECT account.account_id
                FROM security.account AS account
                WHERE octet_length(p_email_lookup_hash) = 32
                  AND account.email_lookup_hash = p_email_lookup_hash
                  AND account.status_code = 'PENDING'
                  AND account.verified_at IS NULL
                LIMIT 1
            $body$
        $function$;

        REVOKE ALL ON FUNCTION security.resolve_pending_account_for_verification(bytea)
            FROM PUBLIC;
        GRANT EXECUTE ON FUNCTION security.resolve_pending_account_for_verification(bytea)
            TO jp_app;
    END IF;
END;
$account_verification_lookup$;

-- BL-MVP-026. El runtime solo puede resolver una credencial activa mediante
-- el hash HMAC del correo y una sesion mediante el hash SHA-256 del token
-- opaco. Las funciones fijan search_path, no aceptan valores de longitud
-- inesperada y no quedan disponibles para PUBLIC. Ningun dato se devuelve al
-- cliente; la API usa el resultado exclusivamente para autenticar y validar la
-- revocacion en el servidor.
DO $personal_session_access$
BEGIN
    IF to_regclass('security.account') IS NOT NULL
       AND to_regclass('security.credential') IS NOT NULL
       AND to_regclass('security.session') IS NOT NULL THEN
        EXECUTE $function$
            CREATE OR REPLACE FUNCTION security.resolve_active_password_credential(
                p_email_lookup_hash bytea
            )
            RETURNS TABLE (
                account_id uuid,
                credential_hash text,
                credential_algorithm varchar(64),
                credential_parameters text
            )
            LANGUAGE sql
            STABLE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
                SELECT
                    account.account_id,
                    credential.hash,
                    credential.algorithm,
                    credential.parameters
                FROM security.account AS account
                INNER JOIN security.credential AS credential
                    ON credential.account_id = account.account_id
                   AND credential.active
                WHERE octet_length(p_email_lookup_hash) = 32
                  AND account.email_lookup_hash = p_email_lookup_hash
                  AND account.status_code = 'ACTIVE'
                  AND account.verified_at IS NOT NULL
                LIMIT 1
            $body$
        $function$;

        EXECUTE $function$
            CREATE OR REPLACE FUNCTION security.resolve_active_session(
                p_session_hash bytea
            )
            RETURNS TABLE (
                session_id uuid,
                account_id uuid,
                assurance_level varchar(64),
                created_at timestamptz,
                idle_expires_at timestamptz,
                absolute_expires_at timestamptz
            )
            LANGUAGE sql
            STABLE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
                SELECT
                    session.session_id,
                    session.account_id,
                    session.assurance_level,
                    session.created_at,
                    session.idle_expires_at,
                    session.absolute_expires_at
                FROM security.session AS session
                INNER JOIN security.account AS account
                    ON account.account_id = session.account_id
                WHERE octet_length(p_session_hash) = 32
                  AND session.session_hash = p_session_hash
                  AND session.assurance_level IN ('PASSWORD', 'MFA')
                  AND session.revoked_at IS NULL
                  AND session.idle_expires_at > CURRENT_TIMESTAMP
                  AND session.absolute_expires_at > CURRENT_TIMESTAMP
                  AND account.status_code = 'ACTIVE'
                  AND account.verified_at IS NOT NULL
                LIMIT 1
            $body$
        $function$;

        EXECUTE $function$
            CREATE OR REPLACE FUNCTION security.revoke_active_session(
                p_session_hash bytea
            )
            RETURNS boolean
            LANGUAGE sql
            VOLATILE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
                WITH revoked AS (
                    UPDATE security.session AS session
                    SET revoked_at = CURRENT_TIMESTAMP
                    WHERE octet_length(p_session_hash) = 32
                      AND session.session_hash = p_session_hash
                      AND session.revoked_at IS NULL
                    RETURNING session.session_id
                )
                SELECT EXISTS (SELECT 1 FROM revoked)
            $body$
        $function$;

        REVOKE ALL ON FUNCTION security.resolve_active_password_credential(bytea)
            FROM PUBLIC;
        REVOKE ALL ON FUNCTION security.resolve_active_session(bytea)
            FROM PUBLIC;
        REVOKE ALL ON FUNCTION security.revoke_active_session(bytea)
            FROM PUBLIC;

        GRANT EXECUTE ON FUNCTION security.resolve_active_password_credential(bytea)
            TO jp_app;
        GRANT EXECUTE ON FUNCTION security.resolve_active_session(bytea)
            TO jp_app;
        GRANT EXECUTE ON FUNCTION security.revoke_active_session(bytea)
            TO jp_app;
    END IF;
END;
$personal_session_access$;


-- BL-MVP-032. El runtime administra solamente su propio método MFA.
-- security.mfa_method conserva RLS forzado por account_id.
DO $mfa_runtime_access$
BEGIN
    IF to_regclass('security.mfa_method') IS NOT NULL THEN
        GRANT SELECT, INSERT, UPDATE
            ON TABLE security.mfa_method
            TO jp_app;
    END IF;
END;
$mfa_runtime_access$;
-- BL-MVP-040. El pool backoffice no recibe INSERT directo sobre ops.stored_object.
-- Solo puede registrar metadata de evidencia M15 por esta funcion acotada.
DO $rights_evidence_registration$
BEGIN
    IF to_regclass('ops.stored_object') IS NOT NULL THEN
        EXECUTE $function$
            CREATE OR REPLACE FUNCTION ops.register_rights_evidence_object(
                p_object_id uuid,
                p_storage_key text,
                p_media_type text,
                p_size_bytes bigint,
                p_checksum bytea,
                p_encryption_key_ref text,
                p_created_at timestamptz,
                p_retention_until timestamptz,
                p_status_code text
            )
            RETURNS void
            LANGUAGE plpgsql
            VOLATILE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
            BEGIN
                IF p_object_id IS NULL
                   OR p_object_id = '00000000-0000-0000-0000-000000000000'::uuid
                   OR p_storage_key !~ '^objects/[0-9a-f]{32}[.]mae1$'
                   OR p_media_type NOT IN (
                       'application/pdf',
                       'text/plain',
                       'image/png',
                       'image/jpeg'
                   )
                   OR p_size_bytes <= 0
                   OR p_size_bytes > 2097152
                   OR octet_length(p_checksum) <> 32
                   OR p_encryption_key_ref IS NULL
                   OR length(p_encryption_key_ref) = 0
                   OR p_created_at IS NULL
                   OR p_status_code IS DISTINCT FROM 'ACTIVE' THEN
                    RAISE EXCEPTION 'Descriptor de evidencia M15 no valido.'
                        USING ERRCODE = '22023';
                END IF;

                INSERT INTO ops.stored_object (
                    object_id,
                    owner_module,
                    purpose_code,
                    storage_key,
                    media_type,
                    size_bytes,
                    checksum,
                    encryption_key_ref,
                    created_at,
                    retention_until,
                    status_code
                )
                VALUES (
                    p_object_id,
                    'M15',
                    'RIGHTS_EVIDENCE',
                    p_storage_key,
                    p_media_type,
                    p_size_bytes,
                    p_checksum,
                    p_encryption_key_ref,
                    p_created_at,
                    p_retention_until,
                    p_status_code
                );
            END
            $body$
        $function$;

        REVOKE ALL ON FUNCTION ops.register_rights_evidence_object(
            uuid, text, text, bigint, bytea, text, timestamptz, timestamptz, text
        ) FROM PUBLIC;

        GRANT EXECUTE ON FUNCTION ops.register_rights_evidence_object(
            uuid, text, text, bigint, bytea, text, timestamptz, timestamptz, text
        ) TO jp_backoffice;
    END IF;
END;
$rights_evidence_registration$;
-- BL-MVP-071. La autoría editorial M08 conserva el pool backoffice sin DML
-- directo sobre learning. Una función acotada solo puede crear/editar DRAFT
-- de completar espacios y revalida la fuente exacta y la ambigüedad básica.
DO $fill_blank_exercise_draft_access$
BEGIN
    IF to_regclass('learning.exercise_definition') IS NOT NULL
       AND to_regclass('learning.exercise_revision') IS NOT NULL
       AND to_regclass('learning.exercise_item') IS NOT NULL
       AND to_regclass('learning.competency') IS NOT NULL
       AND to_regclass('content.lyric_token') IS NOT NULL THEN
        EXECUTE $function$
            CREATE OR REPLACE FUNCTION learning.save_fill_blank_exercise_draft(
                p_recording_id uuid,
                p_line_id uuid,
                p_lyrics_revision_id uuid,
                p_token_id uuid,
                p_competency_code text,
                p_prompt text,
                p_distractors jsonb,
                p_explanation text,
                p_feedback_correct text,
                p_feedback_incorrect text,
                p_difficulty_code text,
                p_difficulty_justification text,
                p_checksum bytea
            )
            RETURNS TABLE (
                exercise_id uuid,
                exercise_revision_id uuid,
                revision_no integer,
                version bigint
            )
            LANGUAGE plpgsql
            VOLATILE
            SECURITY DEFINER
            SET search_path = pg_catalog
            AS $body$
            DECLARE
                v_actor uuid;
                v_correct_answer text;
                v_competency_id uuid;
                v_exercise_id uuid;
                v_revision_id uuid;
                v_revision_no integer;
                v_existing_status text;
                v_solution_spec jsonb;
                v_option text;
                v_option_order integer := 2;
                v_correct_key text;
                v_seen text[] := ARRAY[]::text[];
            BEGIN
                v_actor := nullif(current_setting('app.account_id', true), '')::uuid;
                IF v_actor IS NULL THEN
                    RAISE EXCEPTION 'Falta contexto de actor para autoría M08.'
                        USING ERRCODE = '42501';
                END IF;

                IF p_recording_id IS NULL
                   OR p_line_id IS NULL
                   OR p_lyrics_revision_id IS NULL
                   OR p_token_id IS NULL
                   OR p_prompt IS NULL
                   OR length(btrim(p_prompt)) = 0
                   OR p_explanation IS NULL
                   OR length(btrim(p_explanation)) = 0
                   OR p_feedback_correct IS NULL
                   OR length(btrim(p_feedback_correct)) = 0
                   OR p_feedback_incorrect IS NULL
                   OR length(btrim(p_feedback_incorrect)) = 0
                   OR p_difficulty_justification IS NULL
                   OR length(btrim(p_difficulty_justification)) = 0
                   OR p_difficulty_code NOT IN ('BEGINNER','INTERMEDIATE','ADVANCED')
                   OR octet_length(p_checksum) <> 32 THEN
                    RAISE EXCEPTION 'El borrador M08 no cumple campos obligatorios.'
                        USING ERRCODE = '22023';
                END IF;

                IF p_competency_code NOT IN (
                    'VOCAB.CONTEXT',
                    'GRAMMAR.CONTEXT',
                    'READING.CONTEXT'
                ) THEN
                    RAISE EXCEPTION 'Competencia M08 no permitida.'
                        USING ERRCODE = '22023';
                END IF;

                IF jsonb_typeof(p_distractors) IS DISTINCT FROM 'array'
                   OR jsonb_array_length(p_distractors) < 2
                   OR jsonb_array_length(p_distractors) > 4 THEN
                    RAISE EXCEPTION 'Se requieren entre 2 y 4 distractores.'
                        USING ERRCODE = '22023';
                END IF;

                SELECT token.surface
                INTO v_correct_answer
                FROM content.lyric_token AS token
                INNER JOIN content.lyric_line AS line
                    ON line.line_id = token.line_id
                INNER JOIN content.lyric_section AS section
                    ON section.section_id = line.section_id
                INNER JOIN content.lyrics_revision AS lyrics
                    ON lyrics.lyrics_revision_id = section.lyrics_revision_id
                WHERE token.token_id = p_token_id
                  AND line.line_id = p_line_id
                  AND lyrics.lyrics_revision_id = p_lyrics_revision_id
                  AND lyrics.recording_id = p_recording_id
                  AND lyrics.status_code = 'DRAFT';

                IF v_correct_answer IS NULL THEN
                    RAISE EXCEPTION 'El espacio no pertenece a la revisión DRAFT exacta.'
                        USING ERRCODE = '23503';
                END IF;

                v_correct_key := lower(
                    regexp_replace(btrim(v_correct_answer), '\s+', ' ', 'g')
                );

                FOR v_option IN
                    SELECT value
                    FROM jsonb_array_elements_text(p_distractors) AS value
                LOOP
                    v_option := btrim(v_option);
                    IF length(v_option) = 0 THEN
                        RAISE EXCEPTION 'Un distractor está vacío.'
                            USING ERRCODE = '22023';
                    END IF;

                    IF lower(regexp_replace(v_option, '\s+', ' ', 'g')) = v_correct_key THEN
                        RAISE EXCEPTION 'Un distractor coincide con la respuesta.'
                            USING ERRCODE = '22023';
                    END IF;

                    IF lower(regexp_replace(v_option, '\s+', ' ', 'g')) = ANY(v_seen) THEN
                        RAISE EXCEPTION 'Hay distractores repetidos.'
                            USING ERRCODE = '22023';
                    END IF;

                    v_seen := array_append(
                        v_seen,
                        lower(regexp_replace(v_option, '\s+', ' ', 'g'))
                    );
                END LOOP;

                INSERT INTO learning.competency (
                    competency_code,
                    domain_code,
                    title,
                    definition
                )
                VALUES (
                    p_competency_code,
                    CASE p_competency_code
                        WHEN 'VOCAB.CONTEXT' THEN 'VOCABULARY'
                        WHEN 'GRAMMAR.CONTEXT' THEN 'GRAMMAR'
                        ELSE 'READING'
                    END,
                    CASE p_competency_code
                        WHEN 'VOCAB.CONTEXT' THEN 'Vocabulario en contexto'
                        WHEN 'GRAMMAR.CONTEXT' THEN 'Gramática en contexto'
                        ELSE 'Comprensión de la línea'
                    END,
                    CASE p_competency_code
                        WHEN 'VOCAB.CONTEXT' THEN 'Reconocer una palabra o expresión dentro de la línea exacta.'
                        WHEN 'GRAMMAR.CONTEXT' THEN 'Reconocer una construcción gramatical dentro de la línea exacta.'
                        ELSE 'Reconocer una unidad que completa correctamente la línea.'
                    END
                )
                ON CONFLICT (competency_code) DO NOTHING;

                SELECT competency.competency_id
                INTO v_competency_id
                FROM learning.competency AS competency
                WHERE competency.competency_code = p_competency_code;

                INSERT INTO learning.exercise_definition (
                    recording_id,
                    line_id,
                    exercise_type,
                    competency_id,
                    status_code
                )
                VALUES (
                    p_recording_id,
                    p_line_id,
                    'FILL_BLANK_OPTIONS',
                    v_competency_id,
                    'DRAFT'
                )
                ON CONFLICT DO NOTHING;

                SELECT definition.exercise_id
                INTO v_exercise_id
                FROM learning.exercise_definition AS definition
                WHERE definition.recording_id = p_recording_id
                  AND definition.line_id = p_line_id
                  AND definition.exercise_type = 'FILL_BLANK_OPTIONS'
                  AND definition.competency_id = v_competency_id;

                SELECT revision.exercise_revision_id,
                       revision.revision_no,
                       revision.status_code
                INTO v_revision_id, v_revision_no, v_existing_status
                FROM learning.exercise_revision AS revision
                WHERE revision.exercise_id = v_exercise_id
                ORDER BY revision.revision_no DESC
                LIMIT 1
                FOR UPDATE;

                v_solution_spec := jsonb_build_object(
                    'schemaVersion', 1,
                    'answerModel', 'SINGLE_CHOICE',
                    'acceptedItemOrders', jsonb_build_array(1),
                    'explanation', btrim(p_explanation),
                    'feedback', jsonb_build_object(
                        'correct', btrim(p_feedback_correct),
                        'incorrect', btrim(p_feedback_incorrect)
                    ),
                    'difficulty', jsonb_build_object(
                        'code', p_difficulty_code,
                        'justification', btrim(p_difficulty_justification)
                    ),
                    'blank', jsonb_build_object(
                        'tokenId', p_token_id,
                        'surface', v_correct_answer
                    )
                );

                IF v_revision_id IS NOT NULL AND v_existing_status = 'DRAFT' THEN
                    UPDATE learning.exercise_revision
                    SET prompt = btrim(p_prompt),
                        solution_spec = v_solution_spec,
                        checksum = p_checksum
                    WHERE learning.exercise_revision.exercise_revision_id = v_revision_id;

                    DELETE FROM learning.exercise_item
                    WHERE learning.exercise_item.exercise_revision_id = v_revision_id;
                ELSE
                    v_revision_no := COALESCE(v_revision_no, 0) + 1;

                    INSERT INTO learning.exercise_revision (
                        exercise_id,
                        revision_no,
                        prompt,
                        solution_spec,
                        status_code,
                        checksum
                    )
                    VALUES (
                        v_exercise_id,
                        v_revision_no,
                        btrim(p_prompt),
                        v_solution_spec,
                        'DRAFT',
                        p_checksum
                    )
                    RETURNING learning.exercise_revision.exercise_revision_id
                    INTO v_revision_id;
                END IF;

                INSERT INTO learning.exercise_item (
                    exercise_revision_id,
                    item_type,
                    item_order,
                    prompt_fragment,
                    expected_value,
                    metadata
                )
                VALUES (
                    v_revision_id,
                    'OPTION',
                    1,
                    v_correct_answer,
                    to_jsonb(v_correct_answer),
                    jsonb_build_object(
                        'role', 'CORRECT',
                        'sourceTokenId', p_token_id
                    )
                );

                FOR v_option IN
                    SELECT value
                    FROM jsonb_array_elements_text(p_distractors) AS value
                LOOP
                    INSERT INTO learning.exercise_item (
                        exercise_revision_id,
                        item_type,
                        item_order,
                        prompt_fragment,
                        expected_value,
                        metadata
                    )
                    VALUES (
                        v_revision_id,
                        'OPTION',
                        v_option_order,
                        btrim(v_option),
                        to_jsonb(btrim(v_option)),
                        jsonb_build_object('role', 'DISTRACTOR')
                    );
                    v_option_order := v_option_order + 1;
                END LOOP;

                RETURN QUERY
                SELECT
                    v_exercise_id,
                    revision.exercise_revision_id,
                    revision.revision_no,
                    revision.version
                FROM learning.exercise_revision AS revision
                WHERE revision.exercise_revision_id = v_revision_id;
            END
            $body$
        $function$;

        REVOKE ALL ON FUNCTION learning.save_fill_blank_exercise_draft(
            uuid, uuid, uuid, uuid, text, text, jsonb, text, text, text, text, text, bytea
        ) FROM PUBLIC;

        GRANT EXECUTE ON FUNCTION learning.save_fill_blank_exercise_draft(
            uuid, uuid, uuid, uuid, text, text, jsonb, text, text, text, text, text, bytea
        ) TO jp_backoffice;
    END IF;
END;
$fill_blank_exercise_draft_access$;
-- BL-MVP-041. La proyeccion publica es derivada y reconstruible. El worker
-- puede retirar exclusivamente filas obsoletas de esta proyeccion; no recibe
-- DELETE sobre publication, availability, catalogo ni evidencia canonica.
DO $public_catalog_projection_access$
BEGIN
    IF to_regclass('editorial.published_package_projection') IS NOT NULL THEN
        GRANT DELETE ON TABLE editorial.published_package_projection TO jp_worker;
    END IF;
END;
$public_catalog_projection_access$;

-- BL-MVP-042. song_search_document es una proyeccion derivada. El worker
-- puede retirar exclusivamente documentos obsoletos; la API conserva lectura.
DO $public_catalog_search_access$
BEGIN
    IF to_regclass('catalog.song_search_document') IS NOT NULL THEN
        GRANT DELETE ON TABLE catalog.song_search_document TO jp_worker;
    END IF;
END;
$public_catalog_search_access$;

-- EF Core mantiene __EFMigrationsHistory en public. Solo el rol de migracion
-- puede crear/gestionar esa tabla; los roles runtime no reciben CREATE.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO jp_migrator;
REVOKE CREATE ON SCHEMA public
    FROM jp_app, jp_backoffice, jp_worker, jp_readonly;

DO $history$
BEGIN
    IF to_regclass('public."__EFMigrationsHistory"') IS NOT NULL THEN
        ALTER TABLE public."__EFMigrationsHistory" OWNER TO jp_migrator;
        REVOKE ALL ON TABLE public."__EFMigrationsHistory" FROM PUBLIC;
    END IF;
END;
$history$;
